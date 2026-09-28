#!/usr/bin/env python3
"""Playfield tile sets for the ColecoVision renderer.

The renderer shows arcade cell (bg attr, bg tile, fg attr, fg tile) as one
Screen 2 tile, chosen at run time by the rule the MSX port validated:

    code = (bg tile == this colourway's dirt tile ? TBLA : TBLB)[fg tile]

For each of the arcade's 31 colourways (30 levels + the chomper session,
table $06E6) this composes every foreground tile that can appear over the
playfield (tunnels, every dig-morph stage, cherries, the nest art, the font)
over the level's dirt (TBLA) and over black (TBLB), rotates it into the
player's view, reduces it to Screen 2 (1bpp + two TMS9918 colours per row),
and dedupes. Output (build/tiles/):

  sets.bin    31 x SET_BYTES: [count][pad] patterns[MAX*8] colours[MAX*8]
  tbla.bin    31 x 256: fg tile -> code, over dirt
  tblb.bin    31 x 256: fg tile -> code, over anything else
  dirt.bin    31 x 2: (bg attr, bg tile) that identifies each colourway
  preview_*.png  a recorded arcade frame rendered through the tables
"""
import os
import sys
from collections import Counter
from pathlib import Path

DIS = Path(os.environ.get("DO_DISASM", Path.home() / "work/do_disassemble"))
sys.path.insert(0, str(DIS / "tools"))
from mrdo_gfx import Canvas, build_palette, decode_chars, load_all  # noqa: E402
from mrdo_level1 import BLANK, CENTER_ART, CHERRY_TILES, TUNNEL_TILES  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "tiles"
ROM = (DIS / "mrdo_main.bin").read_bytes()

USE_HACK_CHERRIES = False   # the CV romhack's cherry art instead of the arcade's
MAX = 224
DESSERT_BASE = 176          # codes 176-223: the 48 dessert plate tiles                   # codes 0..223 per set; 224..255 stay free for the HUD
SET_BYTES = 2 + MAX * 16
FONT_ATTR = 0x09
CENTER_ATTR = CENTER_ART[1]

# TMS9918 palette (index 0 transparent -> never used; 1 = black).
TMS = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
       (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
       (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
       (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]

# Every intermediate dig-morph tile (outputs of the arcade shape tables at
# $1BE1-$1D02); from the MSX port (tools/mrdo_runtime.py).
DIG_BLOB = bytes.fromhex(
    "9da2a3a0a19e9f9c9878789678dedf78dd799b79799579dc7a977ae0e17a997a"
    "7be2e37b9a7b7b94a7bcc5acb3c6bfa4c7b0afc8c1a6a9beadcac3a8abc0c9b2"
    "bdaaa5c2cbaeb1c480ecf580bbbb80e4f781b781b7e681eeb58282e8b5f0f982"
    "83ea83f2fbb9b983e78484b4b4f6ef8485b885f8f1b8e98586faf386ebba86ba"
    "ed87e587b6b687f4d3d28876d7d676888976d9d87689cdccdbda768acfce8a76"
    "768bd1d08b76d5d4768c8c768c76768c768d768d8d768d768e768e76768e768e"
    "8f76768f768f8f76fc9090fc90fcfc90fd91fd9191fd91fd92fe92fefe92fe92"
    "93ffff93ff9393ff80818283848586877c7d7e7f88898a8b8c8d8e8f90919293"
    "88898a8b88898a8b76767676767676767c7d7e7f88898a8b88898a8b88898a8b"
    "7676")
GAMEPLAY_FG = sorted((set(TUNNEL_TILES) | set(CHERRY_TILES) | set(CENTER_ART[2])
                      | {BLANK[1]} | set(DIG_BLOB)) - {0xFF})
FONT = list(range(0x24))    # 0-9, A-Z


REDS = (6, 8, 9)   # TMS dark red, medium red, light red


def tms_index(rgb):
    r, g, b = rgb
    # A clearly red colour stays red: plain nearest-RGB sends dark reds such
    # as the chomper session's (88,0,0) dirt to black, which turned the whole
    # playfield black in chomper mode.
    candidates = REDS if r >= 64 and r > 2 * g and r > 2 * b else range(1, 16)
    best, bi = None, 1
    for i in candidates:
        t = TMS[i]
        d = sum((a - b) ** 2 for a, b in zip(rgb, t))
        if best is None or d < best:
            best, bi = d, i
    return bi


def rot(cell):
    """Native (monitor) orientation -> player view (CCW)."""
    return [[cell[x][7 - y] for x in range(8)] for y in range(8)]


def to_screen2(cell):
    """8x8 of TMS indices -> (8 pattern bytes, 8 colour bytes)."""
    pat, col = bytearray(), bytearray()
    for row in cell:
        common = [c for c, _ in Counter(row).most_common()]
        bg = common[0]
        fg = common[1] if len(common) > 1 else bg
        # remaining colours go to whichever of the two is nearer
        def side(c):
            if c == fg:
                return 1
            if c == bg:
                return 0
            dfg = sum((a - b) ** 2 for a, b in zip(TMS[c], TMS[fg]))
            dbg = sum((a - b) ** 2 for a, b in zip(TMS[c], TMS[bg]))
            return 1 if dfg < dbg else 0
        b = 0
        for c in row:
            b = (b << 1) | side(c)
        pat.append(b)
        col.append((fg << 4) | bg)
    return bytes(pat), bytes(col)


def main():
    gfx1, gfx2, _, proms = load_all()
    fgt, bgt = decode_chars(gfx1), decode_chars(gfx2)
    pal = build_palette(proms)
    cways = [(ROM[0x06E6 + i * 2], ROM[0x06E7 + i * 2]) for i in range(31)]

    # The CV romhack's cherry art (tools/gen_sprites_hack.py): 4 tiles in the
    # order $78-$7B, 8 pattern + 8 colour bytes each, already in the player's
    # view; background colour 0 = let the dirt show through.
    # Off by default (user, 2026-09-27): the cherries stay exactly as the
    # arcade draws them, so arcade-only tile glitches stay reproducible.
    dessert_hack = (ROOT / "build" / "tiles" / "dessert_hack.bin").read_bytes()
    hack = ROOT / "build" / "tiles" / "cherry_hack.bin"
    cherry = {}
    if USE_HACK_CHERRIES and hack.exists():
        hb = hack.read_bytes()
        for i, t in enumerate(sorted(CHERRY_TILES)):
            cherry[t] = (hb[i * 16:i * 16 + 8], hb[i * 16 + 8:i * 16 + 16])

    def screen_cell(bg_pair):
        """The background alone, player view, as TMS indices."""
        out = [[1] * 8 for _ in range(8)]
        attr, tile = bg_pair
        art = bgt[tile + ((attr & 0x80) << 1)]
        line = (attr & 0x3F) * 4
        for y in range(8):
            for x in range(8):
                pen = art[y][x]
                if pen or attr & 0x40:
                    out[y][x] = tms_index(pal[line + pen])
        return rot(out)

    def compose(bg_pair, fg_tile, fg_attr):
        if fg_tile in cherry:
            pat, col = cherry[fg_tile]
            under = screen_cell(bg_pair)
            cell = [[(col[y] >> 4) if (pat[y] >> (7 - x)) & 1 else
                     ((col[y] & 15) or under[y][x]) for x in range(8)] for y in range(8)]
            return to_screen2(cell)
        out = [[1] * 8 for _ in range(8)]
        for tiles, (attr, tile) in ((bgt, bg_pair), (fgt, (fg_attr, fg_tile))):
            art = tiles[tile + ((attr & 0x80) << 1)]
            line = (attr & 0x3F) * 4
            opaque = attr & 0x40
            for y in range(8):
                for x in range(8):
                    pen = art[y][x]
                    if pen or opaque:
                        out[y][x] = tms_index(pal[line + pen])
        return to_screen2(rot(out))

    OUT.mkdir(parents=True, exist_ok=True)
    sets, tbla_all, tblb_all, dirt = bytearray(), bytearray(), bytearray(), bytearray()
    counts = []
    for dirt_pair in cways:
        codes, pats, cols = {}, [], []

        def code_of(tile):
            if tile not in codes:
                codes[tile] = len(pats)
                pats.append(tile[0])
                cols.append(tile[1])
            return codes[tile]

        blank_bg = (0x00, BLANK[1])
        black = code_of(compose(blank_bg, BLANK[1], 0))           # code 0 = black
        plain_dirt = code_of(compose(dirt_pair, BLANK[1], 0))
        tbla, tblb = bytearray([plain_dirt] * 256), bytearray([black] * 256)
        for t in GAMEPLAY_FG:
            attr = CENTER_ATTR if t in CENTER_ART[2] else 0
            tbla[t] = code_of(compose(dirt_pair, t, attr))
            tblb[t] = code_of(compose(blank_bg, t, attr))
        for t in FONT:          # text over black (HUD / messages in the field)
            tblb[t] = code_of(compose(blank_bg, t, FONT_ATTR))
        # Dessert plates (the center prize): background tiles phase*4+k in
        # character bank 1, each phase with its attribute from the arcade's
        # sequence table ($320D). They get fixed codes DESSERT_BASE + tile in
        # every set, so the renderer needs no lookup: a non-dirt cell whose
        # bg attribute has bit 7 set shows code DESSERT_BASE + bg tile.
        assert len(pats) <= DESSERT_BASE, f"colourway {dirt_pair}: {len(pats)} codes > {DESSERT_BASE}"
        while len(pats) < DESSERT_BASE:
            pats.append(bytes(8))
            cols.append(bytes([0x11] * 8))
        # Foods with romhack art use its full-colour 2x2 tiles, and their
        # sprite is left empty (tools/gen_sprites_hack.py): the arcade's plate
        # plus sprite pair drawn as two 2-colour layers garbled the dessert.
        seqtbl = ROM[0x320D:0x3219]
        for t in range(48):
            h = dessert_hack[t * 16:t * 16 + 16]
            if any(h):
                pats.append(h[:8])
                cols.append(h[8:])      # colour 0 shows the black backdrop
                continue
            attr = seqtbl[t // 4]
            pats_cols = compose((attr, t), BLANK[1], 0)
            pats.append(pats_cols[0])
            cols.append(pats_cols[1])
        assert len(pats) <= MAX, f"colourway {dirt_pair}: {len(pats)} codes > {MAX}"
        counts.append(len(pats))
        blob = bytearray([len(pats), 0])
        blob += b"".join(pats) + bytes(8 * (MAX - len(pats)))
        blob += b"".join(cols) + bytes(8 * (MAX - len(cols)))
        assert len(blob) == SET_BYTES
        sets += blob
        tbla_all += tbla
        tblb_all += tblb
        dirt += bytes(dirt_pair)
    (OUT / "sets.bin").write_bytes(sets)
    (OUT / "tbla.bin").write_bytes(tbla_all)
    (OUT / "tblb.bin").write_bytes(tblb_all)
    (OUT / "dirt.bin").write_bytes(dirt)
    # ROM bank image: per colourway TBLA (256) + TBLB (256), then the dirt pairs
    tables = bytearray()
    for i in range(31):
        tables += tbla_all[i * 256:(i + 1) * 256] + tblb_all[i * 256:(i + 1) * 256]
    tables += dirt
    assert len(tables) <= 0x3FC0, "tables must stay clear of the $FFC0 hotspot"
    (OUT / "tables.bin").write_bytes(tables)
    print(f"31 colourways, codes per set: min {min(counts)} max {max(counts)} "
          f"(limit {MAX}); sets.bin {len(sets)} bytes")
    preview(sets, tbla_all, tblb_all, cways)


def preview(sets, tbla_all, tblb_all, cways):
    """Render a recorded arcade frame (validation recording) through the
    tables, as the ColecoVision will show it (camera at the middle offset)."""
    ref = ROOT / "build" / "diff" / "s1" / "ref.ram"
    if not ref.exists():
        return
    d = ref.read_bytes()
    REC = 8192
    for h in (1800, 5000):
        if (h + 1) * REC > len(d):
            continue
        v = d[h * REC + 4096:(h + 1) * REC]
        pair = (v[0x083], v[0x483])
        cw = cways.index(pair) if pair in cways else 0
        base = cw * SET_BYTES
        pats = sets[base + 2:base + 2 + MAX * 8]
        cols = sets[base + 2 + MAX * 8:base + SET_BYTES]
        SC = 3
        cv = Canvas(256 * SC, 192 * SC, bg=(0, 0, 0))
        cam = 4
        for sy in range(24):
            for sx in range(24):
                r, c = sx + 4, 31 - (sy + cam)
                o = r * 32 + c
                tbl = tbla_all if v[0x400 + o] == pair[1] else tblb_all
                code = tbl[cw * 256 + v[0xC00 + o]]
                for y in range(8):
                    p, cc = pats[code * 8 + y], cols[code * 8 + y]
                    for x in range(8):
                        ci = (cc >> 4) if (p >> (7 - x)) & 1 else (cc & 15)
                        cv.rect((sx * 8 + x) * SC, (sy * 8 + y) * SC, SC, SC, TMS[ci])
        path = OUT / f"preview_{h}.png"
        cv.save(path)
        print(f"preview: {path} (colourway {cw})")


if __name__ == "__main__":
    main()
