import sys, glob, collections
files=sorted(glob.glob('c_*.log'))
def q(v,x): v=sorted(v); return v[min(len(v)-1,int(x*len(v)))]
allpairs=collections.Counter(); allcodes=collections.Counter()
tot=dict(n=[],vis=[],row=[],pairs=[],apples=[],qc=[]); rowhist=collections.Counter()
segmax=0; segmax_info=None; seg_unions=[]
play_rows=collections.Counter()
for fn in files:
    st=None; seg=set(); 
    for line in open(fn):
        p=line.split()
        if not p: continue
        if p[0]=='F': st=p; continue
        if p[0]!='S': continue
        playing = st is not None and st[7] in ('C0','C8','80','88')  # game (in play) incl. demo? keep all for census
        ents=[bytes.fromhex(e) for e in p[2:]]
        vis=[]
        for c,y,a,x in ents:
            sy=(256-y)&255; sx=x
            if sx+15>=8 and sx<=247 and sy+15>=32 and sy<=223: vis.append((c,y,a,x))
        rows=[0]*256
        for c,y,a,x in vis:
            for r in range(x,min(x+16,256)): rows[r]+=1
        worst=max(rows[8:248]) if vis else 0
        pairs={(c,a&0x30) for c,y,a,x in vis}
        tot['n'].append(len(ents)); tot['vis'].append(len(vis)); tot['row'].append(worst); tot['pairs'].append(len(pairs))
        tot['apples'].append(sum(1 for c,y,a,x in vis if c==0x5e))
        rowhist[worst]+=1
        for pr in pairs: allpairs[pr]+=1
        for c,y,a,x in vis: allcodes[c]+=1
        g=st[7] if st else '00'
        if g in('C0','C8'): seg|=pairs
        else:
            if seg: seg_unions.append((len(seg),fn)); seg=set()
    if seg: seg_unions.append((len(seg),fn))
n=len(tot['n'])
print("frames",n)
for k in ('n','vis','row','pairs','apples'):
    print(k,"max",max(tot[k]),"p99",q(tot[k],.99),"p95",q(tot[k],.95),"med",q(tot[k],.5))
print("worst-row histogram:",sorted(rowhist.items()))
print("distinct (code,flip) overall:",len(allpairs),"distinct codes:",len(allcodes))
su=sorted(seg_unions); print("per-play-segment union sizes: max",su[-1],"p90",su[int(.9*len(su))][0],"n",len(su))
print("codes:",' '.join('%02X'%c for c in sorted(allcodes)))
print("pairs by code:",' '.join('%02X:%s'%(c,''.join(str(f>>4) for cc,f in sorted(allpairs) if cc==c)) for c in sorted(allcodes)))
