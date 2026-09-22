#!/usr/bin/env python3
"""Build a CSV mapping every extracted frame (1 fps) to its active subtitle(s).

Inputs:
  - frames/frame_NNNN.jpg  (1 fps extraction)
  - *.en-orig.srt          (manual English subtitles)

Outputs:
  - frame_index.csv        columns: frame, time, time_hms, subtitle
  - topics.md              chronological topic guide (one bullet per SRT entry)
"""
import csv
import re
from pathlib import Path

ROOT = Path("/Volumes/Dara/dev/coconut")
SRT_FILE = next(ROOT.glob("*.en-orig.srt"))
FRAMES_DIR = ROOT / "frames"

# ---- Parse SRT ----
def parse_srt(path: Path):
    """Return list of (start_sec, end_sec, text)."""
    content = path.read_text(encoding="utf-8")
    # split on blank lines into blocks
    blocks = re.split(r"\r?\n\r?\n+", content.strip())
    cues = []
    for block in blocks:
        lines = block.splitlines()
        if len(lines) < 2:
            continue
        # find the timestamp line; on rare SRT variants the index line is missing
        ts_idx = next((i for i, l in enumerate(lines) if "-->" in l), -1)
        if ts_idx < 0:
            continue
        m = re.match(
            r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})",
            lines[ts_idx],
        )
        if not m:
            continue
        start = (
            int(m.group(1)) * 3600
            + int(m.group(2)) * 60
            + int(m.group(3))
            + int(m.group(4)) / 1000
        )
        end = (
            int(m.group(5)) * 3600
            + int(m.group(6)) * 60
            + int(m.group(7))
            + int(m.group(8)) / 1000
        )
        text_lines = lines[ts_idx + 1 :]
        text = " ".join(l.strip() for l in text_lines if l.strip())
        cues.append((start, end, text))
    return cues


def find_active(cues, t: float):
    """Return the first cue that contains time t, else None."""
    for s, e, txt in cues:
        if s <= t < e:
            return txt
    return None


def hms(t: float) -> str:
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = int(t % 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def main():
    cues = parse_srt(SRT_FILE)
    print(f"Parsed {len(cues)} subtitle cues from {SRT_FILE.name}")

    frames = sorted(FRAMES_DIR.glob("frame_*.jpg"))
    print(f"Found {len(frames)} frames")

    # Build CSV
    csv_path = ROOT / "frame_index.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["frame", "time_seconds", "time_hms", "filename", "subtitle"])
        for i, frame_path in enumerate(frames, start=1):
            t = i - 1  # frame N is at second N-1 (0-indexed)
            subtitle = find_active(cues, t) or ""
            w.writerow([i, f"{t:.2f}", hms(t), frame_path.name, subtitle])
    print(f"Wrote {csv_path}")

    # Build topics.md
    md_path = ROOT / "topics.md"
    with md_path.open("w", encoding="utf-8") as f:
        f.write("# Donut SMP — Topic Timeline\n\n")
        f.write(
            "Each subtitle cue in the video, with the second-precise timestamp. "
            "Use these to locate the corresponding `frame_NNNN.jpg` in `frames/`.\n\n"
        )
        f.write("| # | Time | Subtitle |\n|---|------|----------|\n")
        for idx, (s, e, txt) in enumerate(cues, start=1):
            f.write(f"| {idx} | `{hms(s)}` | {txt} |\n")
    print(f"Wrote {md_path}")


if __name__ == "__main__":
    main()