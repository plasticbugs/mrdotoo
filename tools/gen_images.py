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
    vgland()


# VERY GOOD, once the characters have landed: the romhack's picture of the
# same three (Mr. Do pushing the apple, the dinosaur), 14 x 5 tiles plus 10
# sprites (some black, covering tile pixels), two frames swapped every 8
# vblanks (cvb_INTERMISSION_FRM1/2). src/vgland.asm draws it over our band
# (screen rows 16-20) at column VG_COL, where our landed characters sit (the
# romhack put it at row 17, column 10).
VG_COL, VG_ROW = 5, 16
RH_COL, RH_ROW = 10, 17


def vgland():
    """build/images/vgland.bin (bank 29 at $E000, src/vgland.asm):
      +$000 patterns of tiles $01-$3B (59 x 8)   +$200 their colours
      +$400 sprite patterns, 80 x 8 (20 16x16 sprites)
      +$700 frame 1 SAT (10 x 4, $D0)            +$730 frame 2 SAT
      +$760 frame 1 names, 14 x 5 (romhack tile numbers, 0 = black)
      +$7B0 frame 2 names, rows 3-4 of the block, 14 x 2"""
    pt = H.pletter(H.db_block(H.CORE, "intermission_char"))
    ct = H.pletter(H.db_block(H.CORE, "intermission_color"))
    spt = H.pletter(H.db_block(H.CORE, "intermission_sprites"))
    fr1 = db_exprs(H.CORE, "cvb_FR1")
    fr2 = db_exprs(H.CORE, "cvb_FR2")
    sp = [db_exprs(H.CORE, "cvb_SP1"), db_exprs(H.CORE, "cvb_SP2")]
    assert len(fr1) == 70 and len(fr2) == 28 and all(len(x) == 40 for x in sp)
    assert max(fr1 + fr2) == 0x3B and len(spt) >= 640
    dy, dx = (VG_ROW - RH_ROW) * 8, (VG_COL - RH_COL) * 8
    blob = bytearray(0x800)
    blob[0x000:0x000 + 59 * 8] = pt[8:60 * 8]
    blob[0x200:0x200 + 59 * 8] = ct[8:60 * 8]
    blob[0x400:0x400 + 640] = spt[:640]
    for k, s in enumerate(sp):
        sat = bytearray()
        for i in range(10):
            y, x, n, c = s[i * 4:i * 4 + 4]
            sat += bytes([(y + dy) & 0xFF, (x + dx) & 0xFF, n, c])
        blob[0x700 + k * 0x30:0x700 + k * 0x30 + 41] = sat + b"\xd0"
    blob[0x760:0x760 + 70] = bytes(fr1)
    blob[0x7B0:0x7B0 + 28] = bytes(fr2)
    (OUT / "vgland.bin").write_bytes(blob)
    print("vgland.bin: VERY GOOD landed picture, 59 tiles, 20 sprite patterns, 2 frames")


if __name__ == "__main__":
    main()
