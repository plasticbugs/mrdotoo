#!/usr/bin/env python3
"""Apple visibility from VRAM dumps (tools/diff/apple_vis.tcl, run by tools/apple_vis.sh): for each apple in the arcade's
sprite RAM, which of its pattern lines the TMS9918 really draws (SAT order,
first 4 sprites per line), or whether its 4 tiles are in the shown name table.
Display lags the arcade, so an apple counts as shown at any of its positions in
the last few distinct arcade sprite states."""
import sys
from collections import Counter, defaultdict

REC = 4 + 256 + 128 + 768 + 2048
from pathlib import Path
PAT = (Path(__file__).resolve().parent.parent / 'build/sprites/pat.bin').read_bytes()
APPLE = set(range(0x5D, 0x66))
WIN = 4


def expected(Y, X, cam):
    yb = 240 - cam * 8
    x = 224 - Y
    y = yb - X
    if x < -31 or x >= 192 or y < -15 or y >= 192:
        return None
    return ((y - 1) & 0xFF, x + 32 if x < 0 else x, 0x80 if x < 0 else 0, y)


def pat_rows(code):
    """per flip: 16 row masks (any pixel in that row)"""
    out = []
    for fl in range(4):
        b = PAT[(code * 4 + fl) * 32:(code * 4 + fl) * 32 + 32]
        out.append([b[r] | b[16 + r] for r in range(16)])
    return out


def drawn_lines(sat):
    """SAT index -> set of screen lines it is drawn on (4 per line rule)."""
    per_line = defaultdict(list)
    ents = []
    for i in range(32):
        sy, sx, nm, cl = sat[i * 4:i * 4 + 4]
        if sy == 0xD0:
            break
        ents.append((sy, sx, nm, cl))
        for k in range(16):
            ln = (sy + 1 + k) & 0xFF
            if ln < 192:
                per_line[ln].append(i)
    drawn = defaultdict(set)
    for ln, lst in per_line.items():
        for i in lst[:4]:
            drawn[i].add(ln)
    return ents, drawn


def main(path):
    d = open(path, 'rb').read()
    n = len(d) // REC
    hist = []                       # last distinct arcade apple states
    stats = Counter()
    streak = {}                     # key -> current bad run
    worst = Counter()
    runs = defaultdict(Counter)     # kind -> run length histogram
    examples = []
    prev_cam = None
    for f in range(n):
        r = d[f * REC:(f + 1) * REC]
        mode, r2, cam, r1 = r[0], r[1], r[2], r[3]
        arc = r[4:260]
        sat = r[260:388]
        pnt = r[388:1156]
        spt = r[1156:3204]
        apples = []
        for i in range(64):
            c, Y, col, X = arc[i * 4:i * 4 + 4]
            if Y == 0:
                break
            if (c & 0x7F) in APPLE:
                apples.append((c & 0x7F, Y, X))
        if not hist or hist[-1] != apples:
            hist.append(apples)
            hist = hist[-WIN:]
        ents, drawn = drawn_lines(sat)
        cams = {cam} | ({prev_cam} if prev_cam is not None else set())
        prev_cam = cam
        # the apple set to judge: the state before the newest (the SAT shown
        # was built from it or an older one)
        near = lambda a, st: any(abs(a[1] - b[1]) <= 8 and abs(a[2] - b[2]) <= 8 for b in st)
        judge = [a for a in hist[-1] if len(hist) < 2 or near(a, hist[-2])]
        cand_all = [a for st in hist for a in st]
        seen_keys = set()
        for (c, Y, X) in judge:
            key = (Y // 4, X // 4)
            best = None             # (drawn, needed)
            for (c2, Y2, X2) in cand_all:
                if abs(Y2 - Y) > 8 or abs(X2 - X) > 8:
                    continue
                for cm in cams:
                    e = expected(Y2, X2, cm)
                    if e is None:
                        continue
                    sy, sx, ec, y = e
                    rows = pat_rows(c2)[0]
                    need = {(y + k) for k in range(16) if 0 <= y + k < 192 and rows[k]}
                    if not need:
                        continue
                    # tiles?
                    tx, sr = 28 - Y2 // 8, 30 - X2 // 8 - cm
                    ok_t = Y2 % 8 == 0 and X2 % 8 == 0 and all(
                        0 <= sr + dy < 24 and pnt[(sr + dy) * 32 + tx + dx] == 172 + dy * 2 + dx
                        for dy in range(2) for dx in range(2)) and 0 <= tx < 23
                    if ok_t:
                        got = len(need)
                    else:
                        got = 0
                        for i, (esy, esx, nm, cl) in enumerate(ents):
                            if esy == sy and esx == sx and (cl & 0x80) == ec and (cl & 0x0F):
                                g = PAT[0:0]
                                sp = spt[(nm & 0xFC) * 8:(nm & 0xFC) * 8 + 32]
                                if not any(sp):
                                    continue
                                lines = {((esy + 1 + k) & 0xFF) for k in range(16)} & drawn[i]
                                got = max(got, len(need & lines))
                    if best is None or got / len(need) > best[0] / best[1]:
                        best = (got, len(need))
            if best is None:
                continue            # off screen
            stats['apple-vblanks'] += 1
            g, nd = best
            kind = 'full' if g == nd else ('partial' if g else 'gone')
            stats[kind] += 1
            seen_keys.add(key)
            if kind != 'full':
                st = streak.get(key, (0, kind))
                k2 = 'gone' if (kind == 'gone' or st[1] == 'gone') else 'partial'
                streak[key] = (st[0] + 1, k2)
                if st[0] + 1 == 9:
                    examples.append(f"LONG dump {f}: {k2} apple {c:02X} Y={Y} X={X} cam={cam} sat={len(ents)} got={best}")
                if False:
                    nsat = len(ents)
                    examples.append(f"dump {f}: {kind} apple {c:02X} Y={Y} X={X} cam={cam} sat={nsat}")
            else:
                if key in streak:
                    ln, k2 = streak.pop(key)
                    runs[k2][ln] += 1
        for key in list(streak):
            if key not in seen_keys:
                ln, k2 = streak.pop(key)
                runs[k2][ln] += 1
    print(f"{path}: {n} vblanks, {stats['apple-vblanks']} apple-vblanks: "
          f"full {stats['full']}, partial {stats['partial']}, gone {stats['gone']}")
    for k in ('partial', 'gone'):
        if runs[k]:
            print(f"  {k} runs (length: count): " + ", ".join(f"{l}:{c}" for l, c in sorted(runs[k].items())))
    for e in examples:
        print("  " + e)


if __name__ == "__main__":
  for p in sys.argv[1:]:
    main(p)
