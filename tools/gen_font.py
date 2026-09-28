#!/usr/bin/env python3
"""Extract the arcade FG-layer font (0-9, A-Z, blank) as 1bpp 8x8 TMS9918 patterns.

The arcade monitor is rotated, so each native char is turned CCW into the
player's view (same transform as do_disassemble/tools/mrdo_level1.render).
Output: build/font.bin = 37 glyphs x 8 bytes, in the order "0-9A-Z" + blank,
i.e. glyph n = arcade FG tile n (the arcade font is tiles $00-$23).
"""
import os
import sys
from pathlib import Path

DIS = Path(os.environ.get("DO_DISASM", Path.home() / "work/do_disassemble"))
sys.path.insert(0, str(DIS / "tools"))
from mrdo_gfx import decode_chars, load_all  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "build" / "font.bin"


def screen_view(native):
    return [[native[x][7 - y] for x in range(8)] for y in range(8)]


def main():
    fg = decode_chars(load_all()[0])
    out = bytearray()
    for code in list(range(0x24)) + [0x29]:          # 0-9, A-Z, blank
        for row in screen_view(fg[code]):
            b = 0
            for px in row:
                b = (b << 1) | (1 if px else 0)
            out.append(b)
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_bytes(out)
    for g in (0x0A, 0x16):                             # eyeball 'A' and 'M'
        for b in out[g * 8:g * 8 + 8]:
            print(format(b, "08b").replace("0", ".").replace("1", "#"))
        print()


if __name__ == "__main__":
    main()
