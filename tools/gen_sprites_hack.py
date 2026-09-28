#!/usr/bin/env python3
"""Sprite patterns with the ColecoVision romhack's hand-drawn art.

Same outputs and formats as tools/gen_sprites.py (which stays the fallback),
but for the arcade codes listed in MAP the pattern comes from the earlier CV
hack (~/work/mrdoarcade/mrdo_core.asm, read-only), rotated/mirrored to the
arcade facing and shifted so its bounding box sits where the arcade sprite's
does. Scope (user, 2026-09-27): the hack's ENEMIES (red monsters walking and
pushing, blue diggers, the apple-squashed monster), APPLES (whole, wobbling,
breaking) and DESSERTS; added later the same day: the ALPHA (letter) MONSTER.
Everything else keeps the arcade conversion: Mr. Do (the arcade has far more
frames), the flattened alpha, chompers, ball + fragments, diamond, score
signs, effects.

Hack sources used:
  BADGUY_RIGHT_WALK_01/02_PAT, DIGGER_RIGHT_01/02_PAT, BadGuyPushRight_01/02
      plain 32-byte TMS sprites
  EXTRA_SPRITE_COMP  Pletter-0.5c packed, 18 sprites loaded at SPT name 96:
      E X T R A blank-body apple half-split split squish diamond ball explode x6
      (hack pattern numbers 96 100 104 108 112 116 120 ...; the commented-out
      plain copy EXTRA_SPRITE_PAT in mrdo_core.asm holds the same bytes)
  tileset_bitmap/_color (tilesetscr2.asm, Pletter)  Screen 2 tiles: desserts
      (2x2 multicolour) and the cherry quads

Colours (hack style): monsters red 8 (BYTE_B70B), diggers light blue 5,
squashed enemy purple 13, apples red 8 (BYTE_B757). Arcade colour lines are
kept where the arcade varies them: each line's dominant arcade colour is
snapped to the hack's shade of that hue (reds -> 8, blues -> 5, ...).

Desserts: the arcade draws each one as a 2x2 bg-tile plate plus one sprite
(code $3D + food, at a fixed spot aligned to the plate). The hack draws them
as 2x2 multicolour tiles. Here the sprite gets the hack dessert's two main
colours (pattern + overlay layer) at offset 0, and the full-colour tiles are
written to build/tiles/dessert_hack.bin for the tile renderer.

Outputs (build/sprites/):
  pat.bin      512 x 32  key = code*4 + flipy*2 + flipx, TMS order TL BL TR BR
  col.bin      128 x 16  TMS colour per (code, colour line)
  overlay.bin  512 x 32  second layer (zero where none)
  ovcol.bin    128       overlay colour per code (0 = none)
  hack_mapping.png / hack_mapping.txt  review sheet + table
and build/tiles/:
  cherry_hack.bin   4 tiles (arcade fg $78,$79,$7A,$7B) x (8 pattern + 8
                    colour) bytes, player view, dirt = colour 0; + .png
  dessert_hack.bin  12 foods x 4 tiles (plate quadrant k = arcade bg tile
                    food*4+k) x 16 bytes; zero for foods without hack art
"""
import os
import re
import sys
from collections import Counter
from pathlib import Path

DIS = Path(os.environ.get("DO_DISASM", Path.home() / "work/do_disassemble"))
HACK = Path(os.environ.get("MRDO_HACK", Path.home() / "work/mrdoarcade"))
sys.path.insert(0, str(DIS / "tools"))
from mrdo_gfx import Canvas, build_palette, decode_chars, decode_sprites, load_all  # noqa: E402
from mrdo_sprites import msx_sprite, sprite_rgb  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_sprites import BLACK, SCORE_CODES, tms_sprite_bytes, usual_lines  # noqa: E402
from gen_tiles import TMS, tms_index  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "sprites"
TOUT = ROOT / "build" / "tiles"
CORE = HACK / "mrdo_core.asm"
TSET = HACK / "tilesetscr2.asm"

EXTRA_NAMES = ["LETTER_E", "LETTER_X", "LETTER_T", "LETTER_R", "LETTER_A",
               "ALPHA_BLANK", "APPLE", "APPLE_HALF_SPLIT", "APPLE_SPLIT",
               "SQUISHED", "DIAMOND", "BALL"] + [f"BALL_EXPLODE_{i}" for i in range(6)]

# ---------------------------------------------------------------------------
# hack source parsing
# ---------------------------------------------------------------------------


def _nums(s):
    out = []
    for t in re.findall(r"\$[0-9A-Fa-f]+|\b[0-9][0-9A-Fa-f]*[hH]\b|\b\d+\b", s):
        if t[0] == "$":
            out.append(int(t[1:], 16))
        elif t[-1] in "hH":
            out.append(int(t[:-1], 16))
        else:
            out.append(int(t))
    return out


def db_block(path, label):
    """Bytes of the DB lines following `label:` (up to the next non-DB line)."""
    lines = Path(path).read_text().splitlines()
    i = next(k for k, ln in enumerate(lines)
             if ln.split(";")[0].strip().startswith(label + ":"))
    out = []
    for ln in [lines[i].split(":", 1)[1]] + lines[i + 1:]:
        s = ln.split(";")[0].strip()
        if not s:
            continue
        if re.match(r"(?i)^db\b", s):
            out += _nums(s[2:])
        elif out or re.match(r"^[A-Za-z_.][\w.]*:", s) or s.upper() in ("IFDEF", "ELSE"):
            break
    return bytes(out)


def pletter(src):
    """Pletter 0.5c depacker (the hack's `unpack`)."""
    st = {"byte": (src[0] << 3) & 0xFF, "cnt": 5, "p": 1}

    def bit():
        if st["cnt"] == 0:
            st["byte"], st["cnt"] = src[st["p"]], 8
            st["p"] += 1
        st["cnt"] -= 1
        b = st["byte"] >> 7
        st["byte"] = (st["byte"] << 1) & 0xFF
        return b

    def byte():
        st["p"] += 1
        return src[st["p"] - 1]

    mode = src[0] >> 5
    out = bytearray([byte()])
    while True:
        if not bit():
            out.append(byte())
            continue
        n = 1
        while bit():
            n = (n << 1) | bit()
            if n > 0xFFFF:
                return bytes(out)
        c, b = byte(), 0
        if c & 0x80 and mode:
            for _ in range(mode):
                b = (b << 1) | bit()
            if bit():
                b, c = b + 1, c & 0x7F
        off = ((b << 8) | c) + 1
        for _ in range(n + 1):
            out.append(out[-off])


def layer_to_grid(b):
    g = [[0] * 16 for _ in range(16)]
    for qi, (cx, cy) in enumerate([(0, 0), (0, 8), (8, 0), (8, 8)]):
        for r in range(8):
            for c in range(8):
                if (b[qi * 8 + r] >> (7 - c)) & 1:
                    g[cy + r][cx + c] = 1
    return g


def hack_sprites():
    """label -> 16x16 0/1 grid (single-layer hack sprites)."""
    spr = {}
    for lbl in ("BADGUY_RIGHT_WALK_01_PAT", "BADGUY_RIGHT_WALK_02_PAT",
                "DIGGER_RIGHT_01_PAT", "DIGGER_RIGHT_02_PAT",
                "BadGuyPushRight_01", "BadGuyPushRight_02",
                "CHOMPER_RIGHT_CLOSED_PAT", "CHOMPER_RIGHT_OPEN_PAT"):
        d = db_block(CORE, lbl)
        assert len(d) == 32, (lbl, len(d))
        spr[lbl] = layer_to_grid(d)
    ex = pletter(db_block(CORE, "EXTRA_SPRITE_COMP"))
    assert len(ex) == 18 * 32
    for i, name in enumerate(EXTRA_NAMES):
        spr["EXTRA_SPRITE_COMP#" + name] = layer_to_grid(ex[i * 32:i * 32 + 32])
    # apple break halves: the hack draws the break as ONE sprite, the arcade
    # as two (left/right half, queued 16px apart) -> split at the gap column
    for name in ("APPLE_HALF_SPLIT", "APPLE_SPLIT"):
        g = spr["EXTRA_SPRITE_COMP#" + name]
        cut = split_column(g)
        spr[f"EXTRA_SPRITE_COMP#{name}.L"] = [[v if x < cut else 0 for x, v in enumerate(r)] for r in g]
        spr[f"EXTRA_SPRITE_COMP#{name}.R"] = [[v if x >= cut else 0 for x, v in enumerate(r)] for r in g]
    return spr


def split_column(g):
    """Column where a 2-piece sprite splits: the emptiest column between the
    pieces (ties -> nearest the middle)."""
    cols = [sum(g[y][x] for y in range(16)) for x in range(16)]
    xs = [x for x in range(16) if cols[x]]
    lo, hi = xs[0] + 2, xs[-1] - 1
    return min(range(lo, hi + 1), key=lambda x: (cols[x], abs(x - 8)))


def hack_tiles():
    pt = pletter(db_block(TSET, "tileset_bitmap"))
    ct = pletter(db_block(TSET, "tileset_color"))
    return pt, ct


def tile_px(pt, ct, t):
    """8x8 TMS colour indices of hack tile t."""
    rows = []
    for y in range(8):
        p, c = pt[t * 8 + y], ct[t * 8 + y]
        rows.append([(c >> 4) if (p >> (7 - x)) & 1 else (c & 15) for x in range(8)])
    return rows


def quad_px(pt, ct, col, row):
    """16x16 colour indices of the 2x2 hack tile block at tile (col, row)."""
    g = [[0] * 16 for _ in range(16)]
    for dy in range(2):
        for dx in range(2):
            t = tile_px(pt, ct, (row + dy) * 32 + col + dx)
            for y in range(8):
                for x in range(8):
                    g[dy * 8 + y][dx * 8 + x] = t[y][x]
    return g


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------

def mirror_x(g):
    return [r[::-1] for r in g]


def mirror_y(g):
    return g[::-1]


def transpose(g):
    return [[g[x][y] for x in range(16)] for y in range(16)]


# the 8 symmetries of the square: name -> fn
XFORMS = {
    "id": lambda g: g,
    "mx": mirror_x,
    "my": mirror_y,
    "r180": lambda g: mirror_x(mirror_y(g)),
    "rcw": lambda g: mirror_x(transpose(g)),
    "rccw": lambda g: mirror_y(transpose(g)),
    "tr": transpose,
    "atr": lambda g: mirror_x(mirror_y(transpose(g))),
}


def arcade_flip(g, fx, fy):
    """Arcade flip bits in the player's view: flipx = mirror_y, flipy = mirror_x
    (msx_sprite = rot_ccw(flip(...)))."""
    if fx:
        g = mirror_y(g)
    if fy:
        g = mirror_x(g)
    return g


def bbox(g):
    ys = [y for y in range(16) if any(g[y])]
    xs = [x for x in range(16) if any(g[y][x] for y in range(16))]
    if not ys:
        return None
    return xs[0], ys[0], xs[-1], ys[-1]


def shift(g, dx, dy):
    out = [[0] * 16 for _ in range(16)]
    lost = 0
    for y in range(16):
        for x in range(16):
            if g[y][x]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < 16 and 0 <= ny < 16:
                    out[ny][nx] = g[y][x]
                else:
                    lost += 1
    return out, lost


def align(h, a):
    """Shift h so its bbox centre matches a's (rounding toward the arcade
    box, i.e. to within half a pixel)."""
    hb, ab = bbox(h), bbox(a)
    dx2 = (ab[0] + ab[2]) - (hb[0] + hb[2])
    dy2 = (ab[1] + ab[3]) - (hb[1] + hb[3])
    dx, dy = _half(dx2), _half(dy2)
    s, lost = shift(h, dx, dy)
    if lost:        # never clip art: pull back inside the box
        b = bbox(h)
        dx = max(-b[0], min(15 - b[2], dx))
        dy = max(-b[1], min(15 - b[3], dy))
        s, lost = shift(h, dx, dy)
    return s, (dx, dy)


def centroid(g):
    pts = [(x, y) for y in range(16) for x in range(16) if g[y][x]]
    return sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)


def _half(v):
    return v // 2 if v >= 0 else -((-v) // 2)


def iou(a, b):
    i = u = 0
    for y in range(16):
        for x in range(16):
            p, q = bool(a[y][x]), bool(b[y][x])
            i += p and q
            u += p or q
    return i / u if u else 0.0


# ---------------------------------------------------------------------------
# the mapping
# ---------------------------------------------------------------------------

WALK = ["BADGUY_RIGHT_WALK_01_PAT", "BADGUY_RIGHT_WALK_02_PAT"]
DIG = ["DIGGER_RIGHT_01_PAT", "DIGGER_RIGHT_02_PAT"]
PUSH = ["BadGuyPushRight_01", "BadGuyPushRight_02"]
CHOMP = ["CHOMPER_RIGHT_CLOSED_PAT", "CHOMPER_RIGHT_OPEN_PAT"]
APPLE = "EXTRA_SPRITE_COMP#APPLE"
HALF = "EXTRA_SPRITE_COMP#APPLE_HALF_SPLIT"
SPLIT = "EXTRA_SPRITE_COMP#APPLE_SPLIT"
SQUISH = "EXTRA_SPRITE_COMP#SQUISHED"
LETTER = {ch: f"EXTRA_SPRITE_COMP#LETTER_{ch}" for ch in "EXTRA"}
BLANK = "EXTRA_SPRITE_COMP#ALPHA_BLANK"
ALL8 = list(XFORMS)

# group, codes, candidate hack labels, allowed transforms, colour rule.
# One transform per group (the one with the best summed overlap), so a
# facing never flips between animation frames; each code then takes the
# candidate frame that overlaps its arcade frame best (the arcade has 3
# walk/dig/push frames, the hack 2: this alternates them, e.g. 01 02 01).
MAP = [
    ("monster walk horizontal", [0x2D, 0x2E, 0x2F], WALK, ALL8, "monster"),
    ("monster walk vertical", [0x30, 0x31, 0x32], WALK, ALL8, "monster"),
    ("digger horizontal", [0x33, 0x34, 0x35], DIG, ALL8, "digger"),
    ("digger vertical", [0x36, 0x37, 0x38], DIG, ALL8, "digger"),
    ("monster push", [0x39, 0x3A, 0x3B], PUSH, ALL8, "monster"),
    ("monster squashed by apple", [0x3C], [SQUISH], ["id", "mx"], "squish"),
    ("chomper horizontal", [0x27, 0x28], CHOMP, ALL8, "chomper"),
    # vertical movers: the arcade turns them, so only the turned forms of the
    # hack's right-facing art (the group's shared facing picked them unturned)
    ("chomper vertical", [0x29, 0x2A], CHOMP, ["rcw", "rccw", "tr", "atr"], "chomper"),
    ("apple", [0x5E], [APPLE], ["id"], "apple"),
    ("apple wobble", [0x5D, 0x5F], [APPLE], ["id"], "apple"),
    ("apple break frame 1 L", [0x60], [HALF + ".L"], ["id"], "apple"),
    ("apple break frame 1 R", [0x61], [HALF + ".R"], ["id"], "apple"),
    ("apple break frame 2 L", [0x62], [SPLIT + ".L"], ["id"], "apple"),
    ("apple break frame 2 R", [0x63], [SPLIT + ".R"], ["id"], "apple"),
] + [
    # alpha monster: arcade code = $4D + letter*3 + frame ($44F8: frame 0 =
    # letter cut out of the body, legs apart; 1/2 = walking, letter in pen 3,
    # which the one-colour conversion merges into the body). Hack: letter
    # sprites 96-112 and the blank body 116 (BYTE_B6CF); frames 1/2 take 116,
    # mirrored where that matches the arcade's foot, so the walk still shows.
    (f"alpha {ch} letter", [0x4D + 3 * i], [LETTER[ch]], ["id"], "alpha")
    for i, ch in enumerate("EXTRA")
] + [
    ("alpha walk foot 1", [0x4E + 3 * i for i in range(5)], [BLANK], ["id", "mx"], "alpha"),
    ("alpha walk foot 2", [0x4F + 3 * i for i in range(5)], [BLANK], ["id", "mx"], "alpha"),
]
# the wobble frames are the resting apple tilted: shift the hack apple from
# the resting position by the arcade centroid change (+-1 px), so it jiggles
WOBBLE_REF = 0x5E

# desserts: food index -> hack 2x2 tile block (col, row) in tilesetscr2
# (arcade food = NestWork[level]: sprite $3D+food over plate tiles food*4+k)
DESSERTS = {0: ("cake", (14, 2)), 1: ("cookies", (16, 2)), 2: ("fruit", (18, 2)),
            3: ("sundae", (20, 2)), 4: ("burger", (22, 2)), 5: ("pudding", (22, 4)),
            6: ("waffle", None), 7: ("sandwich", None), 8: ("milk", (24, 4)),
            9: ("eggs", (26, 4)), 10: ("pancakes", (28, 4)), 11: ("cocktail", (30, 4))}
CHERRY_QUADS = [(c, 4) for c in range(0, 20, 2)]       # the 10 level variants
CHERRY_COLOURS = {1, 6, 8, 9}                           # stem + reds (no dirt uses them)

HUE = {  # arcade-nearest TMS colour -> hack shade
    "monster": {6: 8, 8: 8, 9: 8, 4: 5, 5: 5, 7: 7},
    "digger": {4: 5, 5: 5, 7: 7, 6: 8, 8: 8, 9: 8},
    "chomper": {4: 5, 5: 5, 7: 7, 6: 8, 8: 8, 9: 8},
    "apple": {6: 8, 8: 8, 9: 8},
    "squish": {6: 13, 8: 13, 9: 13},
    # alpha: the hack's two shades (yellow 11, red 8); blues -> light blue 5
    "alpha": {6: 8, 8: 8, 9: 8, 10: 11, 11: 11, 4: 5, 5: 5},
}
FIXED = {  # (rule, line) -> colour, where the hack is explicit
    ("digger", 2): 5, ("digger", 8): 5, ("digger", 11): 5,   # arcade dig lines
    ("monster", 2): 8, ("apple", 5): 8, ("squish", 2): 13,
}


def colour(rule, line, arcade_col):
    if (rule, line) in FIXED:
        return FIXED[(rule, line)]
    return HUE[rule].get(arcade_col, arcade_col)


# ---------------------------------------------------------------------------

def arcade_conversion():
    """gen_sprites.py's conversion: masks per key + col.bin."""
    _, _, gfx3, proms = load_all()
    sprites = decode_sprites(gfx3)
    pal = build_palette(proms)
    usual = usual_lines()
    tms_line = [[None] + [tms_index(rgb) for rgb in sprite_rgb(proms, pal, line)[1:]]
                for line in range(16)]
    masks, col = [], bytearray()
    for code in range(128):
        pens = tms_line[usual.get(code, 0)]
        solid = {p for p in (1, 2, 3) if pens[p] != BLACK} or {1, 2, 3}
        if code in SCORE_CODES:         # score ovals: digits cut out
            solid = {3}
        for fl in range(4):
            art = msx_sprite(sprites[code], fl & 1, fl >> 1)
            masks.append([[1 if art[y][x] in solid else 0 for x in range(16)] for y in range(16)])
        art = msx_sprite(sprites[code])
        counts = Counter(p for row in art for p in row if p and (code not in SCORE_CODES or p == 2))
        for ln in range(16):
            best = [tms_line[ln][p] for p, n in counts.most_common() if tms_line[ln][p] != BLACK]
            col.append(best[0] if best else 15)
    return masks, col, usual


def seen_flips():
    """code -> Counter of flip bits in the recordings (for the review sheet)."""
    seen = {}
    for s in (1, 2, 3):
        p = ROOT / "build" / "diff" / f"s{s}" / "ref.ram"
        if not p.exists():
            continue
        d = p.read_bytes()
        for h in range(0, len(d) // 8192, 5):
            w = d[h * 8192:h * 8192 + 4096]
            for i in range(40):
                e = 0x312 + i * 4
                if w[e + 1]:
                    seen.setdefault(w[e] & 0x7F, Counter())[(w[e + 2] >> 4) & 3] += 1
    return seen


def two_layers(q):
    """16x16 colour grid (1 = black/background) -> (main, overlay, c1, c2):
    the two most-used colours; other colours go to the nearer of the two."""
    cnt = Counter(v for r in q for v in r if v not in (0, 1))
    (c1, _), (c2, _) = (cnt.most_common(2) + [(0, 0)])[:2]

    def dist(a, b):
        return sum((x - y) ** 2 for x, y in zip(TMS[a], TMS[b]))
    main = [[0] * 16 for _ in range(16)]
    over = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            v = q[y][x]
            if v in (0, 1):
                continue
            if v == c1 or not c2 or (v != c2 and dist(v, c1) <= dist(v, c2)):
                main[y][x] = 1
            else:
                over[y][x] = 1
    return main, over, c1, c2


def screen2_tile(px, transparent=()):
    """8x8 colour indices -> 8 pattern + 8 colour bytes (<= 2 colours/row).
    Colours in `transparent` become 0."""
    pat, col = bytearray(), bytearray()
    for row in px:
        row = [0 if v in transparent else v for v in row]
        cs = [c for c, _ in Counter(row).most_common()]
        assert len(cs) <= 2, f"row has {cs}"
        fg = next((c for c in cs if c != 0), 0)
        bg = next((c for c in cs if c != fg), 0)
        if fg == 0:
            fg, bg = 0, 0
        pat.append(sum(1 << (7 - x) for x in range(8) if row[x] == fg and fg))
        col.append((fg << 4) | bg)
    return pat + col


def cherry_tiles(pt, ct):
    """The hack's cherry block with the dirt made transparent. The 10 level
    variants differ in the dirt behind the cherry (and in some shading rows):
    a pixel is cherry where most variants give it a cherry colour (black
    stem, reds), and takes the variants' most common colour."""
    quads = [quad_px(pt, ct, c, r) for c, r in CHERRY_QUADS]
    art = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            vals = Counter(q[y][x] for q in quads if q[y][x] in CHERRY_COLOURS)
            if sum(vals.values()) * 2 > len(quads):
                art[y][x] = vals.most_common(1)[0][0]
    # quadrant -> arcade fg tile code (as mrdo_cv_maze.py): $79 TL, $7B TR,
    # $78 BL, $7A BR; file order $78,$79,$7A,$7B
    order = [(1, 0), (0, 0), (1, 1), (0, 1)]   # (qy, qx) for $78, $79, $7A, $7B
    out = bytearray()
    for qy, qx in order:
        px = [[art[qy * 8 + y][qx * 8 + x] for x in range(8)] for y in range(8)]
        out += screen2_tile(px)
    return art, out


def dessert_tiles(pt, ct):
    """food -> 16x16 colour grid; + the 12 x 4 x 16 tile file. Quadrant k of
    the arcade plate (bg tile food*4+k) sits at player (qy, qx) =
    (1 - k % 2, k // 2) (the arcade screen is rotated)."""
    grids, out = {}, bytearray()
    for food in range(12):
        name, pos = DESSERTS[food]
        if pos is None:
            out += bytes(64)
            continue
        q = quad_px(pt, ct, *pos)
        grids[food] = q
        for k in range(4):
            qy, qx = 1 - k % 2, k // 2
            out += screen2_tile([[q[qy * 8 + y][qx * 8 + x] for x in range(8)] for y in range(8)])
    return grids, out


# ---------------------------------------------------------------------------
# review sheet text: the arcade font (0-9 A-Z), player view
# ---------------------------------------------------------------------------

_FONT = None


def text(cv, x, y, s, color, scale=1):
    global _FONT
    if _FONT is None:
        fg = decode_chars(load_all()[0])
        _FONT = {}
        for i, ch in enumerate("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
            t = fg[i]
            _FONT[ch] = [[t[xx][7 - yy] for xx in range(8)] for yy in range(8)]
    for ch in s.upper():
        g = _FONT.get(ch)
        if g is None and ch in "#.+-":
            g = [[1 if (ch == "#" and (yy in (2, 5) or xx in (2, 5)) and 1 <= yy <= 6 and 1 <= xx <= 6)
                  or (ch == "." and yy >= 5 and 2 <= xx <= 3)
                  or (ch in "+-" and yy == 3 and 1 <= xx <= 5)
                  or (ch == "+" and xx == 3 and 1 <= yy <= 5) else 0
                  for xx in range(8)] for yy in range(8)]
        if g:
            for yy in range(8):
                for xx in range(8):
                    if g[yy][xx]:
                        cv.rect(x + xx * scale, y + yy * scale, scale, scale, color)
        x += 7 * scale


def main():
    masks, arc_col, usual = arcade_conversion()
    hs = hack_sprites()
    pt, ct = hack_tiles()
    flips_seen = seen_flips()

    pat = bytearray()
    for m in masks:
        pat += tms_sprite_bytes(m)
    col = bytearray(arc_col)
    overlay = bytearray(512 * 32)
    ovcol = bytearray(128)
    chosen = {}          # code -> (label, xform, shift, iou, note)
    layers = {}          # key -> (main grid, overlay grid)

    for group, codes, cands, xfs, rule in MAP:
        best_xf = None
        for xf in xfs:
            tot, picks = 0.0, {}
            for code in codes:
                a = masks[code * 4]
                opts = []
                for lbl in cands:
                    h, sh = align(XFORMS[xf](hs[lbl]), a)
                    opts.append((iou(h, a), lbl, h, sh))
                picks[code] = max(opts, key=lambda o: o[0])
                tot += picks[code][0]
            if best_xf is None or tot > best_xf[0]:
                best_xf = (tot, xf, picks)
        _, xf, picks = best_xf
        for code in codes:
            s, lbl, h, sh = picks[code]
            if group == "apple wobble":
                ref = chosen[WOBBLE_REF][2]
                d = round(centroid(masks[code * 4])[0] - centroid(masks[WOBBLE_REF * 4])[0])
                h, _ = shift(hs[lbl], ref[0] + d, ref[1])
                sh = (ref[0] + d, ref[1])
                s = iou(h, masks[code * 4])
            chosen[code] = (lbl, xf, sh, s, group)
            for fl in range(4):
                g = arcade_flip(h, fl & 1, fl >> 1)
                key = code * 4 + fl
                pat[key * 32:key * 32 + 32] = tms_sprite_bytes(g)
                layers[key] = (g, None)
            for ln in range(16):
                col[code * 16 + ln] = colour(rule, ln, arc_col[code * 16 + ln])

    # desserts: the full-colour hack tiles draw the whole dessert (see
    # tools/gen_tiles.py), so the sprite $3D+food is left empty; drawing both
    # garbled it. The two-layer split stays in the review sheet.
    dgrids, dfile = dessert_tiles(pt, ct)
    for food, q in dgrids.items():
        code = 0x3D + food
        main_, over, c1, c2 = two_layers(q)
        for fl in range(4):
            key = code * 4 + fl
            g, o = arcade_flip(main_, fl & 1, fl >> 1), arcade_flip(over, fl & 1, fl >> 1)
            pat[key * 32:key * 32 + 32] = bytes(32)
            layers[key] = (g, o)
        col[code * 16:code * 16 + 16] = bytes([c1]) * 16
        name, pos = DESSERTS[food]
        chosen[code] = (f"tileset {name} @{pos[0]},{pos[1]}", "id", (0, 0),
                        iou(main_, masks[code * 4]), f"dessert {food}")

    cherry_art, cfile = cherry_tiles(pt, ct)

    OUT.mkdir(parents=True, exist_ok=True)
    TOUT.mkdir(parents=True, exist_ok=True)
    (OUT / "pat.bin").write_bytes(pat)
    (OUT / "col.bin").write_bytes(col)
    (OUT / "overlay.bin").write_bytes(overlay)
    (OUT / "ovcol.bin").write_bytes(ovcol)
    (TOUT / "cherry_hack.bin").write_bytes(cfile)
    (TOUT / "dessert_hack.bin").write_bytes(dfile)
    assert len(pat) == len(overlay) == 512 * 32 and len(col) == 2048 and len(ovcol) == 128

    write_txt(chosen, usual, flips_seen)
    write_sheet(masks, arc_col, col, layers, ovcol, chosen, usual, flips_seen)
    write_tile_preview(cherry_art, dgrids)
    print(f"{len(chosen)} codes use hack art; pat/col/overlay/ovcol + "
          f"cherry_hack.bin ({len(cfile)} B) + dessert_hack.bin ({len(dfile)} B)")


ARCADE_NOTES = {
    **{c: "Mr. Do (kept arcade by request)" for c in range(0x00, 0x27)},
    0x2B: "squashed alpha/chomper (kept arcade)", 0x2C: "squashed alpha/chomper (kept arcade)",
    0x43: "dessert 6 waffle: no hack art", 0x44: "dessert 7 sandwich: no hack art",
    0x49: "flattened alpha (kept arcade)", 0x4A: "flattened alpha (kept arcade)",
    0x4B: "flattened alpha (kept arcade)", 0x4C: "chomper zapped (kept arcade)",
    0x5C: "flattened alpha (kept arcade)",
    0x64: "apple break final frame (halves lying open): no hack art",
    0x65: "apple break final frame (halves lying open): no hack art",
    0x66: "power ball (kept arcade)", 0x67: "squash burst (kept arcade)",
    0x68: "squash burst (kept arcade)", 0x69: "diamond (kept arcade)",
    0x6A: "diamond sparkle (kept arcade)", 0x6B: "diamond sparkle (kept arcade)",
    0x6C: "nest icon (kept arcade; hack has one at tileset 12,2)",
    0x6D: "clown juggling ball (kept arcade)", 0x6E: "cherry icon (kept arcade)",
    0x70: "ball fragment (kept arcade)", 0x79: "ball fragment (kept arcade)",
    **{c: "score sign (kept arcade by request)" for c in range(0x71, 0x78)},
    0x78: "celebration ball (kept arcade)",
    **{c: "monster killed by ball: hack has no such art (kept arcade)" for c in range(0x7A, 0x80)},
}


def xf_text(xf, sh):
    names = {"id": "", "mx": "mirror-x", "my": "mirror-y", "r180": "rot180",
             "rcw": "rot-cw", "rccw": "rot-ccw", "tr": "transpose", "atr": "anti-transpose"}
    parts = [p for p in (names[xf], f"shift {sh[0]:+d},{sh[1]:+d}" if sh != (0, 0) else "") if p]
    return " ".join(parts) or "as is"


def write_txt(chosen, usual, flips_seen):
    L = ["# arcade sprite code -> art source (tools/gen_sprites_hack.py)",
         "# transform = applied to the hack pattern for flip 0 (player view); flipped keys",
         "# mirror that result the same way the arcade flip mirrors its own sprite.",
         "# shift = pixels moved to match the arcade sprite's bounding-box centre.",
         "# iou = overlap with the arcade silhouette after alignment (low = eyeball it).", ""]
    for code in range(128):
        seen = "seen" if code in flips_seen else "unseen"
        if code in chosen:
            lbl, xf, sh, s, grp = chosen[code]
            note = ""
            if s < 0.45 and not grp.startswith(("dessert", "alpha")):
                note = "  ** low overlap, check"
            L.append(f"${code:02X} {grp:26s} {lbl} [{xf_text(xf, sh)}] iou {s:.2f} ({seen}){note}")
        else:
            L.append(f"${code:02X} arcade  {ARCADE_NOTES.get(code, '(unused / other)')} ({seen})")
    L += ["", "Notes:",
          "- Walk/dig/push: one transform per facing group; each arcade frame (3) takes the",
          "  hack frame (2) that overlaps it best, which alternates them.",
          "- Apple wobble $5D/$5F: the hack apple moved 1 px from the resting $5E position",
          "  (the arcade's centroid change), so the wobble still shows.",
          "- Dig colours: arcade lines 2/8/B all map to the hack's digger light blue 5.",
          "- $3C squashed monster uses the hack's SQUISHED sprite in purple 13 (the hack's",
          "  'enemy smashed' colour).",
          "- Apple break: the hack's single break sprites are split at their gap column into",
          "  the arcade's left/right half codes, each aligned to its arcade half.",
          "- Desserts $3D-$48: sprite = the hack dessert's two main colours (pat + overlay),",
          "  placed at offset 0 (the arcade food sprite lines up with its 2x2 plate).",
          "  Full colour: build/tiles/dessert_hack.bin. Using the tiles for the plate makes",
          "  the sprite layers redundant (they coincide with tile pixels).",
          "  Food 6 waffle ($43) and 7 sandwich ($44) have no hack art: arcade kept.",
          "- Alpha monster $4D-$5B = $4D + letter*3 + frame (arcade $44F8). Frame 0 (letter",
          "  cut out of the body) -> hack LETTER_E/X/T/R/A (patterns 96/100/104/108/112);",
          "  frames 1/2 (walking; the arcade letter there is pen 3, merged into the",
          "  one-colour body) -> hack blank body 116, mirrored per foot. The arcade only",
          "  queues colour line 4 (blue) for these: -> light blue 5. Other lines snap",
          "  reds -> 8 and yellows -> 11 (the hack's two alpha colours). Their iou is low by",
          "  design: the hack draws an outline body, the arcade a solid one."]
    (OUT / "hack_mapping.txt").write_text("\n".join(L) + "\n")


def draw16(cv, x0, y0, S, layers_):
    cv.rect(x0, y0, 16 * S, 16 * S, (16, 16, 40))
    for g, c in layers_:
        if g is None:
            continue
        for y in range(16):
            for x in range(16):
                if g[y][x]:
                    cv.rect(x0 + x * S, y0 + y * S, S, S, TMS[c] if c > 1 else (70, 70, 70))


def write_sheet(masks, arc_col, col, layers, ovcol, chosen, usual, flips_seen):
    S = 3
    box = 16 * S
    colw = 4 * (box + 4) + 8 + 34 * 7 + 12
    rowh = box + 8
    ncols, nrows = 4, 32
    cv = Canvas(ncols * colw + 8, nrows * rowh + 30, bg=(40, 40, 40))
    text(cv, 8, 6, "ARCADE F0  HACK F0  ARCADE FX  HACK FX   CODE  SOURCE", (220, 220, 220))
    for code in range(128):
        cx = 8 + (code // nrows) * colw
        cy = 26 + (code % nrows) * rowh
        ln = usual.get(code, 0)
        fl_seen = flips_seen.get(code, Counter())
        alt = max((f for f in (1, 2, 3)), key=lambda f: (fl_seen.get(f, 0), f == 2))
        c_arc, c_new = arc_col[code * 16 + ln], col[code * 16 + ln]
        for i, fl in enumerate((0, alt)):
            key = code * 4 + fl
            draw16(cv, cx + (2 * i) * (box + 4), cy, S, [(masks[key], c_arc)])
            if key in layers:
                g, o = layers[key]
                draw16(cv, cx + (2 * i + 1) * (box + 4), cy, S, [(g, c_new), (o, ovcol[code])])
            else:
                cv.rect(cx + (2 * i + 1) * (box + 4), cy, box, box, (30, 30, 30))
        tx = cx + 4 * (box + 4) + 4
        text(cv, tx, cy + 4, f"{code:02X}", (255, 255, 120))
        if code in chosen:
            lbl, xf, sh, s, grp = chosen[code]
            lbl = lbl.replace("EXTRA_SPRITE_COMP#", "").replace("_PAT", "").replace("_", " ")
            text(cv, tx + 20, cy + 4, lbl[:30], (140, 255, 140))
            text(cv, tx + 20, cy + 16, xf_text(xf, sh).replace(",", " ")[:30], (170, 200, 170))
            text(cv, tx + 20, cy + 28, f"IOU {int(s * 100)}  FX={alt}", (150, 150, 150))
        else:
            text(cv, tx + 20, cy + 4, "ARCADE", (150, 150, 150))
    cv.save(OUT / "hack_mapping.png")


def write_tile_preview(cherry_art, dgrids):
    S = 6
    cv = Canvas(14 * (16 * S + 8) + 8, 16 * S + 16, bg=(90, 60, 30))
    draw_px(cv, 8, 8, S, cherry_art)
    for i, food in enumerate(sorted(dgrids)):
        draw_px(cv, 8 + (i + 2) * (16 * S + 8), 8, S, dgrids[food])
    cv.save(TOUT / "cherry_hack.png")


def draw_px(cv, x0, y0, S, g):
    for y in range(16):
        for x in range(16):
            if g[y][x]:
                cv.rect(x0 + x * S, y0 + y * S, S, S, TMS[g[y][x]])


if __name__ == "__main__":
    main()
