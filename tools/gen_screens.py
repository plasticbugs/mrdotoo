#!/usr/bin/env python3
"""Tile sets for the arcade's non-gameplay screens (title, cutscenes, ...).

Each tools/data/screens/NAME.txt (made by tools/capture_screen.py) lists the
(bg attr, bg tile, fg attr, fg tile) cells the screen shows, with counts, its
camera row and a signature cell. For each screen this composes every cell into
a Screen 2 tile (same rules as tools/gen_tiles.py), dedupes, and if more than
the set's room of distinct tiles remain, maps the rarest onto their nearest
kept tile. The runtime finds a cell's tile code through a 1024-entry
open-addressed hash:

    h = (fg tile + 4 * (fg attr ^ bg tile ^ bg attr)) & 1023, then h+1, h+2, ...

Screens with a scrolling band (the cutscenes, `band` + `pair` lines) also get:
  - code 0 = black, and every font character in each colour the screen's text
    uses (scores and times differ from the capture);
  - pre-shifted tiles: for every (left bg cell, right bg cell) pair, the 8
    pixel phases of the pair scrolled left by 0-7 (phase 0 = the left cell);
  - a 512-entry pair hash (pkey) giving the pair's id, and the pairs' tiles
    at phases 0, 2, 4, 6 (the band scrolls in 2-pixel steps), all in one bank;
  - room for the band's tile slots: 2 x BAND_SLOTS codes after the static
    tiles (up to code 255: the slots need no set data).

Output (build/screens/):
  banks.bin  whole 16KB banks from SCR_BANK0 on: sets (4 per bank), hashes
             (3 per bank), a bank per cutscene band (pair hash + tiles). A
             bank's last 64 bytes stay $FF.
  banks.inc  SCR_BANKS = number of banks
  index.bin  16 bytes per screen, see INDEX below
"""
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gen_tiles as G  # noqa: E402
from mrdo_gfx import build_palette, load_all  # noqa: E402

ROOT = HERE.parent
OUT = ROOT / "build" / "screens"
SCR_BANK0 = 15                  # first bank (src/main.asm)
BANK = 0x4000
BANK_USE = BANK - 64            # MegaCart hotspot
SCREEN_MAX = 224
HASH_N = 1024
PAIR_N = 512
BAND_SLOTS = 50                 # tiles per band build (src/scene.asm SCN_SLOTS; VERY GOOD builds
                                # only the letter monster: src/vgland.asm draws the rest)
PAIR_MAX = (BANK_USE - 0x1000) // 64    # pairs per scene (one bank)
BLANK = 0x29
FONT_TILES = range(0x30)        # 0-9, A-Z and punctuation
# Order matters: the first signature match wins. The title's logo is on the
# instruction screen too, and congrats (the CONGRATULATIONS opening the diamond
# and EXTRA scenes share) stays on screen under both.
SCREENS = ["instruction", "title", "verygood", "hiscore", "wonderful", "diamond", "extra", "congrats"]
# Screens shown as a romhack image instead (tools/gen_images.py): name -> bank
# (src/image.asm IMG_BANK_EXTRA = MC_FIXED - 2)
IMAGES = {"extra": 29}
# INDEX entry (16 bytes): sig cell (2), sig fg tile, cam, set bank, set address
# (2), hash bank, hash page, band first screen row, band rows, pair hash bank
# (0 = no band), slot base (= static tile count), image bank (0 = none), 2 spare
INDEX = 16


def load(name):
    cam, sig, band, cells, pairs = None, None, None, Counter(), Counter()
    font = False
    logo = None
    fontattr = set()
    for line in (HERE / "data" / "screens" / f"{name}.txt").read_text().splitlines():
        if not line or line[0] == "#":
            continue
        f = line.split()
        if f[0] == "logo":              # the romhack's logo at these screen
            logo = tuple(int(x) for x in f[1:5])        # rows/columns
        elif f[0] == "fontattr":          # every font character in these fg
            fontattr |= {int(x, 16) for x in f[1:]}     # attributes
        elif f[0] == "cam":
            cam = int(f[1])
        elif f[0] == "sig":
            sig = (int(f[1], 16), int(f[2], 16))
        elif f[0] == "font":
            font = True
        elif f[0] == "band":
            band = (int(f[1]), int(f[2]))
        elif f[0] == "pair":
            pairs[tuple(int(x, 16) for x in f[1:5])] += int(f[5])
        else:
            cells[tuple(int(x, 16) for x in f[:4])] += int(f[4])
    for attr in fontattr:
        for t in FONT_TILES:
            cells[(0, BLANK, attr, t)] += 0
    return cam, sig, band, cells, pairs, font or band is not None, logo


# The CV romhack's title logo (mrdo_core.asm cvb_ANIMATEDLOGO): Graphics I
# tiles whose colour is per group of 8 codes; its colour bars animate by
# pointing the colour table at one of 12 64-byte frames (R3 $80-$85 once,
# then $86-$8B looping), a frame every 4 vblanks. Here (Screen 2) each logo
# tile gets fixed code LOGO_BASE + i and its colour is rewritten per frame
# (src/logo.asm). Block: romhack rows 3-10, columns 6-25 -> LOGO_AT (screen
# rows 1-8, columns 2-21, over the arcade logo's place).
LOGO_AT = (1, 8, 2, 21)
LOGO_SRC = (3, 6)                # romhack row, column of the block's corner


def romhack_logo():
    """-> dict(base, tiles [(pattern, colour)], blob): blob (src/logo.asm) =
    names 8 x 20 (codes), then 12 frames x LOGO_N colour bytes (one per
    tile: all 8 rows of a Graphics I tile share it)."""
    import gen_sprites_hack as H
    ts = H.pletter(H.db_block(H.CORE, "cvb_TILESET"))
    pnt = H.pletter(H.db_block(H.CORE, "cvb_PNT"))
    cf = H.pletter(H.db_block(H.CORE, "colorframes_plt"))
    rows, cols = LOGO_AT[1] - LOGO_AT[0] + 1, LOGO_AT[3] - LOGO_AT[2] + 1
    block = [pnt[(LOGO_SRC[0] + r) * 32 + LOGO_SRC[1] + c] for r in range(rows) for c in range(cols)]
    uniq = sorted(set(block))
    base = SCREEN_MAX - len(uniq)
    tiles = [(bytes(ts[t * 8:t * 8 + 8]), bytes([cf[t // 8]]) * 8) for t in uniq]
    names = bytes(base + uniq.index(t) for t in block)
    frames = b"".join(bytes(cf[f * 64 + t // 8] for t in uniq) for f in range(12))
    return {"base": base, "tiles": tiles, "blob": names + frames}


def hkey(k):
    a, b, c, e = k
    return (e + ((c ^ b ^ a) << 2)) & (HASH_N - 1)


def pkey(k):
    """Pair hash: ((left tile ^ rlc3(right tile)) * 2 + bit 2 of (left attr ^
    right attr)). 1.1 probes on average for the VERY GOOD scene (a sum of the
    tiles clustered: 6.8, up to 60)."""
    la, lt, ra, rt = k
    r3 = ((rt << 3) | (rt >> 5)) & 0xFF
    return (((lt ^ r3) << 1) | ((la ^ ra) >> 2 & 1)) & (PAIR_N - 1)


def distance(t1, t2):
    (p1, c1), (p2, c2) = t1, t2
    d = sum(bin(a ^ b).count("1") for a, b in zip(p1, p2))
    for a, b in zip(c1, c2):
        for s in (4, 0):
            x, y = G.TMS[(a >> s) & 15], G.TMS[(b >> s) & 15]
            d += sum(abs(i - j) for i, j in zip(x, y)) // 64
    return d


class Banks:
    """Packs blobs into 16KB banks, never into a bank's last 64 bytes."""
    def __init__(self):
        self.banks = []

    def put(self, blob, per_bank):
        """-> (bank number, address); up to `per_bank` blobs of a kind share a bank."""
        if not self.banks or self.banks[-1][1] != per_bank or self.banks[-1][2] >= per_bank:
            self.banks.append([bytearray(), per_bank, 0])
        b = self.banks[-1]
        addr = 0xC000 + len(b[0])
        b[0] += blob
        b[2] += 1
        assert len(b[0]) <= BANK_USE
        return SCR_BANK0 + len(self.banks) - 1, addr

    def data(self):
        return b"".join(bytes(b) + b"\xff" * (BANK - len(b)) for b, _, _ in self.banks)


def main():
    gfx1, gfx2, _, proms = load_all()
    fgt, bgt = G.decode_chars(gfx1), G.decode_chars(gfx2)
    pal = build_palette(proms)

    def pixels(k):
        """(bg attr, bg tile, fg attr, fg tile) -> 8x8 TMS indices, native [y][x]."""
        out = [[1] * 8 for _ in range(8)]
        for tiles, (attr, tile) in ((bgt, (k[0], k[1])), (fgt, (k[2], k[3]))):
            art = tiles[tile + ((attr & 0x80) << 1)]
            line = (attr & 0x3F) * 4
            for y in range(8):
                for x in range(8):
                    pen = art[y][x]
                    if pen or attr & 0x40:
                        out[y][x] = G.tms_index(pal[line + pen])
        return out

    def compose(k):
        return G.to_screen2(G.rot(pixels(k)))

    def pair_tiles(k):
        """The 8 phases of a bg pair: the bg layer scrolls along the native
        first index (the player-view x axis), so phase s shows rows s..s+7 of
        left + right. 16 bytes per phase: pattern, then colour."""
        la, lt, ra, rt = k
        left = pixels((la, lt, 0, BLANK))
        right = pixels((ra, rt, 0, BLANK)) if (ra, rt) != (0xFF, 0xFF) else pixels((0, BLANK, 0, BLANK))
        out = bytearray()
        for s in range(8):
            cell = [left[i + s] if i + s < 8 else right[i + s - 8] for i in range(8)]
            p, c = G.to_screen2(G.rot(cell))
            out += p + c
        return out

    OUT.mkdir(parents=True, exist_ok=True)
    lg = romhack_logo()
    banks = Banks()
    entries, sets, hashes = [], [], []
    for name in SCREENS:
        cam, sig, band, cells, pairs, font, logo = load(name)
        room = min(SCREEN_MAX, 256 - 2 * BAND_SLOTS) if band else SCREEN_MAX   # slots may use 224-255
        if logo:
            assert logo == LOGO_AT, f"{name}: logo at {logo}, src/logo.asm expects {LOGO_AT}"
            room = lg["base"]
        if font:                    # every font character in each colour used
            chars = {}              # for varying text (6+ different characters;
            for k in cells:         # one-off labels such as "5TH" stay as seen)
                if k[3] in FONT_TILES:
                    chars.setdefault(k[2], set()).add(k[3])
            for attr, seen in chars.items():
                if len(seen) >= 6:
                    for t in FONT_TILES:
                        cells[(0, BLANK, attr, t)] += 0
        tile_of = {k: compose(k) for k in cells}
        weight = Counter()
        for k, n in cells.items():
            weight[tile_of[k]] += n + 1
        kept = [t for t, _ in weight.most_common(room)]
        if band:                    # code 0 = black: the band's empty cells
            black = compose((0, BLANK, 0, BLANK))
            kept = [black] + [t for t in kept if t != black][:room - 1]
        code = {t: i for i, t in enumerate(kept)}
        merged = 0
        for t in weight:
            if t not in code:
                code[t] = code[min(kept, key=lambda k: distance(k, t))]
                merged += 1
        keys = bytearray(b"\xff" * (HASH_N * 4))
        codes = bytearray(b"\xff" * HASH_N)
        for k in cells:
            h = hkey(k)
            while codes[h] != 0xFF:
                h = (h + 1) & (HASH_N - 1)
            keys[h * 4:h * 4 + 4] = bytes(k)
            codes[h] = code[tile_of[k]]
        if logo:                    # the logo's tiles at their fixed codes
            pad = [(bytes(8), bytes(8))] * (lg["base"] - len(kept))
            kept_all = kept + pad + lg["tiles"]
        else:
            kept_all = kept
        blob = bytearray([len(kept_all), 0])
        blob += b"".join(p for p, _ in kept_all) + bytes(8 * (G.MAX - len(kept_all)))
        blob += b"".join(c for _, c in kept_all) + bytes(8 * (G.MAX - len(kept_all)))
        assert len(blob) == G.SET_BYTES
        sets.append(blob)
        hashes.append(keys + codes)
        entries.append((name, cam, sig, band, len(kept), pairs, logo))
        print(f"{name}: {len(cells)} cells -> {len(weight)} tiles, {len(kept)} kept, "
              f"{merged} merged into their nearest; cam {cam}, signature ${sig[0]:03x}=${sig[1]:02x}"
              + (f"; band rows {band[0]}-{band[1]}, {len(pairs)} pairs" if band else ""))
    set_at = [banks.put(b, 4) for b in sets]
    hash_at = [banks.put(h, 3) for h in hashes]
    index = bytearray()
    for i, (name, cam, sig, band, nkept, pairs, logo) in enumerate(entries):
        pbank = 0
        if band:
            # One bank: keys (512 x 4) at $C000, ids at $C800, then 64 bytes
            # per pair (phases 0, 2, 4, 6: the band scrolls in 2-pixel steps)
            # at $D000 + id * 64.
            order = sorted(pairs, key=lambda k: -pairs[k])
            assert len(order) <= PAIR_MAX, f"{name}: {len(order)} pairs > {PAIR_MAX}"
            ph = bytearray(b"\xff" * (PAIR_N * 4)) + bytearray(PAIR_N) + bytearray(0x1000 - PAIR_N * 5)
            for pid, p in enumerate(order):
                h = pkey(p)
                while ph[h * 4:h * 4 + 4] != b"\xff\xff\xff\xff":
                    h = (h + 1) & (PAIR_N - 1)
                ph[h * 4:h * 4 + 4] = bytes(p)
                ph[PAIR_N * 4 + h] = pid
            for p in order:
                t = pair_tiles(p)
                ph += b"".join(t[s * 16:s * 16 + 16] for s in (0, 2, 4, 6))
            pbank, _ = banks.put(ph, 1)
        sb, sa = set_at[i]
        hb, ha = hash_at[i]
        row0 = band[0] - cam if band else 0
        nrows = band[1] - band[0] + 1 if band else 0
        assert not band or 0 <= row0 and row0 + nrows <= 24
        index += bytes([sig[0] & 0xFF, sig[0] >> 8, sig[1], cam, sb, sa & 0xFF, sa >> 8,
                        hb, ha >> 8, row0, nrows, pbank, nkept, IMAGES.get(name, 0),
                        1 if logo else 0, 0])
    data = banks.data()
    (OUT / "banks.bin").write_bytes(data)
    (OUT / "banks.inc").write_text(f"SCR_BANKS equ {len(data) // BANK}\n")
    (OUT / "index.bin").write_bytes(index)
    (OUT / "logo.bin").write_bytes(lg["blob"])
    (OUT / "logo.inc").write_text(f"LOGO_BASE equ {lg['base']}\nLOGO_N equ {len(lg['tiles'])}\n")
    print(f"screens: {len(SCREENS)} in {len(data) // BANK} banks from {SCR_BANK0}")


if __name__ == "__main__":
    main()
