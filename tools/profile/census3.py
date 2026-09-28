import sys, glob, collections
def q(v,x): v=sorted(v); return v[min(len(v)-1,int(x*len(v)))] if v else 0
def frames(fn):
    st=None
    for line in open(fn):
        p=line.split()
        if not p: continue
        if p[0]=='F': st=p; continue
        if p[0]!='S' or st is None: continue
        g0=int(st[7],16)
        cat='play' if (g0&0xC0)==0xC0 else ('demo' if g0&0x40 else 'other')
        ents=[tuple(bytes.fromhex(e)) for e in p[2:]]
        vis=[(c,y,a,x) for c,y,a,x in ents if x+15>=8 and x<=247 and ((256-y)&255)+15>=32 and ((256-y)&255)<=223]
        rows=[0]*272
        for c,y,a,x in vis:
            for r in range(x,x+16): rows[r]+=1
        yield dict(cat=cat,st=st,n=len(ents),vis=vis,worst=max(rows[8:248]),pairs={(c,a&0x30) for c,y,a,x in vis},nmon=int(st[2]),nch=int(st[4]))
groups=collections.defaultdict(list)
segs=[]
for fn in sorted(glob.glob('c_*.log')):
    name=fn[2:-4]; seg=set(); gap=0
    for fr in frames(fn):
        if fr['cat']=='play':
            groups[name].append(fr); groups['ALL play'].append(fr); seg|=fr['pairs']; gap=0
        else:
            groups['ALL '+fr['cat']].append(fr)
            gap+=1
            if gap>30 and seg: segs.append(len(seg)); seg=set()
    if seg: segs.append(len(seg))
print(f"{'group':26s} {'frames':>7s} spr max/p99  worstrow max/p99  pairs/frame max/p99  union")
for g,fr in sorted(groups.items()):
    n=[f['n'] for f in fr]; w=[f['worst'] for f in fr]; pr=[len(f['pairs']) for f in fr]
    u=set().union(*[f['pairs'] for f in fr])
    print(f"{g:26s} {len(fr):7d} {max(n):3d}/{q(n,.99):3d}   {max(w):3d}/{q(w,.99):3d}   {max(pr):3d}/{q(pr,.99):3d}  {len(u)}")
for g in ('ALL play','old_play_s1','old_play_s2','old_play_s3','w1_idle8','w2_idle_alpha','w6_nofire_s10'):
    fr=groups[g]; h=collections.Counter(min(f['worst'],11) for f in fr)
    print(g,'worst-row hist:',' '.join(f"{k}{'+' if k==11 else ''}:{h[k]}" for k in range(0,12)))
segs.sort(); print("per-round-segment (code,flip) union: n",len(segs),"median",q(segs,.5),"p90",q(segs,.9),"max",segs[-1])
