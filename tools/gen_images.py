#!/usr/bin/env python3
"""Full-screen images from the CV romhack (~/work/mrdoarcade), shown in place
of an arcade scene the tile renderer cannot do well.

EXTRA (the "YOU WIN EXTRA Mr. Do!" scene): the romhack's cvb_EXTRASCREEN
picture, 22 sprites, and its flag animation (two 4x5 name blocks at column
13, row 17, swapped every 8 frames with sprite 0 shown / hidden).

Output build/images/extra.bin (one ROM bank, src/image.asm reads it):
  $0000  patterns, 2048 (one table: every screen third shares it)
  $0800  colours, 2048
  $1000  name table, 768
  $1300  sprite patterns, 22 x 32
  $1600  sprite attributes, 128 ($D0-terminated)
  $1680  flag frame 1 names, 20; $1694 frame 2, 20
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gen_sprites_hack as H  # noqa: E402

ROOT = HERE.parent
OUT = ROOT / "build" / "images"


def db_exprs(path, label):
    """The DB values after `label:`, arithmetic expressions evaluated."""
    lines = Path(path).read_text().splitlines()
    i = next(n for n, l in enumerate(lines) if l.strip().startswith(label + ":"))
    out = []
    for l in lines[i + 1:]:
        s = l.split(";")[0].strip()
        if not s:
            continue
        m = re.match(r"(?i)db\s+(.*)", s)
        if not m:
            break
        for v in m.group(1).split(","):
            v = v.strip().replace("$", "0x")
            out.append(eval(v, {}) & 0xFF)
    return out


def main():
    pt = H.pletter(H.db_block(H.CORE, "cvb_IMAGE_CHAR"))
    ct = H.pletter(H.db_block(H.CORE, "cvb_IMAGE_COLOR"))
    pnt = H.pletter(H.db_block(H.CORE, "cvb_IMAGE_PATTERN_plt"))
    spt = H.pletter(H.db_block(H.CORE, "cvb_IMAGE_SPRITES"))
    sat = bytes(db_exprs(H.CORE, "cvb_SPRITE_OVERLAY"))
    fr1 = bytes(db_exprs(H.CORE, "cvb_IMAGE_PATTERN_FR1"))
    fr2 = bytes(db_exprs(H.CORE, "cvb_IMAGE_PATTERN_FR2"))
    assert len(pt) <= 2048 and len(ct) <= 2048 and len(pnt) == 768
    assert len(spt) == 22 * 32 and len(sat) == 22 * 4 + 1 and len(fr1) == len(fr2) == 20
    blob = bytearray(0x16A8)
    blob[0x0000:0x0000 + len(pt)] = pt
    blob[0x0800:0x0800 + len(ct)] = ct
    blob[0x1000:0x1300] = pnt
    blob[0x1300:0x1300 + len(spt)] = spt
    blob[0x1600:0x1600 + len(sat)] = sat
    blob[0x1680:0x1694] = fr1
    blob[0x1694:0x16A8] = fr2
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "extra.bin").write_bytes(blob)
    print(f"extra.bin: {len(pt)} B patterns, {len(ct)} B colours, 22 sprites, flag frames")


if __name__ == "__main__":
    main()
