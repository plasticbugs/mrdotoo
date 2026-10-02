#!/usr/bin/env python3
"""Give every saved Apple Lab design the one apple shape (the chomper-red
design, tools/gen_sprites_hack.py APPLE_SHAPE_PAIR) and keep its dirt.

Per 8-pixel half-row: the apple's pixels take the apple colour; the rest
keeps the design's own dirt where the old apple never was. A half-row the
new apple touches keeps one dirt colour, the design's most common non-apple
colour there (else the plain dirt's); a half-row it no longer touches but
the old apple did goes back to the plain dirt. Writes tools/data/apples.json
and prints the changed pairs; DOCS=dir also writes one {pixels, pair} doc
per changed pair for the lab's database.
usage: apple_reshape.py   (after make: reads build/tiles for the plain dirt)"""
import json, os, sys
from collections import Counter
sys.path.insert(0, 'tools')
import gen_tiles as G
import gen_sprites_hack as H

F = 'tools/data/apples.json'
designs = json.load(open(F))
shape = H.user_apple()
A = H.APPLE_SHAPE_COL
sets = open('build/tiles/sets.bin', 'rb').read()
tbl = open('build/tiles/tables.bin', 'rb').read()
cw = [(G.ROM[0x06E6 + i * 2], G.ROM[0x06E7 + i * 2]) for i in range(31)]


def plain_dirt(pair):
    ci = cw.index(pair)
    b = sets[ci * G.SET_BYTES:(ci + 1) * G.SET_BYTES]
    code = tbl[ci * 512 + G.DIRT_FG]
    p, c = b[2 + code * 8:2 + code * 8 + 8], b[2 + G.MAX * 8 + code * 8:2 + G.MAX * 8 + code * 8 + 8]
    return G.screen2_pixels(p, c)


changed = {}
for key, px in designs.items():
    if key == H.APPLE_SHAPE_PAIR:
        continue
    pair = tuple(int(v, 16) for v in key.split('/'))
    dirt = plain_dirt(pair)
    out = list(px)
    for y in range(16):
        for h in (0, 8):
            xs = range(h, h + 8)
            old = [px[y * 16 + x] for x in xs]
            if any(shape[y][x] for x in xs):
                cand = Counter(c for x, c in zip(xs, old) if not (c == A))
                pd = Counter(dirt[y % 8][x % 8] for x in xs if not shape[y][x])
                keep = cand.most_common(1)[0][0] if cand else pd.most_common(1)[0][0]
                for x in xs:
                    out[y * 16 + x] = A if shape[y][x] else keep
            elif A in old:
                for x in xs:
                    out[y * 16 + x] = dirt[y % 8][x % 8]
    if out != px:
        designs[key] = out
        changed[key] = out
json.dump(designs, open(F, 'w'), indent=0)
open(F, 'a').write('\n')
print('reshaped:', ' '.join(changed) or 'none')
if os.environ.get('DOCS'):
    for key, out in changed.items():
        json.dump({'pair': key, 'pixels': out}, open(os.path.join(os.environ['DOCS'], key.replace('/', '_') + '.json'), 'w'))
