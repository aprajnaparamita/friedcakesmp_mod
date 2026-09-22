#!/usr/bin/env bash
# ============================================================================
# setup_qwen_vl.sh — Fully configure a vast.ai instance to run
# Qwen2.5-VL-72B-Instruct against the Donut SMP frames.
#
# What it does:
#   1. Pre-flight checks (GPUs, VRAM, RAM, disk)
#   2. Installs system + Python dependencies
#   3. Downloads Qwen2.5-VL-72B-Instruct (~145 GB) with resume support
#   4. Launches vLLM in a tmux session ("vllm") so it survives SSH disconnects
#   5. Polls the /v1/models endpoint until ready
#   6. Runs a smoke test (single image inference)
#   7. Prints next-step instructions
#
# Usage on the instance:
#   bash setup_qwen_vl.sh
#
# Idempotent: safe to re-run; downloads resume, tmux session is replaced.
# ============================================================================

set -euo pipefail

# ---- config ----
MODEL_REPO="${MODEL_REPO:-Qwen/Qwen2.5-VL-72B-Instruct}"
MODEL_NAME="${MODEL_REPO##*/}"
MODEL_DIR="${MODEL_DIR:-/root/models/$MODEL_NAME}"
VLLM_PORT="${VLLM_PORT:-8000}"
TP_SIZE="${TP_SIZE:-2}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
MIN_DISK_GB=200
MIN_RAM_GB=80
MIN_VRAM_GB=150
GPU_COUNT_MIN=2

# ---- ui ----
G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; B=$'\033[36m'; N=$'\033[0m'
step() { printf "\n${B}==>${N} ${B}%s${N}\n" "$1"; }
ok()   { printf "  ${G}✓${N} %s\n" "$1"; }
warn() { printf "  ${Y}!${N} %s\n" "$1"; }
die()  { printf "  ${R}✗ %s${N}\n" "$1" >&2; exit 1; }
hr()   { printf "${B}%s${N}\n" "------------------------------------------------------------"; }

# ---- 0. sanity: are we on a GPU box? ----
command -v nvidia-smi >/dev/null || die "nvidia-smi not found — not a GPU instance?"

# ---- 1. pre-flight ----
step "1/7 Pre-flight checks"
hr

# GPUs
mapfile -t GPU_LINES < <(nvidia-smi -L)
GPU_COUNT=${#GPU_LINES[@]}
[ "$GPU_COUNT" -ge "$GPU_COUNT_MIN" ] \
    || die "Need ≥${GPU_COUNT_MIN} GPUs for tensor-parallel. Found ${GPU_COUNT}."
ok "${GPU_COUNT} GPUs detected"

# VRAM
VRAM_GB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits \
          | awk '{s+=$1} END {printf "%d", s/1024}')
[ "$VRAM_GB" -ge "$MIN_VRAM_GB" ] \
    || die "Need ≥${MIN_VRAM_GB} GB total VRAM. Found ${VRAM_GB} GB."
ok "Total VRAM: ${VRAM_GB} GB"

# CUDA version
CUDA_VER=$(nvidia-smi | awk -F'CUDA Version: ' '/CUDA Version/ {print $2}' | awk '{print $1; exit}')
ok "CUDA runtime: ${CUDA_VER:-unknown}"

# RAM
RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
[ "$RAM_GB" -ge "$MIN_RAM_GB" ] \
    || die "Need ≥${MIN_RAM_GB} GB RAM. Found ${RAM_GB} GB."
ok "RAM: ${RAM_GB} GB"

# Disk
DISK_GB=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
[ "$DISK_GB" -ge "$MIN_DISK_GB" ] \
    || die "Need ≥${MIN_DISK_GB} GB free on /. Found ${DISK_GB} GB. Provision more disk."
ok "Free disk: ${DISK_GB} GB"

# Python
PY=$(command -v python3 || true)
[ -n "$PY" ] || die "python3 not found."
ok "Python: $($PY --version 2>&1)"

# ---- 2. apt deps ----
step "2/7 System packages"
hr
if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq tmux git aria2 nvtop >/dev/null 2>&1 || \
        apt-get install -y -qq tmux git aria2 >/dev/null
    ok "apt: tmux, git, aria2 installed"
else
    warn "apt-get not found — assuming deps already present"
fi

# ---- 3. pip deps ----
step "3/7 Python packages"
hr
pip install -U --quiet \
    "vllm>=0.6" \
    "qwen-vl-utils" \
    "Pillow" \
    "requests" \
    "huggingface_hub" \
    "hf_transfer"
ok "pip: vllm, qwen-vl-utils, Pillow, requests, huggingface_hub, hf_transfer"

# ---- 4. model download ----
step "4/7 Download model (${MODEL_REPO})"
hr
mkdir -p "$MODEL_DIR"
# Use Xet-based high-performance transfers (the modern replacement for hf_transfer)
export HF_XET_HIGH_PERFORMANCE=1
hf download "$MODEL_REPO" \
    --local-dir "$MODEL_DIR"
ok "Model downloaded to ${MODEL_DIR}"
echo "  Disk used by model:"
du -sh "$MODEL_DIR" | sed 's/^/    /'

# Quick sanity check on weights
SHARD_COUNT=$(ls "$MODEL_DIR"/model-*-of-*.safetensors 2>/dev/null | wc -l | tr -d ' ')
[ "$SHARD_COUNT" -gt 0 ] || die "No safetensors shards found in $MODEL_DIR"
ok "Found ${SHARD_COUNT} weight shards"

# ---- 5. launch vLLM in tmux ----
step "5/7 Launch vLLM (tmux session 'vllm')"
hr
tmux kill-session -t vllm 2>/dev/null || true

# Build the launch command with proper JSON for --limit-mm-per-prompt
LAUNCH_CMD=$(cat <<EOF
vllm serve "$MODEL_DIR" 
  --tensor-parallel-size ${TP_SIZE} 
  --max-model-len ${MAX_MODEL_LEN} 
  --limit-mm-per-prompt '{"image":1}' 
  --port ${VLLM_PORT} 
  --host 0.0.0.0 
  --served-model-name "${MODEL_NAME}" 2>&1 | tee -a /tmp/vllm.log
EOF
)
# collapse newlines into a single command line
LAUNCH_CMD=$(printf '%s' "$LAUNCH_CMD" | tr '\n' ' ')

tmux new-session -d -s vllm "$LAUNCH_CMD"
ok "vLLM launched in tmux session 'vllm'"

# ---- 6. wait for ready ----
step "6/7 Waiting for vLLM to become ready"
hr
READY=0
for i in $(seq 1 90); do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${VLLM_PORT}/v1/models" \
        | grep -q "200"; then
        ok "vLLM ready (after ~$((i*10))s)"
        READY=1
        break
    fi
    # Show last line of log every minute
    if [ $((i % 6)) -eq 0 ]; then
        echo "  still waiting... last log line:"
        tail -1 /tmp/vllm.log 2>/dev/null | sed 's/^/    /' || true
    fi
    sleep 10
done

if [ "$READY" -ne 1 ]; then
    die "vLLM did not become ready in 15 min. Last 40 log lines:"
    tail -40 /tmp/vllm.log >&2 || true
fi

curl -s "http://localhost:${VLLM_PORT}/v1/models" | head -c 500
echo

# ---- 7. smoke test ----
step "7/7 Smoke test"
hr
cat > /tmp/smoke_test.py <<'PY'
import base64, json, os, sys
import requests
from PIL import Image, ImageDraw

# Make a synthetic test image with text on it
img = Image.new("RGB", (1024, 768), (40, 40, 50))
d = ImageDraw.Draw(img)
for i, line in enumerate(["HELLO", "WORLD"]):
    d.rectangle([100 + i*20, 100 + i*80, 400 + i*20, 200 + i*80],
                fill=(255, 255, 255))
img.save("/tmp/smoke.png", "JPEG", quality=85)

b64 = base64.b64encode(open("/tmp/smoke.png", "rb").read()).decode()
payload = {
    "model": os.environ.get("MODEL_NAME", "Qwen2.5-VL-72B-Instruct"),
    "messages": [{
        "role": "user",
        "content": [
            {"type": "image_url",
             "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            {"type": "text",
             "text": "Describe this image in one sentence."},
        ],
    }],
    "max_tokens": 128,
    "temperature": 0.2,
}
r = requests.post(
    f"http://localhost:{os.environ.get('VLLM_PORT', '8000')}/v1/chat/completions",
    json=payload, timeout=120,
)
r.raise_for_status()
content = r.json()["choices"][0]["message"]["content"]
print(f"Smoke test response: {content!r}")
if not content or len(content) < 5:
    print("ERROR: empty/short response", file=sys.stderr)
    sys.exit(1)
print("OK")
PY

MODEL_NAME="$MODEL_NAME" VLLM_PORT="$VLLM_PORT" python3 /tmp/smoke_test.py \
    || die "Smoke test failed — see output above"
ok "Smoke test passed"

# ---- done ----
hr
echo "${G}✓ Instance fully configured and validated.${N}"
echo
echo "  Model:       ${MODEL_REPO}"
echo "  Endpoint:    http://localhost:${VLLM_PORT}/v1"
echo "  vLLM tmux:   vllm   (attach with:  tmux a -t vllm)"
echo "  vLLM log:    /tmp/vllm.log   (tail -f)"
echo
echo "  Next step:"
echo "    1) Upload frames/ and run_qwen_vl_describe.py to the instance"
echo "    2) Run:    python3 run_qwen_vl_describe.py"
echo "    3) When done, download:"
echo "         frame_descriptions_vlm.md"
echo "         frame_descriptions_vlm.json"
echo "         frame_descriptions_vlm.csv"
echo
echo "  Cost-control:"
echo "    tmux kill-session -t vllm        # stop vLLM (saves nothing — instance still bills)"
echo "    vllm serve ... --max-model-len 4096  # reduce memory pressure"
echo "    VLM_MODEL=Qwen/Qwen2.5-VL-7B-Instruct python3 run_qwen_vl_describe.py  # use 7B"
hr