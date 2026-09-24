# Donut SMP UI Recreation — Handoff Document
*Last updated: 2026-09-22 (session 3 — SPEC COMPLETE)*

> **Session 3 update:** all `spec/features/f01–f16` files now exist, plus
> `spec/plan/{roadmap,open-questions,acceptance-tests}.md`. New in session 3:
> `f08-teleport`, `f10-combat`, `f13-ranks`, `f14-stats`, `f15-world-rules`,
> `f16-legacy` and the three plan files. The spec set is complete; next step
> is implementation per `spec/plan/roadmap.md`, and resolving open questions
> (`spec/plan/open-questions.md`) against live-server captures.

> **Engine source-of-truth (update from session 4):** the local checkouts
> below are fresher than any pinned commit referenced elsewhere in the spec
> or handoff. Always verify against them before quoting API behaviour,
> formspec syntax, or game.conf fields.
>
> - **Mineclonia (latest):** `~/dev/mineclonia-git` — clone of
>   `mineclonia/mineclonia`, tracking upstream `main`. Use this for any
>   reference to Mineclonia mod structure, default mods, crafts, spawn
>   tables, or API mods it bundles.
> - **Luanti (updated):** `~/dev/luanti` — local checkout of the Luanti
>   engine. Use this for any reference to Lua API, formspec, builtin
>   privileges, mod security, or engine defaults.
>
> Do **not** assume the commit SHA in `spec/README.md` ("verified against
> GitHub mirror, commit `5bdce566`, 2026-09-21") is the latest — that mirror
> is stale relative to `~/dev/mineclonia-git`.

## Goal

Recreate the Donut SMP (a public Minecraft Java server) UI in the open-source
**Mineclonia** game engine (Luanti / Minetest). Output is a structured UI spec
per feature, ready to translate into Mineclonia Lua + formspec code.

Source material: a 5-minute YouTube tutorial walking through every command
and menu. We extract frames at 1 fps, describe each UI element via a vision-
language model, and aggregate into per-feature specs.

## Local Mac (development machine)

- Owner: `dara@Daras-MacBook-Pro`
- Working directory: `/Volumes/Dara/dev/coconut/`

### SSH config (this machine)

```
Host vast
    HostName 174.78.228.101
    Port 41442
    User root
    IdentityFile ~/.ssh/vast_ops   # passphrase-less ops key
```

`~/.ssh/vast_ops.pub` is the public key added to vast.ai. The passphrase-
protected key (`~/.ssh/id_ed25519` or `~/.ssh/dara`) is for normal ssh; this
ops key lets non-interactive agents drive the instance.

### Local files of interest

| Path | What |
|---|---|
| `setup_qwen_vl.sh` | Provisioning script for the vast.ai instance (run once) |
| `run_qwen_vl_describe.py` | Client that POSTs frames to vLLM and collects descriptions |
| `frames/frame_NNNN.jpg` (×141) | 1920×1080 1-fps frames from the source video |
| `thumbnail_grid.jpg` | 4152×2830 contact sheet of all 305 frames (pre-deletion) |
| `feature_index.md` | Feature-segment boundaries with key frames |
| `frame_index.csv` | Every frame ↔ timestamp ↔ subtitle (from SRT) |
| `topics.md` | Full second-by-second subtitle timeline |
| `*.en-orig.srt`, `*.en.srt` | SubRip subtitles (manual + auto) from yt-dlp |
| `*.mp4` | Original downloaded 1080p MP4 |

## vast.ai instance

### Identity

- **Instance ID**: `C.51991581`
- **Template**: Oklahoma, 2× RTX PRO 6000 (Blackwell, cc12.0), 96 GB VRAM total
- **Host**: `174.78.228.101:41442` (SSH on container port 22)
- **OS**: Ubuntu 24.04, kernel 6.8
- **Image**: vast.ai PyTorch base (preinstalled `torch@cu130` in `/venv/main`)
- **DRIVER**: 595.84, max CUDA 13.2
- **System CUDA libs**: 12.8 (partial — `cublas`, `cudnn`, etc. present)
- **Storage**: 191 GB free on `/` (model takes ~145 GB)

### Connect

```bash
ssh vast 'echo "connected as $(whoami)"'
```

Or with explicit key:

```bash
ssh -i ~/.ssh/vast_ops -p 41442 root@174.78.228.101
```

### Vast.ai guidance for AI agents

`/etc/vast-agents-guide.md` is required reading for any AI agent operating
on this instance. Key points:

- This is a **Docker container, not a VM** — no kernel modules, no
  Docker-in-Docker, no sysctls.
- Long-running services should use **supervisor**, not loose tmux sessions.
  (Exception: throwaway jobs like ours use tmux.)
- `/workspace` is **NOT** automatically persistent — it's a volume mount
  *if* one is attached. On this instance: `vast-capabilities | jq
  '.instance.workspace_is_volume'` is `false`, so **nothing survives
  destroy/recycle**. Sync irreplaceable data off-box.
- For external Caddy-fronted apps, use `portal.yaml` + `OPEN_BUTTON_TOKEN`.
  We don't need this — our inference endpoint is on `127.0.0.1:8000` only.
- Use `uv pip install` in `/venv/main` (not bare pip) — `uv` is faster and
  the image default. We used `pip` and it works fine; consistency-wise,
  prefer `uv` going forward.
- `vastai` CLI is available with `$CONTAINER_API_KEY` set.

### Live environment snapshot

```bash
vast-capabilities | jq '{image:.image, gpu:.hardware.gpu, open_ports:.instance.open_ports}'
```

## Python environment

- **Venv root**: `/venv/main` (already activated in login shells)
- **Activation**: `source /venv/main/bin/activate`
- **System python**: `python3` (3.12)
- **PyTorch stack (preinstalled by image)**: torch, torchvision, torchaudio
  were *upgraded* by our pip installs — see "Current versions" below.

### Current versions (as of handoff)

```
torch           2.14.0+cu130
torchvision     0.29.0+cu130     (re-installed, was 0.28.0 — see "Bug saga")
torchaudio      2.11.0+cu130     (re-installed to match torch's CUDA)
vllm            0.29.0
flashinfer-python  0.6.13        (downgraded from 0.6.18 — see "Bug saga")
flashinfer-cubin   0.6.13        (must EXACTLY match flashinfer-python)
transformers    5.17.0
```

**Critical version rule**: `flashinfer-python` and `flashinfer-cubin` MUST
have the same version. flashinfer-cubin has a hard runtime check that raises
`RuntimeError: flashinfer-cubin version does not match flashinfer version` if
they differ. Only flashinfer-python releases ship a paired cubin — 0.6.18 had
no matching cubin, so we use the 0.6.13 pair.

## Files on the instance

| Path | Size | What |
|---|---|---|
| `/root/models/Qwen2.5-VL-72B-Instruct/` | ~145 GB | 38 safetensors shards + tokenizer/config |
| `/root/work/frames/frame_NNNN.jpg` | ~25 MB | 141 frames copied from local |
| `/root/work/run_qwen_vl_describe.py` | ~10 KB | The describer client |
| `/root/work/setup_qwen_vl.sh` | ~8 KB | Setup script (latest, patched) |
| `/root/work/_progress_vlm.json` | — | Incremental progress (created by describer) |
| `/root/work/frame_descriptions_vlm.{md,csv,json}` | — | Outputs (not yet created) |
| `/tmp/vllm.log` | growing | vLLM stdout/stderr |

## Workflow

### 1. Start vLLM (one command)

```bash
source /venv/main/bin/activate
tmux kill-session -t vllm 2>/dev/null
pkill -f "vllm serve" 2>/dev/null
sleep 3
> /tmp/vllm.log
tmux new-session -d -s vllm "VLLM_USE_FLASHINFER_SAMPLER=0 \
vllm serve /root/models/Qwen2.5-VL-72B-Instruct \
    --tensor-parallel-size 2 \
    --max-model-len 8192 \
    --limit-mm-per-prompt '{\"image\":1}' \
    --enforce-eager \
    --port 8000 \
    --host 0.0.0.0 \
    --served-model-name 'Qwen/Qwen2.5-VL-72B-Instruct' 2>&1 | tee -a /tmp/vllm.log"
```

`--enforce-eager` skips CUDA graph capture (faster startup, ~2x slower per
inference step, irrelevant for 141 image-captioning frames).
`VLLM_USE_FLASHINFER_SAMPLER=0` keeps flashinfer-comm (for tensor-parallel
all-reduce) but uses the pure-PyTorch top-k/top-p sampler instead of
flashinfer-sample (which was failing for unrelated reasons).

### 2. Wait for ready (3-5 min)

```bash
sleep 240
curl -s http://localhost:8000/v1/models | python3 -m json.tool
```

Should return:
```json
{
  "object": "list",
  "data": [
    {"id": "Qwen/Qwen2.5-VL-72B-Instruct", "object": "model", ...}
  ]
}
```

### 3. Run the describer

```bash
cd /root/work
python3 run_qwen_vl_describe.py
```

Live output:
```
[1/141] frame_0037.jpg  00:00:36
[2/141] frame_0055.jpg  00:00:54
...
```

It writes `_progress_vlm.json` after every frame — safe to Ctrl-C and rerun
(skip is automatic).

### 4. Pull results back to local Mac

```bash
scp -P 41442 -o IdentityFile=~/.ssh/vast_ops \
    root@174.78.228.101:/root/work/frame_descriptions_vlm.md \
    /Volumes/Dara/dev/coconut/
scp -P 41442 -o IdentityFile=~/.ssh/vast_ops \
    root@174.78.228.101:/root/work/frame_descriptions_vlm.csv \
    /Volumes/Dara/dev/coconut/
scp -P 41442 -o IdentityFile=~/.ssh/vast_ops \
    root@174.78.228.101:/root/work/frame_descriptions_vlm.json \
    /Volumes/Dara/dev/coconut/
```

(Or `scp vast:/root/work/frame_descriptions_vlm.md ./` if SSH config is set.)

### 5. Destroy the instance to stop billing

In vast.ai panel → **Destroy** (not stop). Storage still bills on stop.

## Bug saga (read this before "fixing" anything)

1. **Original `setup_qwen_vl.sh` had stale CLI syntax.**
   - `huggingface-cli` was deprecated → swapped to `hf` (PyPI's modern CLI).
   - `--local-dir-use-symlinks False` was removed → removed flag.
   - `HF_HUB_ENABLE_HF_TRANSFER=1` was deprecated → swapped to
     `HF_XET_HIGH_PERFORMANCE=1`.
   - `huggingface_hub[cli]` extra was deprecated → removed `cli` extra.

2. **First vLLM crash: `Detected that PyTorch and TorchAudio were compiled
   with different CUDA versions.`** Torch CUDA 13.0, torchaudio CUDA 12.8.
   - Fixed: `pip install torchaudio==2.11.0 --index-url
     https://download.pytorch.org/whl/cu130`. This pulls a wheel tagged
     `torchaudio-2.11.0+cu130`.

3. **Second vLLM crash: `RuntimeError: operator torchvision::nms does not
   exist.`** After upgrading flashinfer, torch got bumped to 2.14.0 but
   torchvision stayed at 0.28.0 (compiled for older torch).
   - Fixed: `pip install torchvision==0.29.0+cu130 --index-url
     https://download.pytorch.org/whl/cu130 --no-deps`.

4. **Third vLLM crash: `flashinfer-cubin version (0.6.13) does not match
   flashinfer version (0.6.18).`** vLLM 0.29.0 wants flashinfer-python==0.6.18
   but no matching cubin ships; vLLM's flashinfer.comm import triggers the
   hard version check on import.
   - Fixed: downgrade `flashinfer-python==0.6.13` to match the available
     `flashinfer-cubin==0.6.13`. vLLM tolerates this because flashinfer.comm
     is just the all-reduce kernel, not the sampling kernel.

5. **RESOLVED — bug saga item 5 was `apache-tvm-ffi` + `nvidia-cutlass-dsl`
   version drift.** After fixing flashinfer, vLLM crashed again with
   `terminate called after throwing an instance of 'tvm::ffi::Error':
   TypeAttr __ffi_repr__ is already registered for type index 132`.
   Root cause: `apache-tvm-ffi==0.1.14.post0` and `nvidia-cutlass-dsl==4.8.0`
   were installed (the latest), but vLLM 0.29.0 explicitly pins
   `apache-tvm-ffi==0.1.11` and `nvidia-cutlass-dsl[cu13]==4.6.2`.
   Fix: pin all four deps in one shot with `--no-deps`:
   ```bash
   pip install 'apache-tvm-ffi==0.1.11' \
              'nvidia-cutlass-dsl[cu13]==4.6.2' \
              'setuptools>=77.0.3,<81.0.0' --force-reinstall --no-deps
   ```
   Then restart vLLM with all the env vars — it works.

### Final working vLLM launch command

```bash
tmux new-session -d -s vllm "FLASHINFER_DISABLE_VERSION_CHECK=1 \
VLLM_USE_FLASHINFER_SAMPLER=0 \
vllm serve /root/models/Qwen2.5-VL-72B-Instruct \
    --tensor-parallel-size 2 \
    --max-model-len 8192 \
    --limit-mm-per-prompt '{\"image\":1}' \
    --enforce-eager \
    --port 8000 \
    --host 0.0.0.0 \
    --served-model-name 'Qwen/Qwen2.5-VL-72B-Instruct' 2>&1 | tee -a /tmp/vllm.log"
```

The three FLASHINFER env vars are all needed:
- `FLASHINFER_DISABLE_VERSION_CHECK=1` — cubin (0.6.13) lags python (0.6.18); bypass version mismatch check
- `VLLM_USE_FLASHINFER_SAMPLER=0` — use PyTorch top-k/top-p sampler, not flashinfer-sample
- (no explicit `VLLM_USE_FLASHINFER_ALL_REDUCE` needed — flashinfer all-reduce self-disables for world_size=2)

## Script fixes applied to `run_qwen_vl_describe.py`

1. **SRT file glob** — `ROOT.glob("*.en-orig.srt")` failed because the
   filename contains `[k-YgSy19y7I]` (YouTube video ID in brackets) which
   Python's `glob` interprets as a character class. Fixed: use
   `iterdir()` + substring match.
2. **`ROOT` hardcoded to `/Volumes/Dara/dev/coconut`** — only valid on the
   Mac. Fixed: derive from `Path(__file__).parent` with `VLM_ROOT` env
   var override.

## Cost notes

- This instance: ~$2.034/hr (Oklahoma #47198826), full GPU billing.
- Setup script: ~25 min = $0.85.
- vLLM model load: ~5 min = $0.17.
- Describer: ~90 min for 141 frames = $3.05.
- **Total expected for full run: $4-5.**
- Stop billing now: destroy the instance.

## Open questions / next steps after handoff

1. ✅ **vLLM is serving** (bug saga item 5 resolved).
2. ✅ **Describer completed** — all 141 frames described, 0 errors, results
   pulled back to local Mac.
3. ✅ **Description quality verified** — chat text captured verbatim
   (some OCR errors on heavily-pixelated text, expected), menu titles
   accurate, spatial layouts correct, hover/active states noted.
4. Extract per-feature specs (one .md per feature segment) and write the
   Mineclonia formspec for each.
5. If descriptions are bad: try Qwen2.5-VL-7B (cheaper, faster, slightly
   less accurate) or LLaVA-OneVision-7B as a comparison.

## Run summary

- Started: ~03:40 UTC (vLLM ready), 03:51 UTC (describer started)
- Finished: 04:56 UTC (141/141 frames done, files written)
- Total runtime: ~76 minutes end-to-end
- Frames: 141/141, 0 errors
- Output files in `/Volumes/Dara/dev/coconut/`:
  - `frame_descriptions_vlm.md` (293 KB, 7892 lines)
  - `frame_descriptions_vlm.csv` (296 KB, structured)
  - `frame_descriptions_vlm.json` (318 KB, structured)
- vLLM process killed after run; instance can be destroyed.

## Next agent's task: extract per-feature UI specs

Use `frame_descriptions_vlm.md` as the source. The descriptions are already
grouped under `## <feature name>` headers. For each feature, produce a
`specs/<feature>.md` file with:

- Menu structure (title, layout, sections)
- Every UI element with verbatim text + position
- Trigger command(s) (e.g. `/rtp`, `/ah`, `/orders`)
- Interaction sequence (open → input → confirm → result)
- State transitions (where things change based on selection)
- Mineclonia implementation hints (which formspec elements to use:
  `formspec_version[]`, `size[]`, `button[]`, `list[]`, `field[]`, etc.)

## Quick-reference commands

```bash
# State check
ssh vast 'tmux ls; nvidia-smi --query-gpu=memory.free --format=csv,noheader; ls /root/work/'

# Live progress while describer runs
ssh vast 'python3 -c "import json; print(len(json.load(open(\"/root/work/_progress_vlm.json\"))[\"done\"]))"'

# Restart vLLM cleanly
ssh vast 'tmux kill-session -t vllm 2>/dev/null; pkill -f "vllm serve" 2>/dev/null; sleep 3; \
  source /venv/main/bin/activate && \
  tmux new-session -d -s vllm "VLLM_USE_FLASHINFER_SAMPLER=0 \
  vllm serve /root/models/Qwen2.5-VL-72B-Instruct \
    --tensor-parallel-size 2 --max-model-len 8192 \
    --limit-mm-per-prompt '{\"image\":1}' --enforce-eager \
    --port 8000 --host 0.0.0.0 \
    --served-model-name 'Qwen/Qwen2.5-VL-72B-Instruct' 2>&1 | tee -a /tmp/vllm.log"'

# Attach to vLLM log (Ctrl-B D to detach)
ssh -t vast 'tmux a -t vllm'
```
---

## Session 4 Resumption (2026-09-25) — Fix Wave Status

**Current `main`:** `59e7eaa` (27/27 gate green)

### Merged this session (all gated, no conflicts)
| Feature | Merge Commit | Files | Gate | Key Outcomes |
|---|---|---|---|---|
| f14 (stats) | `36ed1c9` | 7 | 26/26 | S1/S2 verify-only; S3–S7 closed; 4 escalations in §10 |
| f11-finish (social) | `f528d68` | 8 | 26/26 | `follow_blocked`, `blocks_only`, D10 honesty, contract test; unblocks f08 TP13 |
| f12 (settings) | `9c57fad` | 6 | 26/26 | F12-1 ⚠ triangle both renders, F12-4 T9 leg in `test_social`, F12-2/3 → D3, F12-7 → D7 |
| f01 (economy) | `eb2fa2e` | 8 | **27/27** | 18 rows closed (E-01 wiring, E-18 `give` clamp, E-20 M2 codec, E-22 settings chain), 8 escalated; new `test_items.lua` |

### Integrator Decisions Executed (commit `5c6cc81` + `59e7eaa`)
- **V-48 = block-only payments** — `/pay` calls `smp_social.blocks_only()` (not `blocks()`); `/ignore` no longer refuses. V-48 assertions in `test_economy`.
- **F-1 = guarded call-only** — no `optional_depends = smp_social` on economy; documented in `shared/02-architecture.md` §2.1.
- **E-12 fixed** — `/smp_backend` chat output via translator.
- **E-21 fixed** — `auto` backend probes `lsqlite3` via `sqlite_available()`.
- **E-05/06/15/17/19 backlogged** as D13 store-hardening.
- **F-2 accepted** — `shared/05` `/smp` row widened to `reload｜test <mod>｜backend`.
- **F-3 accepted** — `shared/05` gains `/payto` (PROPOSED, `economy.tab_complete` gate).
- **F-5 routed** — row **F12-8** added to `fixes/f12-settings.md` (register `eco.pay_accept`).
- **F-6 split** — quickbuy fixed; orders → new row **O9** in `fixes/f04-orders.md`; bounty → overseer post-f10.
- **test_economy V-48 assertion corrected** (`59e7eaa`): `-100` cents not `-1` (float precision at 1e15).

### Active Agents (re-dispatched 2026-09-25, same worktrees/bases)
| Feature | Worktree | Branch | Base | Status |
|---|---|---|---|---|
| f07 (spawners) | coconut-f07 | agent/f07-spawner-fixes | 5413d08 | Running |
| f08 (teleport) | coconut-f08 | agent/f08-teleport-fixes | 2b5f16c | Running (TP13 unblocked) |
| f06 (shards) | coconut-f06 | agent/f06-shard-fixes | 2b5f16c | Running (owns cycle cut + F06-11) |
| f03 (auction) | coconut-f03 | agent/f03-auction-fixes | 2b5f16c | Running (owns `ah.history` drain) |
| f10 (combat) | coconut-f10 | agent/f10-combat-fixes | 2b5f16c | Running (C4 + engine evidence) |

### Deliberately Held
- **f04 (orders)** → after f06 merges (shares `orders→shardshop→amethyst→orders` cycle)
- **f09 (homes)** → after f08 merges (same `smp_tp` mod)

### Open Escalations
| Item | Owner | Next |
|---|---|---|
| D13 backlog (5 store/core items) | integrator | Schedule when authorized |
| f10 C4 + F-6 bounty period | f10 agent / overseer post-f10 | Same file set |
| f12 F12-8 (`eco.pay_accept`) | follow-up f12 dispatch | f12 already merged once |
| f08 TP13 (rtpqueue→blocks_only) | f08 agent | Will close when f08 reports |

### Next Steps When Agents Report
1. Review → merge → 27/27 gate → annotate `fixes/README.md` → STATUS entry
2. After f06 → dispatch f04
3. After f08 → dispatch f09
4. After f10 → overseer sweep (bounty period, F12-8) → wave C (f02, f13)
