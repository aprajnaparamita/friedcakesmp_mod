#!/usr/bin/env python3
"""Build navigation aids for the extracted frames:
  - thumbnail_grid.jpg : all 305 frames in a labeled grid for quick visual scanning
  - feature_index.md   : chronological feature guide with key frames per feature
  - feature_index.csv  : machine-readable version of the same
"""
import csv
import re
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path("/Volumes/Dara/dev/coconut")
FRAMES_DIR = ROOT / "frames"

# ---- Manual feature boundaries derived from topics.md ----
# (start_seconds, feature_name)
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

# ---- Thumbnail grid ----
THUMB_W, THUMB_H = 240, 135      # 16:9 downscale from 1920x1080
COLS = 17
PAD = 4
LABEL_H = 18
FONT_PATH_CANDIDATES = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNSMono.ttf",
    "/Library/Fonts/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

def get_font(size: int):
    for p in FONT_PATH_CANDIDATES:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def build_grid():
    frames = sorted(FRAMES_DIR.glob("frame_*.jpg"))
    n = len(frames)
    rows = (n + COLS - 1) // COLS
    grid_w = COLS * THUMB_W + (COLS + 1) * PAD
    grid_h = rows * (THUMB_H + LABEL_H) + (rows + 1) * PAD

    canvas = Image.new("RGB", (grid_w, grid_h), (16, 16, 16))
    draw = ImageDraw.Draw(canvas)
    font = get_font(13)

    for i, fp in enumerate(frames, start=1):
        r = (i - 1) // COLS
        c = (i - 1) % COLS
        x = PAD + c * (THUMB_W + PAD)
        y = PAD + r * (THUMB_H + LABEL_H + PAD)
        img = Image.open(fp).convert("RGB").resize((THUMB_W, THUMB_H), Image.LANCZOS)
        canvas.paste(img, (x, y))
        # label: "frame_0042 @ 0:42"
        secs = i - 1
        m, s = divmod(secs, 60)
        label = f"#{i:04d}  {m}:{s:02d}"
        draw.rectangle([x, y + THUMB_H, x + THUMB_W, y + THUMB_H + LABEL_H], fill=(0, 0, 0))
        draw.text((x + 4, y + THUMB_H + 2), label, fill=(255, 255, 255), font=font)

    out = ROOT / "thumbnail_grid.jpg"
    canvas.save(out, quality=88, optimize=True)
    print(f"Wrote {out}  ({canvas.size[0]}x{canvas.size[1]}, {out.stat().st_size/1_048_576:.1f} MB)")

# ---- Feature index ----
def hms(t):
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = int(t % 60)
    return f"{h:02d}:{m:02d}:{s:02d}"

def parse_srt(path: Path):
    content = path.read_text(encoding="utf-8")
    blocks = re.split(r"\r?\n\r?\n+", content.strip())
    cues = []
    for block in blocks:
        lines = block.splitlines()
        if len(lines) < 2:
            continue
        ts_idx = next((i for i, l in enumerate(lines) if "-->" in l), -1)
        if ts_idx < 0:
            continue
        m = re.match(
            r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})",
            lines[ts_idx],
        )
        if not m:
            continue
        start = int(m.group(1))*3600 + int(m.group(2))*60 + int(m.group(3)) + int(m.group(4))/1000
        text = " ".join(l.strip() for l in lines[ts_idx+1:] if l.strip())
        cues.append((start, text))
    return cues

def find_active(cues, t):
    for s, txt in cues:
        if s <= t < s + 5:  # approximate: a cue covers a short window
            return txt
    return ""

def main():
    build_grid()
    cues = parse_srt(next(ROOT.glob("*.en-orig.srt")))

    # feature_index.md
    md = ROOT / "feature_index.md"
    with md.open("w", encoding="utf-8") as f:
        f.write("# Donut SMP — Feature Index\n\n")
        f.write("Quick map from each feature shown in the video to its starting "
                "timestamp and the first 3 frames showing it.\n\n")
        f.write("| # | Time | Feature | First frames | What the speaker is doing |\n")
        f.write("|---|------|---------|--------------|----------------------------|\n")
        total_frames = sum(1 for _ in FRAMES_DIR.glob("frame_*.jpg"))
        for idx, (start, name) in enumerate(FEATURES):
            first_frames = [n for n in range(start + 1, start + 4) if 1 <= n <= total_frames]
            sample = find_active(cues, start + 2) or ""
            frame_links = ", ".join(f"`frame_{n:04d}.jpg`" for n in first_frames)
            f.write(f"| {idx} | `{hms(start)}` | **{name}** | {frame_links} | {sample} |\n")
    print(f"Wrote {md}")

    # feature_index.csv
    csv_path = ROOT / "feature_index.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["feature_index", "start_hms", "start_seconds", "feature", "frame_range"])
        for idx, (start, name) in enumerate(FEATURES):
            w.writerow([idx, hms(start), start, name, f"frame_{start+1:04d}.jpg - frame_{start+8:04d}.jpg"])
    print(f"Wrote {csv_path}")

if __name__ == "__main__":
    main()