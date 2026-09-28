#!/usr/bin/env python3
"""Dev-time capture of a non-gameplay screen's tile cells (needs MAME output).

usage: capture_screen.py NAME CAM RECORDING.ram:FIRST-LAST [RECORDING.ram:FIRST-LAST ...]
Reads a tools/diff/mame_record.lua recording (8KB per vblank handler: work RAM
then video RAM), collects every (bg attr, bg tile, fg attr, fg tile) cell in
the camera window (player-view rows CAM..CAM+23, playfield columns) over
handlers FIRST..LAST, picks a signature cell (an fg tile constant over the
whole run, unusual elsewhere), and writes tools/data/screens/NAME.txt, which
tools/gen_screens.py turns into a tile set. Commit the .txt.
"""
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REC = 8192


def main():
    name, cam = sys.argv[1], int(sys.argv[2])
    combos = Counter()
    const = None
    frames = []
    for spec in sys.argv[3:]:
        path, rng = spec.rsplit(":", 1)
        first, last = (int(x) for x in rng.split("-"))
        d = Path(path).read_bytes()
        frames += [d[h * REC + 4096:(h + 1) * REC] for h in range(first, min(last + 1, len(d) // REC))]
    for v in frames:
        cells = {}
        for sy in range(24):
            c = 31 - (sy + cam)
            for sx in range(24):
                o = (sx + 4) * 32 + c
                k = (v[o], v[0x400 + o], v[0x800 + o], v[0xC00 + o])
                combos[k] += 1
                cells[o] = v[0xC00 + o]
        const = cells if const is None else {o: t for o, t in const.items() if cells.get(o) == t}
    # signature: a constant fg tile that is not blank, dirt, tunnel or font
    cand = [(o, t) for o, t in const.items() if t >= 0xC0 or 0x40 <= t < 0x72]
    if not cand:
        cand = [(o, t) for o, t in const.items() if t not in (0x29, 0x77)]
    sig = sorted(cand, key=lambda ot: -ot[1])[0]
    out = ROOT / "tools" / "data" / "screens" / f"{name}.txt"
    lines = [f"# {name}: captured from {' '.join(Path(a).name for a in sys.argv[3:])}",
             f"cam {cam}", f"sig {sig[0]:03x} {sig[1]:02x}"]
    lines += [f"{a:02x} {b:02x} {c:02x} {e:02x} {n}" for (a, b, c, e), n in combos.most_common()]
    out.write_text("\n".join(lines) + "\n")
    print(f"{name}: {len(combos)} cells, signature cell ${sig[0]:03x} = fg tile ${sig[1]:02x} -> {out}")


if __name__ == "__main__":
    main()
