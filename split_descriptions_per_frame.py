#!/usr/bin/env python3
"""Split frame_descriptions_vlm.json into one .json per frame.

For each frame in the combined descriptions file, write a sibling file in
frames/ with the same basename but .json extension:

    frames/frame_0037.jpg
    frames/frame_0037.json   <-- new

Each .json contains:
  - frame:           int, the frame number
  - time_hms:        "HH:MM:SS"
  - time_seconds:    int
  - feature:         the Donut SMP feature segment this frame belongs to
  - subtitle:        what the speaker is saying at this timestamp
  - description:     the VLM's full 6-section structured output (raw text)

Run from anywhere; the script uses absolute paths to the project root.
"""
import json
from pathlib import Path

ROOT = Path("/Volumes/Dara/dev/coconut")
SRC  = ROOT / "frame_descriptions_vlm.json"
FRAMES_DIR = ROOT / "frames"

def main():
    data = json.loads(SRC.read_text(encoding="utf-8"))
    print(f"Source: {SRC.name}  ({len(data)} frames)")

    written = 0
    for entry in data:
        frame_n = entry["frame"]
        # frame_NNNN.json — same basename, .json extension
        out = FRAMES_DIR / f"frame_{frame_n:04d}.json"
        # Keep only the fields the user needs; preserve order
        record = {
            "frame":        entry["frame"],
            "time_hms":     entry["time_hms"],
            "time_seconds": entry["time_seconds"],
            "feature":      entry["feature"],
            "subtitle":     entry["subtitle"],
            "description":  entry["description"],
        }
        out.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
        written += 1

    print(f"Wrote {written} files to {FRAMES_DIR}/frame_NNNN.json")
    # Sanity check: count actual files vs expected
    on_disk = sorted(FRAMES_DIR.glob("frame_*.json"))
    print(f"On disk: {len(on_disk)} .json files (expected {len(data)})")


if __name__ == "__main__":
    main()