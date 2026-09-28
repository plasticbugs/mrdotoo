#!/usr/bin/env python3
"""Side-by-side arcade (MAME) vs ColecoVision frames at the same handlers.

usage: compare_frames.py OUT.png CAM MAME_SNAP_DIR CV_PATTERN H1 H2 ...
MAME snapshots are numbered in handler order; CV_PATTERN has %d for the
handler. Prints, per frame, the share of playfield pixels whose brightness
class agrees (tiles and sprites together), and writes the sheet.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import pngtool  # noqa: E402


def cls(p):
    s = sum(p)
    return 0 if s < 120 else 1          # dark vs lit (same test as the first alignment check)


def main():
    out, cam, snapdir, pattern = sys.argv[1], int(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
    hs = [int(h) for h in sys.argv[5:]]
    ms = [pngtool.read(p) for p in sorted((snapdir).glob("*.png"))][:len(hs)]
    cs = [pngtool.read(pattern % h) for h in hs]
    W, H = 200 * len(hs), 488
    sheet = [[(40, 40, 40)] * W for _ in range(H)]
    for k, (m, c) in enumerate(zip(ms, cs)):
        ok = tot = 0
        for y in range(240):
            for x in range(192):
                sheet[y][x + k * 200] = m[y][x]
                cy = y - (cam - 1) * 8
                if 0 <= cy < 192:
                    cp = c[cy + 24][x + 32]
                    sheet[y + 248][x + k * 200] = cp
                    ok += cls(m[y][x]) == cls(cp)
                    tot += 1
        print(f"handler {hs[k]}: {100 * ok / tot:.1f}% of pixels agree")
    pngtool.write(out, sheet, scale=2)
    print(f"sheet: {out}")


if __name__ == "__main__":
    main()
