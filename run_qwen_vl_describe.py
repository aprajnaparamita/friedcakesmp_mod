#!/usr/bin/env python3
"""
Run Qwen2.5-VL-72B-Instruct (via OpenAI-compatible vLLM endpoint) over every
remaining frame in frames/ and produce structured UI descriptions.

Usage on a vast.ai instance:

    # 1) Install + launch vLLM (in one terminal)
    pip install -U vllm qwen-vl-utils
    vllm serve Qwen/Qwen2.5-VL-72B-Instruct \
        --tensor-parallel-size 2 \
        --max-model-len 8192 \
        --limit-mm-per-prompt '{"image": 1}' \
        --port 8000 \
        --host 0.0.0.0

    # 2) In another terminal, run this script
    python3 run_qwen_vl_describe.py

Outputs:
    - frame_descriptions_vlm.json   full structured results
    - frame_descriptions_vlm.md     human-readable report grouped by feature
    - frame_descriptions_vlm.csv    one row per frame (frame, time, feature, raw)
    - _progress.json               incremental progress (so resumes survive crashes)
"""
from __future__ import annotations
import base64
import csv
import json
import os
import re
import time
from pathlib import Path
import requests

ENDPOINT       = os.environ.get("VLM_ENDPOINT", "http://localhost:8000/v1/chat/completions")
MODEL          = os.environ.get("VLM_MODEL", "Qwen/Qwen2.5-VL-72B-Instruct")
MAX_TOKENS     = int(os.environ.get("VLM_MAX_TOKENS", "2048"))
TEMPERATURE    = float(os.environ.get("VLM_TEMPERATURE", "0.2"))
# Default to the directory containing this script; allow override via env var
ROOT           = Path(os.environ.get("VLM_ROOT", Path(__file__).resolve().parent))
FRAMES_DIR     = Path(os.environ.get("VLM_FRAMES_DIR", ROOT / "frames"))
PROGRESS_FILE  = ROOT / "_progress_vlm.json"
JSON_OUT       = ROOT / "frame_descriptions_vlm.json"
MD_OUT         = ROOT / "frame_descriptions_vlm.md"
CSV_OUT        = ROOT / "frame_descriptions_vlm.csv"

# Feature boundaries (seconds -> name). Must match feature_index.md.
FEATURES = [
    (0,   "Intro — joining the server (donutsmp.net)"),
    (21,  "/rtp — random teleport"),
    (43,  "/sethome + /homes — set home, rename, delete, change icon"),
    (87,  "/pay + /sell — send money, quick-sell items"),
    (107, "/ah / /auction — auction house browse & search"),
    (127, "/ah — putting your own items up for auction"),
    (154, "/orders — fulfilling other players' buy orders"),
    (184, "/orders — creating your own buy order"),
    (231, "/settings — chat, PvP, privacy toggles"),
    (267, "/msg + /ignore — private messages and ignore list"),
    (304, "Outro"),
]

# Prompt designed for UI reverse-engineering. Don't edit lightly; tested phrasing.
SYSTEM_PROMPT = """You are an expert UI/UX reverse-engineer documenting a Minecraft
server's custom menus and HUD elements so they can be faithfully recreated in
another game engine (Luanti / MineClone2). Be extremely detailed, structured,
and faithful to what is literally visible in the screenshot.

For every frame, structure your response with these exact markdown sections:

## View Type
One sentence: gameplay view with HUD / fullscreen menu / modal overlay / chat-only / etc.

## UI Name & Layout
If a menu is open: its title text (verbatim), its on-screen position
(top of screen / center modal / side panel / etc.), approximate size as a
fraction of the screen (e.g. "occupies middle 60% of screen"), and background
style (opaque / translucent dark / border / etc.).

## Visible Elements
A bulleted list. For each element give:
  - Element type (button / tab / list row / icon / input field / checkbox / slider / label / chat line / hotbar slot / health bar / etc.)
  - Position (e.g. "top-left of panel, second from top")
  - Verbatim text content. If unreadable, write `[unreadable]` rather than guess.

## Selected / Active State
What is highlighted, focused, hovered, or being typed.

## World Context
Briefly describe the 3D scene behind the UI: terrain (biome, blocks), mobs,
player position/orientation, time of day, weather. Skip if fully occluded.

## User Action
One sentence: what the player is most likely doing at this moment
(opening a menu, typing a command, browsing items, etc.).

Rules:
- Do NOT invent details. If something is unclear, say "[unreadable]" or "obscured".
- Pay extra attention to small text — chat lines, button labels, item names.
- Preserve exact spelling, capitalization, and punctuation of on-screen text.
- If a chat message is cut off, note "truncated at top/bottom"."""

# ---------- helpers ----------

def feature_for(t: float) -> str:
    name = FEATURES[0][1]
    for s, n in FEATURES:
        if t >= s:
            name = n
        else:
            break
    return name

def hms(t: float) -> str:
    h = int(t // 3600); m = int((t % 3600) // 60); s = int(t % 60)
    return f"{h:02d}:{m:02d}:{s:02d}"

def parse_srt(path: Path):
    cues = []
    for block in re.split(r"\r?\n\r?\n+", path.read_text(encoding="utf-8").strip()):
        lines = block.splitlines()
        if len(lines) < 2: continue
        ts_idx = next((i for i, l in enumerate(lines) if "-->" in l), -1)
        if ts_idx < 0: continue
        m = re.match(
            r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})",
            lines[ts_idx])
        if not m: continue
        start = int(m.group(1))*3600+int(m.group(2))*60+int(m.group(3))+int(m.group(4))/1000
        text = " ".join(l.strip() for l in lines[ts_idx+1:] if l.strip())
        cues.append((start, text))
    return cues

def find_active(cues, t):
    for s, txt in cues:
        if s <= t < s + 5:
            return txt
    return ""

def load_progress():
    if PROGRESS_FILE.exists():
        return json.loads(PROGRESS_FILE.read_text())
    return {"done": {}}

def save_progress(p):
    PROGRESS_FILE.write_text(json.dumps(p))

def encode_image(path: Path) -> str:
    with path.open("rb") as f:
        return base64.b64encode(f.read()).decode("ascii")

def describe_frame(frame_path: Path, subtitle: str, retries: int = 3) -> str:
    img_b64 = encode_image(frame_path)
    user_text = "Describe this Minecraft screenshot following the schema exactly."
    if subtitle:
        user_text += f'\n\nFor additional context, the speaker in the video is saying: "{subtitle}"'

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{img_b64}"}},
                {"type": "text", "text": user_text},
            ]},
        ],
        "max_tokens": MAX_TOKENS,
        "temperature": TEMPERATURE,
    }
    last_err = None
    for attempt in range(retries):
        try:
            r = requests.post(ENDPOINT, json=payload, timeout=600)
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"]
        except Exception as e:
            last_err = e
            print(f"  retry {attempt+1}/{retries}: {e}", flush=True)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"Failed after {retries} retries: {last_err}")

# ---------- main ----------

def main():
    # Use iterdir + substring match — filenames contain [brackets] which
    # Python's glob treats as character classes and never matches.
    srt_files = [p for p in ROOT.iterdir()
                 if p.is_file() and p.suffix == ".srt" and ".en-orig" in p.name]
    if not srt_files:
        raise FileNotFoundError(f"No *.en-orig.srt in {ROOT}")
    cues = parse_srt(srt_files[0])
    progress = load_progress()
    frames = sorted(FRAMES_DIR.glob("frame_*.jpg"),
                    key=lambda p: int(p.stem.split("_")[1]))
    print(f"Frames to process: {len(frames)}  (already done: {len(progress['done'])})")

    for i, fp in enumerate(frames, start=1):
        n = int(fp.stem.split("_")[1])
        key = str(n)
        if key in progress["done"]:
            continue
        t = n - 1
        subtitle = find_active(cues, t)
        print(f"[{i}/{len(frames)}] frame_{n:04d}.jpg  {hms(t)}", flush=True)
        try:
            desc = describe_frame(fp, subtitle)
            progress["done"][key] = {
                "frame": n,
                "time_seconds": t,
                "time_hms": hms(t),
                "feature": feature_for(t),
                "subtitle": subtitle,
                "description": desc,
            }
            save_progress(progress)
        except Exception as e:
            print(f"  SKIPPED: {e}", flush=True)
            progress["done"][key] = {
                "frame": n, "time_seconds": t, "time_hms": hms(t),
                "feature": feature_for(t), "subtitle": subtitle,
                "description": f"[ERROR: {e}]",
            }
            save_progress(progress)

    # Write final outputs
    rows = [progress["done"][str(int(p.stem.split('_')[1]))]
            for p in frames if str(int(p.stem.split('_')[1])) in progress["done"]]
    JSON_OUT.write_text(json.dumps(rows, indent=2, ensure_ascii=False))
    print(f"Wrote {JSON_OUT}")

    with CSV_OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["frame", "time_hms", "time_seconds", "feature", "subtitle", "description"])
        for r in rows:
            w.writerow([r["frame"], r["time_hms"], r["time_seconds"],
                        r["feature"], r["subtitle"], r["description"]])
    print(f"Wrote {CSV_OUT}")

    with MD_OUT.open("w", encoding="utf-8") as f:
        f.write("# Donut SMP — Frame Descriptions (Qwen2.5-VL-72B)\n\n")
        f.write(f"Model: `{MODEL}` · Frames: {len(rows)}\n\n")
        f.write("---\n")
        last_feat = None
        for r in rows:
            if r["feature"] != last_feat:
                f.write(f"\n## {r['feature']}\n\n")
                last_feat = r["feature"]
            f.write(f"### frame_{r['frame']:04d}.jpg — {r['time_hms']}\n\n")
            if r["subtitle"]:
                f.write(f"**Speaker:** {r['subtitle']}\n\n")
            f.write(r["description"] + "\n\n---\n\n")
    print(f"Wrote {MD_OUT}")


if __name__ == "__main__":
    main()