#!/usr/bin/env python3
"""Tile sets for the arcade's non-gameplay screens (title, cutscenes, ...).

Each tools/data/screens/NAME.txt (made by tools/capture_screen.py) lists the
(bg attr, bg tile, fg attr, fg tile) cells the screen shows, with counts, its
camera row and a signature cell. For each screen this composes every cell into
a Screen 2 tile (same rules as tools/gen_tiles.py), dedupes, and if more than
SCREEN_MAX distinct tiles remain, maps the rarest onto their nearest kept tile.
The runtime finds a cell's tile code through a 512-entry open-addressed hash:

    h = (fg tile + (fg attr ^ bg tile ^ bg attr)) & 511, then h+1, h+2, ...

Output (build/screens/):
  sets.bin   screens x SET_BYTES (tile set, same layout as playfield sets)
  hash.bin   screens x 4KB: keys (512 x 4 bytes) then codes (512, $FF = empty)
  index.bin  screens x 4: signature cell offset (word), signature fg tile, cam
  preview_NAME.png  a representative frame through the tables
"""
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gen_tiles as G  # noqa: E402
from mrdo_gfx import build_palette, decode_chars, load_all  # noqa: E402

ROOT = HERE.parent
OUT = ROOT / "build" / "screens"
SCREEN_MAX = 224
HASH_N = 512
SCREENS = ["title"]


def load(name):
    cam, sig, cells = None, None, Counter()
    for line in (HERE / "data" / "screens" / f"{name}.txt").read_text().splitlines():
        if not line or line[0] == "#":
            continue
        f = line.split()
        if f[0] == "cam":
            cam = int(f[1])
        elif f[0] == "sig":
            sig = (int(f[1], 16), int(f[2], 16))
        else:
            cells[tuple(int(x, 16) for x in f[:4])] += int(f[4])
    return cam, sig, cells


def hkey(k):
    a, b, c, e = k
    return (e + (c ^ b ^ a)) & (HASH_N - 1)


def distance(t1, t2):
    (p1, c1), (p2, c2) = t1, t2
    d = sum(bin(a ^ b).count("1") for a, b in zip(p1, p2))
    for a, b in zip(c1, c2):
        for s in (4, 0):
            x, y = G.TMS[(a >> s) & 15], G.TMS[(b >> s) & 15]
            d += sum(abs(i - j) for i, j in zip(x, y)) // 64
    return d


def main():
    gfx1, gfx2, _, proms = load_all()
    fgt, bgt = G.decode_chars(gfx1), G.decode_chars(gfx2)
    pal = build_palette(proms)

    def compose(k):
        out = [[1] * 8 for _ in range(8)]
        for tiles, (attr, tile) in ((bgt, (k[0], k[1])), (fgt, (k[2], k[3]))):
            art = tiles[tile + ((attr & 0x80) << 1)]
            line = (attr & 0x3F) * 4
            for y in range(8):
                for x in range(8):
                    pen = art[y][x]
                    if pen or attr & 0x40:
                        out[y][x] = G.tms_index(pal[line + pen])
        return G.to_screen2(G.rot(out))

    OUT.mkdir(parents=True, exist_ok=True)
    sets, hashes, index = bytearray(), bytearray(), bytearray()
    for name in SCREENS:
        cam, sig, cells = load(name)
        tile_of = {k: compose(k) for k in cells}
        weight = Counter()
        for k, n in cells.items():
            weight[tile_of[k]] += n
        kept = [t for t, _ in weight.most_common(SCREEN_MAX)]
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
        blob = bytearray([len(kept), 0])
        blob += b"".join(p for p, _ in kept) + bytes(8 * (G.MAX - len(kept)))
        blob += b"".join(c for _, c in kept) + bytes(8 * (G.MAX - len(kept)))
        assert len(blob) == G.SET_BYTES
        sets += blob
        hashes += keys + codes + bytes(4096 - HASH_N * 5)
        index += bytes([sig[0] & 0xFF, sig[0] >> 8, sig[1], cam])
        print(f"{name}: {len(cells)} cells -> {len(weight)} tiles, {len(kept)} kept, "
              f"{merged} merged into their nearest; cam {cam}, signature ${sig[0]:03x}=${sig[1]:02x}")
    (OUT / "sets.bin").write_bytes(sets)
    (OUT / "hash.bin").write_bytes(hashes)
    (OUT / "index.bin").write_bytes(index)


if __name__ == "__main__":
    main()
