#!/usr/bin/env python3
"""Flicker-fairness simulator for TMS9918 sprite multiplexing (4 sprites per line)."""
# Full scanline model: sprites have a player-view Y; the VDP shows the first 4
# (in SAT order) covering each line. A sprite counts as visible if drawn on all
# its lines, "partly" if some lines were dropped.
import random
def frame_vis(order, ys):
    cnt=[0]*256; full={}
    for i in order:
        ok=True
        for l in range(ys[i], ys[i]+16):
            if cnt[l%256]>=4: ok=False
            else: cnt[l%256]+=1
        full[i]=ok
    return full
def cluster_order(f, ys, pinned=()):
    """Row-cluster multiplexer (the port's scheme)."""
    rest=sorted((i for i in range(len(ys)) if i not in pinned), key=lambda i: ys[i])
    out=list(pinned); c=[]
    def flush():
        cap=4-sum(1 for p in pinned if any(abs(ys[p]-ys[i])<16 for i in c))
        k=len(c)
        if k>cap:
            s=(f*cap)%k; out.extend(c[(s+j)%k] for j in range(k))
        else: out.extend(c)
    for i in rest:
        if c and ys[i]-ys[c[-1]]>=16: flush(); c.clear()
        c.append(i)
    flush(); return out
def revrot(f, ys, pinned=(), step=7):
    n=len(ys); o=((f//2)*step)%n
    seq=[(o+j)%n for j in range(n)] if f%2==0 else [(o-1-j)%n for j in range(n)]
    return list(pinned)+[i for i in seq if i not in pinned]
def romhack(f, ys, pinned=()):
    o=(4*f)%20; seq=[(o+j)%20 for j in range(20) if (o+j)%20<len(ys)]
    return list(pinned)+[i for i in seq if i not in pinned]
def measure(fn, scen, frames=600, pinned=()):
    n=len(scen(0)); vis=[0]*n; run=[0]*n; worst=[0]*n; crowd=set()
    for f in range(frames):
        ys=scen(f); full=frame_vis(fn(f,ys,pinned) if pinned else fn(f,ys), ys)
        for i in range(n):
            # only score sprites that share a line with >=4 others this frame
            if sum(1 for j in range(n) if abs(ys[j]-ys[i])<16) >= 5 and i not in pinned:
                crowd.add(i)
            if full[i]: vis[i]+=1; run[i]=0
            else: run[i]+=1; worst[i]=max(worst[i],run[i])
    if not crowd: return "no crowding"
    return f"{min(vis[i] for i in crowd)*100//frames:3d}% / {max(worst[i] for i in crowd):3d}"
def row(k, others=18):   # k sprites in one tunnel row, the rest scattered in rows 2+ apart
    ys=[80]*k+[(10+i*20)%176 if abs((10+i*20)%176-80)>=16 else 150 for i in range(others-k)]
    return lambda f: ys
def moving(f):           # 18 sprites drifting vertically at different speeds: churning clusters
    rnd=random.Random(1); base=[rnd.randrange(0,176) for _ in range(18)]; sp=[rnd.choice([-1,1])*rnd.random() for _ in range(18)]
    return [int(base[i]+sp[i]*f)%176 for i in range(18)]
def stair(f):            # diagonal cluster: overlapping chain, not all on one line
    return [40+i*6 for i in range(12)]+[150,160,170,10,20,0]
scen={'5 in a row':row(5),'8 in a row':row(8),'11 in a row':row(11),'staircase 12':stair,'18 moving':moving}
algos={'romhack +4':romhack,'reverse+rotate':revrot,'row clusters':cluster_order}
print(f"{'min visible / longest hidden run':32s}"+''.join(f'{s:>15s}' for s in scen))
for an,a in algos.items():
    print(f'{an:32s}'+''.join(f'{measure(a,s):>15s}' for s in scen.values()))
print("Mr. Do (sprite 0) pinned first:")
for an,a in algos.items():
    print(f'{an:32s}'+''.join(f'{measure(a,s,pinned=(0,)):>15s}' for s in scen.values()))
print("ideal (4/k):  5->80%/1  8->50%/1  11->36%/2")
