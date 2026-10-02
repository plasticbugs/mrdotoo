#!/usr/bin/env python3
"""Contact sheet of the HUD's EXTRA letters (review aid).

Every state of every letter as the CV draws it (patterns and colours read
from build/tiles/hud.bin, codes from its glyph table), the whole box in
typical game situations, and the arcade's own box in each state for
reference. Labels use the arcade font.
usage: hud_extra_sheet.py OUT.png   (after make)
       hud_extra_sheet.py --combos OUT.png   every TMS colour for the letters
       on black, every letter/background pair for the "next" marker, and
       the box with alternatives for each state"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gen_tiles as G  # noqa: E402
import gen_hud as HUD  # noqa: E402
from mrdo_gfx import build_palette, decode_chars, load_all  # noqa: E402

ROOT = HERE.parent
hud = (ROOT / "build" / "tiles" / "hud.bin").read_bytes()
inc = dict(l.split(" equ ") for l in (ROOT / "build" / "tiles" / "hud.inc").read_text().split("\n") if l)
MARK, MARK2 = int(inc["HUD_MARK"]), int(inc["HUD_MARK2"])
gfx1, _, _, proms = load_all()
fgt = decode_chars(gfx1)
pal = build_palette(proms)
BG = (48, 48, 56)
WHITE = (255, 255, 255)


def glyph(code):
    """8x8 RGB of HUD glyph `code` from hud.bin."""
    i = code - HUD.HUD_BASE if code >= HUD.HUD_BASE else 256 - HUD.HUD_BASE + HUD.HUD_EXTRA.index(code)
    px = G.screen2_pixels(hud[i * 8:i * 8 + 8], hud[0x300 + i * 8:0x300 + i * 8 + 8])
    return [[G.TMS[c] for c in r] for r in px]


def gcode(attr, box):
    return hud[0x800 + (HUD.CLASSES[attr] - 1) * 128 + box]


STATES = [  # name, code per letter i
    ("NOT COLLECTED", lambda i: gcode(0x2D, HUD.LETTERS[i][1])),
    ("COLLECTED", lambda i: gcode(0x1A, HUD.LETTERS[i][1])),
    ("MONSTER OUT", lambda i: gcode(0x25, HUD.LETTERS[i][1])),
    ("NEXT", lambda i: MARK + i),
    ("NEXT COLLECTED", lambda i: MARK2 + i),
]
ST = {n: f for n, f in STATES}


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[BG] * w for _ in range(h)]

    def block(self, x0, y0, grid, s):
        for y, row in enumerate(grid):
            for x, c in enumerate(row):
                for yy in range(s):
                    r = self.px[y0 + y * s + yy]
                    for xx in range(s):
                        r[x0 + x * s + xx] = c

    def text(self, x0, y0, s, col=WHITE):
        """Arcade font: digits, A-Z (tile $0A + n), space."""
        def tile(ch):
            if ch.isdigit():
                return int(ch)
            if ch.isalpha():
                return 0x0A + ord(ch) - ord("A")
            return None
        for k, ch in enumerate(s.upper()):
            t = tile(ch)
            if t is None:
                continue
            art = G.rot([[1 if v else 0 for v in r] for r in fgt[t]])
            self.block(x0 + k * 8 * self.ts, y0, [[col if v else BG for v in r] for r in art], self.ts)

    def save(self, path):
        ppm = Path(str(path) + ".ppm")
        ppm.write_bytes(b"P6 %d %d 255\n" % (self.w, self.h) + bytes(v for r in self.px for p in r for v in p))
        subprocess.run(["sips", "-s", "format", "png", str(ppm), "--out", str(path)], check=True,
                       capture_output=True)
        ppm.unlink()


def box_grid(states):
    """The panel's box rows 5-7, columns 0-6 (frame + 5 letters), RGB."""
    static = {}
    st = hud[0xB80:0xBC0]
    for k in range(0, len(st), 2):
        if st[k] == 0xFF:
            break
        static[st[k]] = st[k + 1]
    rows = []
    for r in range(HUD.BOX_ROW, HUD.BOX_ROW + 3):
        cells = []
        for x in range(HUD.BOX_X0, HUD.BOX_X1 + 1):
            cell = r * 8 + x
            if r == HUD.BOX_ROW + 1 and HUD.BOX_X0 < x < HUD.BOX_X1:
                i = x - HUD.BOX_X0 - 1
                cells.append(glyph(ST[states[i]](i)))
            else:
                cells.append(glyph(static.get(cell, HUD.HUD_BASE)))
        for y in range(8):
            rows.append([p for c in cells for p in c[y]])
    return rows


def arcade_box(attr_of):
    """The arcade's box (native col 28/29, rows 11-20) in the player's view;
    attr_of(i) = the fg attribute of letter i (the box tiles take the
    attribute of the letter they hold)."""
    rows_letter = {}
    for i, (row, _, _) in enumerate(HUD.LETTERS):
        rows_letter[row] = i
        rows_letter[row + 1] = i if i in (0, 2) else rows_letter.get(row + 1)
    nat = []                                    # native: 10 rows x 2 cols of 8x8
    for r in range(10):
        line = [[None] * 16 for _ in range(8)]
        i = rows_letter.get(11 + r)
        attr = attr_of(i if i is not None else 0)
        for c in range(2):
            t = 0x4C + 2 * r + c
            art = fgt[t + ((attr & 0x80) << 1)]
            ln = (attr & 0x3F) * 4
            for y in range(8):
                for x in range(8):
                    line[y][c * 8 + x] = pal[ln + art[y][x]] if art[y][x] else (0, 0, 0)
        nat.extend(line)
    h, w = len(nat), 16
    return [[nat[x][w - 1 - y] for x in range(h)] for y in range(w)]   # CCW, as G.rot


SITUATIONS = [
    ("ROUND START  E NEXT", ["NEXT"] + ["NOT COLLECTED"] * 4),
    ("E COLLECTED  X NEXT", ["COLLECTED", "NEXT"] + ["NOT COLLECTED"] * 3),
    ("NEXT ON A COLLECTED LETTER", ["NEXT COLLECTED", "NOT COLLECTED", "COLLECTED", "NOT COLLECTED", "NOT COLLECTED"]),
    ("X MONSTER OUT", ["COLLECTED", "MONSTER OUT", "NOT COLLECTED", "NOT COLLECTED", "NOT COLLECTED"]),
    ("EXT COLLECTED  R NEXT", ["COLLECTED"] * 3 + ["NEXT", "NOT COLLECTED"]),
    ("EXTR COLLECTED  A NEXT", ["COLLECTED"] * 4 + ["NEXT"]),
    ("MIXED  E R COLLECTED  T NEXT", ["COLLECTED", "NOT COLLECTED", "NEXT", "COLLECTED", "NOT COLLECTED"]),
    ("ALL BUT A  A OUT", ["COLLECTED"] * 4 + ["MONSTER OUT"]),
]


NAMES = ["", "BLACK", "MED GREEN", "LT GREEN", "DK BLUE", "LT BLUE", "DK RED", "CYAN",
         "MED RED", "LT RED", "DK YELLOW", "LT YELLOW", "DK GREEN", "MAGENTA", "GREY", "WHITE"]
CUR = {"NOT COLLECTED": (14, 1), "COLLECTED": (HUD.COLLECTED, 1), "NEXT": (15, 4),
       "NEXT COLLECTED": (HUD.COLLECTED, 4)}


def letter(i, fg, bg):
    """Letter i of EXTRA as the HUD draws it, in TMS colours fg on bg."""
    art = G.rot(fgt[HUD.LETTERS[i][2]])
    return [[G.TMS[fg] if v else G.TMS[bg] for v in r] for r in art]


def word(fg, bg):
    return [sum((letter(i, fg, bg)[y] for i in range(5)), []) for y in range(8)]


def combos(out):
    TS, LS, MS = 3, 6, 6
    pad, gap = 24, 10
    lab_w = 25 * 8 * TS
    cols = list(range(2, 16))
    W = max(pad * 2 + lab_w + 40 * LS + 20, pad * 2 + 4 * 8 * TS + len(cols) * (8 * MS + gap) + 40)
    H = pad + 2 * (8 * TS + 12) + len(cols) * (8 * LS + 8) + 40 + 8 * TS + 12 + 2 * 8 * TS + 8 \
        + len(cols) * (8 * MS + gap) + pad
    cv = Canvas(W, H)
    cv.ts = TS
    y = pad
    cv.text(pad, y, "LETTERS ON BLACK   NOW MARKED")
    y += 8 * TS + 12
    for c in cols:
        tag = "  NOW NOT COLL" if c == CUR["NOT COLLECTED"][0] else "  NOW COLL" if c == CUR["COLLECTED"][0] else ""
        cv.text(pad, y + (8 * LS - 8 * TS) // 2, "%d %s%s" % (c, NAMES[c], tag))
        cv.block(pad + lab_w, y, word(c, 1), LS)
        y += 8 * LS + 8
    y += 40
    cv.text(pad, y, "NEXT MARKER  LETTER ACROSS  BG DOWN")
    y += 8 * TS + 6
    cv.text(pad, y, "WHITE FRAME  NOW")
    y += 8 * TS + 12
    x0 = pad + 4 * 8 * TS
    for k, fg in enumerate(cols):
        cv.text(x0 + k * (8 * MS + gap) + (8 * MS - (2 if fg > 9 else 1) * 8 * TS) // 2, y, str(fg))
    y += 2 * 8 * TS + 8
    for bg in cols:
        cv.text(pad, y + (8 * MS - 8 * TS) // 2, str(bg))
        for k, fg in enumerate(cols):
            x = x0 + k * (8 * MS + gap)
            if fg == bg:
                continue
            if (fg, bg) in (CUR["NEXT"], CUR["NEXT COLLECTED"]):
                cv.block(x - 4, y - 4, [[WHITE] * (8 * MS + 8)] * (8 * MS + 8), 1)
            cv.block(x, y, letter(0, fg, bg), MS)
        y += 8 * MS + gap
    cv.save(out)
    print(out)


def main():
    if sys.argv[1:2] == ["--combos"]:
        combos(Path(sys.argv[2] if len(sys.argv) > 2 else ROOT / "build" / "hud_extra_combos.png"))
        return
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "build" / "hud_extra_sheet.png")
    GS, BS, ABS, TS = 10, 6, 4, 3          # glyph, box, arcade box, label scale
    pad = 24
    lab_w = 15 * 8 * TS
    W = pad * 3 + lab_w + 5 * (8 * GS + 12) + 7 * 8 * BS + 60
    rows_a = len(STATES)
    H = (pad + 8 * TS + 12 + rows_a * (8 * GS + 16) + 24 + 8 * TS + 12
         + len(SITUATIONS) * (24 * BS + 20) + 24 + 8 * TS + 12 + 16 * ABS + 8 * TS + 40)
    cv = Canvas(W, H)
    cv.ts = TS
    y = pad
    cv.text(pad, y, "EVERY LETTER STATE")
    y += 8 * TS + 12
    for name, f in STATES:
        cv.text(pad, y + (8 * GS - 8 * TS) // 2, name)
        for i in range(5):
            cv.block(pad + lab_w + pad + i * (8 * GS + 12), y, glyph(f(i)), GS)
        y += 8 * GS + 16
    y += 24
    cv.text(pad, y, "THE BOX IN PLAY")
    y += 8 * TS + 12
    for name, sts in SITUATIONS:
        cv.text(pad, y + (24 * BS - 8 * TS) // 2, name[:15])
        if len(name) > 15:
            cv.text(pad, y + (24 * BS - 8 * TS) // 2 + 8 * TS + 4, name[15:].strip()[:15])
        cv.block(pad + lab_w + pad, y, box_grid(sts), BS)
        y += 24 * BS + 20
    y += 24
    cv.text(pad, y, "ARCADE  NOT COLL  COLLECTED  OUT")
    y += 8 * TS + 12
    x = pad
    for attr in (0x2D, 0x1A, 0x25):
        g = arcade_box(lambda i, a=attr: a)
        cv.block(x, y, g, ABS)
        x += len(g[0]) * ABS + 30
    cv.save(out)
    print(out)


if __name__ == "__main__":
    main()
