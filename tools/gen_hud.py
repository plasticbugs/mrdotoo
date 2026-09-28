#!/usr/bin/env python3
"""The HUD panel (screen columns 24-31) for the playfield (src/hud.asm).

The arcade draws its HUD into two strips of its own video RAM: native columns
29-31 (the top strip: 1ST, the score, the EXTRA box) and 0-2 (the bottom
strip: lives, SCENE, TOP and the top score). Those cells are off our 24x24
playfield, so src/hud.asm mirrors them into the right-hand panel, laid out
like the MSX2 port's:

    row  1  1ST              arcade col 30 rows 7-9
    row  2  score            col 29 rows 5-10 (6 digits)
    rows 5-7 EXTRA box       a drawn frame; one letter per EXTRA letter, its
                             state from the fg attribute of one of its box
                             tiles (col 29 rows 12/14/15/17/18): $2D unlit,
                             $1A collected (light green), $25 out (black); the next letter (the
                             arcade's letter-monster sprite on the box) white
                             (green if collected) on blue
    row 17  SCENE..n         col 2 rows 17-21, 24, 25, 26
    row 19  TOP              col 1 rows 17-19
    row 20  top score        col 1 rows 21-26
    rows 22-23 lives         cols 2/1 rows 4-11 (2x2 icons)

Each mirrored cell becomes a glyph code from its (fg attribute, fg tile):
the arcade's own tile in its own colours, rotated into the player's view.
Glyphs take codes HUD_BASE..255, which playfield tile sets leave free (their
upload stops at code HUD_BASE, see tools/gen_tiles.py).

Output build/tiles/hud.bin (bank 30 at $E100, src/hud.asm HUD_DATA; tables
page-aligned for the lookups):
  +$000  patterns, HUD_N x 8        +$300  colours, HUD_N x 8
  +$600  attribute class, 64 bytes (fg attr -> 0 none, 1..6)
  +$700  panel cell per (strip column, row): 6 x 32; strip column 0-2 =
         native col 0-2, 3-5 = native col 29-31; panel cell = row*8 + x,
         $FF = not shown
  +$800  glyph code per (class, fg tile < $60): class c at +(c-1)*128
         (0 = blank)
  +$B80  static cells (the box frame): (panel cell, code) pairs, $FF ends
  +$BC0  every mirrored arcade cell (lo, hi), $FF $FF ends (hud_redraw)
Glyphs past code 255 take HUD_EXTRA (165-175).
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gen_tiles as G  # noqa: E402
from mrdo_gfx import build_palette, decode_chars, load_all  # noqa: E402

ROOT = HERE.parent
OUT = ROOT / "build" / "tiles"
HUD_BASE = 180
BLANK = 0x29
CLASSES = {0x09: 1, 0x26: 2, 0x2C: 3, 0x2D: 4, 0x1A: 5, 0x25: 6, 0x08: 7}
HUD_EXTRA = list(range(165, 176))   # also free in every playfield set: the dessert
                                    # score shows 163 ("00") and 164 (loaded at pickup)
DIGITS = list(range(10))
GLYPHS = {                          # attr -> fg tiles drawn in that colour
    0x09: DIGITS + [0x2E, 0x2F, 0x30, 0x31],            # score, lives
    0x08: DIGITS,                                        # the other player's score (grey)
    0x26: DIGITS + [0x0C, 0x0D, 0x0E, 0x17, 0x1C, 0x1D, 0x28],  # 1ST, 2ND, SCENE..n
    0x2C: DIGITS + [0x18, 0x19, 0x1D],                   # TOP, top score
}
# EXTRA: the box tile sampled per letter (col 29) and the font letter drawn
LETTERS = [(12, 0x4E, 0x0E), (14, 0x52, 0x21), (15, 0x54, 0x1D),
           (17, 0x58, 0x1B), (18, 0x5A, 0x0A)]       # (row, box tile, font tile)
EX_ATTRS = [0x2D, 0x1A, 0x25]
BOX_ROW, BOX_X0, BOX_X1 = 5, 0, 6    # frame rows 5-7, columns 0-6 of the panel
COLLECTED = 3                   # TMS light green: collected letters (user's pick, 2026-09-28;
                                # the arcade's yellow was too close to the grey and the frame)


def gcode(i):
    """Glyph i's code: HUD_BASE.. then the spare HUD_EXTRA codes."""
    return HUD_BASE + i if HUD_BASE + i < 256 else HUD_EXTRA[HUD_BASE + i - 256]


def main():
    gfx1, gfx2, _, proms = load_all()
    fgt = decode_chars(gfx1)
    pal = build_palette(proms)

    def fg_pixels(attr, tile):
        """fg (attr, tile) over black -> 8x8 TMS indices, player view."""
        art = fgt[tile + ((attr & 0x80) << 1)]
        line = (attr & 0x3F) * 4
        out = [[1] * 8 for _ in range(8)]
        for y in range(8):
            for x in range(8):
                if art[y][x]:
                    out[y][x] = G.tms_index(pal[line + art[y][x]])
        return G.rot(out)

    glyphs = [G.to_screen2([[1] * 8 for _ in range(8)])]   # HUD_BASE: blank
    code = {}
    for attr, tiles in GLYPHS.items():
        for t in tiles:
            code[(attr, t)] = gcode(len(glyphs))
            px = fg_pixels(attr, t)
            if attr == 0x08:            # the arcade's grey (88,88,88) is nearest
                px = [[14 if c != 1 else 1 for c in r] for r in px]    # to TMS
            glyphs.append(G.to_screen2(px))                     # dark green

    # EXTRA letters: box tiles draw the frame with pen 1 (yellow) and the
    # letter with pen 2: grey ($2D, not yet collected), yellow ($1A,
    # collected) or black ($25: its letter monster is out). The arcade's grey
    # (88,88,88) is nearest to TMS black, so the grey is TMS grey 14.
    frame_col = G.tms_index(pal[(0x2D & 0x3F) * 4 + 1])
    letter_col = {0x2D: (14, 1), 0x1A: (COLLECTED, 1), 0x25: (1, 1)}
    lit0 = None
    for row, box, font in LETTERS:
        for a in EX_ATTRS:
            if a == 0x25:                       # out: black, the blank glyph
                code[(a, box)] = HUD_BASE
                continue
            fg, bg = letter_col[a]
            if a == 0x1A and lit0 is None:
                lit0 = gcode(len(glyphs))
            art = fg_pixels(0x09, font)
            art = [[fg if c != 1 else bg for c in r] for r in art]
            code[(a, box)] = gcode(len(glyphs))
            glyphs.append(G.to_screen2(art))

    # The next letter: the arcade marks it with a letter-monster sprite on
    # the box (off our playfield); src/hud.asm finds that sprite and draws
    # the letter with one of these instead: white on the monster's blue.
    marks = gcode(len(glyphs))
    for row, box, font in LETTERS:          # not collected yet: white on blue
        art = fg_pixels(0x09, font)
        glyphs.append(G.to_screen2([[15 if c != 1 else 4 for c in r] for r in art]))
    marks2 = gcode(len(glyphs))
    for row, box, font in LETTERS:          # collected: its colour on blue
        art = fg_pixels(0x09, font)
        glyphs.append(G.to_screen2([[COLLECTED if c != 1 else 4 for c in r] for r in art]))

    # frame: lines 2 px thick, placed to hug the letter row
    def frame_tile(top=False, bottom=False, left=False, right=False):
        px = [[1] * 8 for _ in range(8)]
        for y in range(8):
            for x in range(8):
                h = (top and y in (5, 6)) or (bottom and y in (1, 2))
                v = (left and x in (5, 6)) or (right and x in (1, 2))
                if h and ((not left or x >= 5) and (not right or x <= 2)):
                    px[y][x] = frame_col
                if v and ((not top or y >= 5) and (not bottom or y <= 2)):
                    px[y][x] = frame_col
        return G.to_screen2(px)

    static = []
    frame = {}
    for name, kw in (("tl", dict(top=True, left=True)), ("t", dict(top=True)),
                     ("tr", dict(top=True, right=True)), ("l", dict(left=True)),
                     ("r", dict(right=True)), ("bl", dict(bottom=True, left=True)),
                     ("b", dict(bottom=True)), ("br", dict(bottom=True, right=True))):
        frame[name] = gcode(len(glyphs))
        glyphs.append(frame_tile(**kw))
    for x in range(BOX_X0, BOX_X1 + 1):
        edge = "l" if x == BOX_X0 else "r" if x == BOX_X1 else ""
        static.append(((BOX_ROW) * 8 + x, frame["t" + edge] if edge else frame["t"]))
        static.append(((BOX_ROW + 2) * 8 + x, frame["b" + edge] if edge else frame["b"]))
        if edge:
            static.append(((BOX_ROW + 1) * 8 + x, frame[edge]))
    assert len(glyphs) <= 256 - HUD_BASE + len(HUD_EXTRA), f"{len(glyphs)} glyphs"

    # panel map: (strip column 0-5, row) -> panel cell
    pmap = bytearray(b"\xff" * (6 * 32))

    def put(col, row, prow, px):
        s = col if col < 3 else col - 26
        pmap[s * 32 + row] = prow * 8 + px
    for i, r in enumerate((7, 8, 9)):
        put(30, r, 1, i)                        # 1ST
    for i, r in enumerate(range(5, 11)):
        put(29, r, 2, 2 + i)                    # score
    for i, r in enumerate((23, 24, 25)):
        put(30, r, 3, i)                        # 2ND (2-player game)
    for i, r in enumerate(range(21, 27)):
        put(29, r, 4, 2 + i)                    # its score
    for i, (r, _, _) in enumerate(LETTERS):
        put(29, r, BOX_ROW + 1, BOX_X0 + 1 + i)  # EXTRA letters
    for i, r in enumerate((17, 18, 19, 20, 21, 24, 25, 26)):
        put(2, r, 17, i)                        # SCENE..n
    for i, r in enumerate((17, 18, 19)):
        put(1, r, 19, i)                        # TOP
    for i, r in enumerate(range(21, 27)):
        put(1, r, 20, 2 + i)                    # top score
    for r in range(4, 12):
        put(2, r, 22, r - 4)                    # lives, upper half
        put(1, r, 23, r - 4)                    #        lower half

    cls = bytearray(64)
    for a, c in CLASSES.items():
        cls[a] = c

    gtab = bytearray(7 * 128)
    for (a, t), c in code.items():
        gtab[(CLASSES[a] - 1) * 128 + t] = c
    for a in CLASSES:                           # the arcade's blank: black
        gtab[(CLASSES[a] - 1) * 128 + BLANK] = HUD_BASE
    cells = [(r * 32 + (s_ if s_ < 3 else s_ + 26)) for s_ in range(6) for r in range(32)
             if pmap[s_ * 32 + r] != 0xFF]

    blob = bytearray(0xD00)
    n = len(glyphs)
    blob[0x000:0x000 + n * 8] = b"".join(p for p, _ in glyphs)
    blob[0x300:0x300 + n * 8] = b"".join(c for _, c in glyphs)
    blob[0x600:0x640] = cls
    blob[0x700:0x700 + len(pmap)] = pmap
    blob[0x800:0x800 + len(gtab)] = gtab
    st = b"".join(bytes([p, c]) for p, c in static) + b"\xff"
    blob[0xB80:0xB80 + len(st)] = st
    cl = b"".join(bytes([c & 0xFF, c >> 8]) for c in cells) + b"\xff\xff"
    blob[0xBC0:0xBC0 + len(cl)] = cl
    assert len(st) <= 0x40 and 0xBC0 + len(cl) <= len(blob) and n * 8 <= 0x300
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "hud.bin").write_bytes(blob)
    assert all(gcode(i) - gcode(i - 1) == 1 for i in range(1, len(glyphs)) if gcode(i) not in (HUD_EXTRA[0],))
    (OUT / "hud.inc").write_text(f"HUD_N equ {n}\nHUD_MARK equ {marks}\nHUD_MARK2 equ {marks2}\n"
                                 f"HUD_LIT0 equ {lit0}\nHUD_EXTRA0 equ {HUD_EXTRA[0]}\n"
                                 f"HUD_LETTER0 equ {(BOX_ROW + 1) * 8 + BOX_X0 + 1}\n")
    print(f"hud.bin: {n} glyphs (codes {HUD_BASE}-{HUD_BASE + n - 1}), "
          f"frame colour {frame_col}, {len(static)} static cells, {len(cells)} mirrored cells")


if __name__ == "__main__":
    main()
