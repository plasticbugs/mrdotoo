#!/usr/bin/env python3
"""One-colour TMS9918 sprites from the arcade sprite ROMs (h5-05/k5-06).

Each of the 128 arcade sprite codes is pre-rotated into the player's view in
all four arcade flip combinations (the TMS9918 cannot mirror), as 32-byte
16x16 sprite patterns in TMS order (quadrants TL, BL, TR, BR). One colour per
sprite: the shape is every non-black pixel, and the colour is the most common
non-black colour, for each of the 16 arcade colour lines.

The arcade colour line a code is usually drawn with (counted from the sprite
queue in the validation recordings) decides which pixels count as black for
that code's shape.

Output (build/sprites/):
  pat.bin   512 x 32: pattern for (code << 2 | flipy << 1 | flipx)
  col.bin   128 x 16: TMS colour for (code, colour line)
  mrdo_white.bin  Mr. Do's white pixels (overlay sprite), see main()
  sheet.png every code, flip 0, in its usual colour line
"""
import os
import sys
from collections import Counter
from pathlib import Path

DIS = Path(os.environ.get("DO_DISASM", Path.home() / "work/do_disassemble"))
sys.path.insert(0, str(DIS / "tools"))
from mrdo_gfx import Canvas, build_palette, decode_sprites, load_all  # noqa: E402
from mrdo_sprites import msx_sprite, sprite_rgb  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_tiles import TMS, tms_index  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "sprites"
BLACK = 1
MR_DO_CODES = set(range(0x00, 0x27))   # walk, dig, push, throw, caught, death ($00-$26)


def usual_lines():
    """code -> most common colour line in the recorded sprite queues."""
    seen = {}
    for s in (1, 2, 3):
        p = ROOT / "build" / "diff" / f"s{s}" / "ref.ram"
        if not p.exists():
            continue
        d = p.read_bytes()
        for h in range(0, len(d) // 8192, 5):
            w = d[h * 8192:h * 8192 + 4096]
            # the count was just reset by the upload at the sync point, but
            # the entries remain: take every one with a live Y
            for i in range(40):
                e = 0x312 + i * 4
                if w[e + 1] == 0:
                    continue
                code, attr = w[e] & 0x7F, w[e + 2]
                seen.setdefault(code, Counter())[attr & 0x0F] += 1
    return {c: cnt.most_common(1)[0][0] for c, cnt in seen.items()}


def tms_sprite_bytes(mask):
    """16x16 booleans -> 32 bytes in TMS9918 sprite order."""
    out = bytearray()
    for x0 in (0, 8):
        for y in range(16):
            b = 0
            for x in range(x0, x0 + 8):
                b = (b << 1) | (1 if mask[y][x] else 0)
            out.append(b)
    # TMS order: TL (rows 0-7), BL (rows 8-15), TR (0-7), BR (8-15)
    return bytes(out)


def main():
    _, _, gfx3, proms = load_all()
    sprites = decode_sprites(gfx3)
    pal = build_palette(proms)
    usual = usual_lines()
    tms_line = [[None] + [tms_index(rgb) for rgb in sprite_rgb(proms, pal, line)[1:]]
                for line in range(16)]

    pat = bytearray()
    col = bytearray()
    shapes = []
    for code in range(128):
        line = usual.get(code, 0)
        pens = tms_line[line]
        solid = {p for p in (1, 2, 3) if pens[p] != BLACK}
        if not solid:
            solid = {1, 2, 3}
        for flips in range(4):
            art = msx_sprite(sprites[code], flips & 1, flips >> 1)
            mask = [[art[y][x] in solid for x in range(16)] for y in range(16)]
            pat += tms_sprite_bytes(mask)
            if flips == 0:
                shapes.append((mask, art))
        art = shapes[-1][1]
        counts = Counter(p for row in art for p in row if p)
        for ln in range(16):
            best = [(n, tms_line[ln][p]) for p, n in counts.most_common()
                    if tms_line[ln][p] != BLACK]
            col.append(best[0][1] if best else 15)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "pat.bin").write_bytes(pat)
    (OUT / "col.bin").write_bytes(col)
    # Mr. Do's second colour: his white pixels (pen 2 in his colour line) as
    # an overlay sprite drawn in front of the red one. 64 codes x 4 flips x 32
    # (codes $00-$26 used), then one byte per code: 1 = it has white pixels.
    white = bytearray()
    has = bytearray(64)
    for code in range(64):
        for flips in range(4):
            if code in MR_DO_CODES:
                art = msx_sprite(sprites[code], flips & 1, flips >> 1)
                mask = [[art[y][x] == 2 for x in range(16)] for y in range(16)]
                if any(any(r) for r in mask):
                    has[code] = 1
            else:
                mask = [[False] * 16 for _ in range(16)]
            white += tms_sprite_bytes(mask)
    (OUT / "mrdo_white.bin").write_bytes(white + has)
    # Mr. Do's codes are pinned: always first in the SAT, never rotated out.
    pin = bytearray(0x40 if c in MR_DO_CODES else 0 for c in range(128))
    (OUT / "pin.bin").write_bytes(pin)

    S, cell = 4, 16 * 4 + 6
    cv = Canvas(16 * cell + 6, 8 * cell + 6, bg=(40, 40, 40))
    for code, (mask, art) in enumerate(shapes):
        x0, y0 = 6 + (code % 16) * cell, 6 + (code // 16) * cell
        c = TMS[col[code * 16 + usual.get(code, 0)]]
        for y in range(16):
            for x in range(16):
                if mask[y][x]:
                    cv.rect(x0 + x * S, y0 + y * S, S, S, c)
    cv.save(OUT / "sheet.png")
    print(f"128 codes x 4 flips: pat.bin {len(pat)} B, col.bin {len(col)} B; "
          f"{len(usual)} codes seen in recordings")


if __name__ == "__main__":
    main()
