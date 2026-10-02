#!/usr/bin/env python3
"""Data for the Apple Lab page (artifacts/23-apple-lab/apple_lab.html): per
level look (13 dirt pairs) the resting apple over that look's dirt as the
arcade draws it (full colour), the current CV tiles (codes 172-175), the
in-game apple sprite over the dirt (what the apple turns into when it
wobbles or falls), a 2-colours-per-row draft and the dirt tile; plus the
romhack's apple (mask, 0 = dirt shows through).
usage: apple_lab_data.py OUT.json   (after make: reads build/tiles, build/sprites)"""
import sys, os, json
from collections import OrderedDict
sys.path.insert(0, 'tools'); sys.path.insert(0, os.path.expanduser('~/work/do_disassemble/tools'))
import gen_tiles as G
import gen_sprites_hack as H
from mrdo_gfx import build_palette, decode_chars, decode_sprites, load_all
from mrdo_sprites import msx_sprite, sprite_rgb

gfx1, gfx2, gfx3, proms = load_all()
fgt, bgt = decode_chars(gfx1), decode_chars(gfx2)
pal = build_palette(proms)
spr = decode_sprites(gfx3)
sets = open('build/tiles/sets.bin', 'rb').read()
tbl = open('build/tiles/tables.bin', 'rb').read()
cw = [(G.ROM[0x06E6 + i * 2], G.ROM[0x06E7 + i * 2]) for i in range(31)]
groups = OrderedDict()
for i, p in enumerate(cw):
    groups.setdefault(p, []).append(i)
APPLE, APPLE_LINE = 0x5E, 5
art = msx_sprite(spr[APPLE])                     # player view, pens 0-3
argb = sprite_rgb(proms, pal, APPLE_LINE)
G.apple_mask, G.APPLE_COLOUR = G.apple_sprite()  # the CV sprite: mask, TMS colour


def dirt_rgb(pair):
    """8x8 RGB of a plain dirt cell as the arcade draws it (player view)."""
    attr, tile = pair
    a = bgt[tile + ((attr & 0x80) << 1)]
    line = (attr & 0x3F) * 4
    return G.rot([[pal[line + a[y][x]] for x in range(8)] for y in range(8)])


def tile_px(set_i, code):
    b = sets[set_i * G.SET_BYTES:(set_i + 1) * G.SET_BYTES]
    p = b[2 + code * 8:2 + code * 8 + 8]
    c = b[2 + G.MAX * 8 + code * 8:2 + G.MAX * 8 + code * 8 + 8]
    return G.screen2_pixels(p, c)


bgs = []
for n, (pair, levels) in enumerate(groups.items()):
    ci = levels[0]
    drgb = dirt_rgb(pair)
    dirt = tile_px(ci, tbl[ci * 512 + G.DIRT_FG])     # the dirt as the CV draws it
    arc, tms, msk, cur, sp = ([[0] * 16 for _ in range(16)] for _ in range(5))
    for y in range(16):
        for x in range(16):
            pen = art[y][x]
            rgb = argb[pen] if pen else drgb[y % 8][x % 8]
            arc[y][x] = '#%02x%02x%02x' % tuple(rgb)
            tms[y][x] = G.tms_index(rgb) if pen else dirt[y % 8][x % 8]
            msk[y][x] = 1 if pen else 0
            sp[y][x] = G.APPLE_COLOUR if G.apple_mask[y][x] else dirt[y % 8][x % 8]
    for q, (qx, qy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):    # TL TR BL BR
        t = tile_px(ci, G.APPLE_BASE + q)
        for y in range(8):
            for x in range(8):
                cur[qy * 8 + y][qx * 8 + x] = t[y][x]
    # arcade-shaped draft: per 8-pixel half-row the 2 colours that cover the
    # most weight (apple pixels 3x), the others to the nearer of the two
    adraft = [G._reduce_row(tms[y][0:8], [3 if m else 1 for m in msk[y][0:8]]) +
              G._reduce_row(tms[y][8:16], [3 if m else 1 for m in msk[y][8:16]]) for y in range(16)]
    # best guess: the in-game sprite's apple whole (its shape and colour: the
    # handover to the wobbling sprite shows no change), and in each 8-pixel
    # half-row the dirt keeps its most common colour there
    draft = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for h in (0, 8):
            xs = range(h, h + 8)
            dirt_cols = [sp[y][x] for x in xs if not G.apple_mask[y][x]]
            keep = max(set(dirt_cols), key=lambda c: (dirt_cols.count(c), -c)) if dirt_cols else None
            for x in xs:
                draft[y][x] = G.APPLE_COLOUR if G.apple_mask[y][x] else (
                    sp[y][x] if any(G.apple_mask[y][xx] for xx in xs) is False else keep)
    lv = [l + 1 for l in levels]
    name = 'Chomper red' if pair == (0x28, 0x0C) else 'Scene ' + ', '.join(str(l) for l in lv[:4])
    bgs.append({'id': 'bg%d' % n, 'name': name, 'levels': lv, 'pair': '%02x/%02x' % pair,
                'arcade': arc, 'current': cur, 'sprite': sp, 'draft': draft, 'adraft': adraft, 'dirt': dirt})
hs = H.hack_sprites()
rmask = hs["EXTRA_SPRITE_COMP#APPLE"]
romhack = [[8 if rmask[y][x] else 0 for x in range(16)] for y in range(16)]   # red 8 (the hack's apple colour)
tmsrgb = ['#%02x%02x%02x' % t for t in G.TMS]
json.dump({'bgs': bgs, 'romhack': [romhack], 'tms': tmsrgb}, open(sys.argv[1], 'w'))
print(len(bgs), 'backgrounds')
