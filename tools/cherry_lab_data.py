#!/usr/bin/env python3
"""Data for the Cherry Lab page (artifacts/19-cherry-lab/cherry_lab.html,
published at https://claude.ai/artifact/WiiYJN5jCUntQSFhNDJcW2): per level look
(13 dirt pairs) the arcade cherry in its own colours, the current CV tiles, a
2-colours-per-row draft and the dirt tile; plus the romhack's 10 cherries.
usage: cherry_lab_data.py OUT.json   (after make: reads build/tiles, build/sprites)"""
import sys, os, json
from collections import Counter, OrderedDict
sys.path.insert(0, 'tools'); sys.path.insert(0, os.path.expanduser('~/work/do_disassemble/tools'))
import gen_tiles as G
import gen_sprites_hack as H
from mrdo_gfx import build_palette, decode_chars, load_all
gfx1, gfx2, _, proms = load_all()
fgt, bgt = decode_chars(gfx1), decode_chars(gfx2)
pal = build_palette(proms)
sets = open('build/tiles/sets.bin', 'rb').read()
tbl = open('build/tiles/tables.bin', 'rb').read()
cw = [(G.ROM[0x06E6 + i * 2], G.ROM[0x06E7 + i * 2]) for i in range(31)]
groups = OrderedDict()
for i, p in enumerate(cw):
    groups.setdefault(p, []).append(i)
QUAD = {(0, 0): 0x79, (1, 0): 0x7B, (0, 1): 0x78, (1, 1): 0x7A}   # (qx, qy) -> fg tile

def arcade_rgb(bg, fg_tile):
    """8x8 RGB (player view) + mask of fg pixels: the arcade's own colours."""
    out = [[(0, 0, 0)] * 8 for _ in range(8)]
    mask = [[0] * 8 for _ in range(8)]
    for layer, tiles, (attr, tile) in ((0, bgt, bg), (1, fgt, (0, fg_tile))):
        art = tiles[tile + ((attr & 0x80) << 1)]
        line = (attr & 0x3F) * 4
        for y in range(8):
            for x in range(8):
                pen = art[y][x]
                if pen or attr & 0x40:
                    out[y][x] = pal[line + pen]
                    if layer == 1 and pen:
                        mask[y][x] = 1
    return G.rot(out), G.rot(mask)

def tile_px(set_i, code):
    b = sets[set_i * G.SET_BYTES:(set_i + 1) * G.SET_BYTES]
    p = b[2 + code * 8:2 + code * 8 + 8]; c = b[2 + G.MAX * 8 + code * 8:2 + G.MAX * 8 + code * 8 + 8]
    return G.screen2_pixels(p, c)

def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(G.TMS[a], G.TMS[b]))

def draft_row(cols, mask):
    """8 TMS colours + cherry mask -> 8 colours using at most 2."""
    w = Counter()
    for c, m in zip(cols, mask):
        w[c] += 3 if m else 1
    cand = list(w)
    if len(cand) <= 2:
        return cols
    best = None
    for i in range(len(cand)):
        for j in range(i + 1, len(cand)):
            a, b = cand[i], cand[j]
            score = w[a] + w[b]
            if best is None or score > best[0]:
                best = (score, a, b)
    _, a, b = best
    return [c if c in (a, b) else (a if dist(c, a) <= dist(c, b) else b) for c in cols]

bgs = []
for n, (pair, levels) in enumerate(groups.items()):
    ci = levels[0]
    arc = [[None] * 16 for _ in range(16)]; tms = [[1] * 16 for _ in range(16)]; msk = [[0] * 16 for _ in range(16)]
    cur = [[1] * 16 for _ in range(16)]
    page = tbl[ci * 512:ci * 512 + 256]
    for (qx, qy), t in QUAD.items():
        rgb, m = arcade_rgb(pair, t)
        cp = tile_px(ci, page[t])
        for y in range(8):
            for x in range(8):
                arc[qy * 8 + y][qx * 8 + x] = '#%02x%02x%02x' % rgb[y][x]
                tms[qy * 8 + y][qx * 8 + x] = G.tms_index(rgb[y][x])
                msk[qy * 8 + y][qx * 8 + x] = m[y][x]
                cur[qy * 8 + y][qx * 8 + x] = cp[y][x]
    G._FGT, G._BGT, G._PAL = fgt, bgt, pal
    draft = G.cherry_design(pair)         # the ROM's default (tools/gen_tiles.py)
    dirt = tile_px(ci, page[0x77])
    lv = [l + 1 for l in levels]
    name = 'Chomper red' if pair == (0x28, 0x0C) else 'Scene ' + ', '.join(str(l) for l in lv[:4])
    bgs.append({'id': 'bg%d' % n, 'name': name, 'levels': lv, 'pair': '%02x/%02x' % pair,
                'arcade': arc, 'current': cur, 'draft': draft, 'dirt': dirt})
pt, ct = H.hack_tiles()
rh = []
for c, r in H.CHERRY_QUADS:
    q = H.quad_px(pt, ct, c, r)
    rh.append([[v if v else 1 for v in row] for row in q])
tmsrgb = ['#%02x%02x%02x' % t for t in G.TMS]
json.dump({'bgs': bgs, 'romhack': rh, 'tms': tmsrgb}, open(sys.argv[1], 'w'))
print(len(bgs), 'backgrounds;', len(rh), 'romhack variants')
