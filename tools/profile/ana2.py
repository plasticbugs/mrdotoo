import sys, statistics as st, collections
FB=68398  # arcade cycles/frame
CV=59659
def load(fn):
    ev=[]; 
    for line in open(fn):
        p=line.split()
        if not p: continue
        if p[0]=='F': ev.append(('F',None,p[1:]))
        elif p[0] in ('I','D','E','P0','P1','P2'): ev.append((p[0],int(p[1]),p[2:]))
    # attach next F state to each I
    per=[]  # (period, busy, isr, pf_cycles_in_period, state, interruptedpc)
    Iidx=[i for i,e in enumerate(ev) if e[0]=='I']
    for a,b in zip(Iidx,Iidx[1:]):
        t0,t1=ev[a][1],ev[b][1]
        st_=None
        for k in range(a+1,len(ev)):
            if ev[k][0]=='F': st_=ev[k][2]; break
        idle_start=None; isr_end=None
        for k in range(a+1,b):
            e=ev[k]
            if e[0]=='D': idle_start=e[1]
            if e[0] in ('E','P0','P1','P2') and isr_end is None: isr_end=e[1]
        busy=(t1-t0) - ((t1-idle_start) if idle_start else 0)
        isr=(isr_end-t0) if isr_end else (t1-t0)
        per.append(dict(L=t1-t0,busy=busy,isr=isr,st=st_,ipc=ev[a][2][0]))
    return per
def q(v,x): return v[min(len(v)-1,int(x*len(v)))]
def rep(name, per):
    if not per: print(name,"none"); return
    b=sorted(p['busy'] for p in per); i=sorted(p['isr'] for p in per)
    over=sum(1 for x in b if x>CV)
    tr=sum(1 for p in per if p['L']>FB*1.2)
    print(f"{name:28s} n={len(b):6d} busy min/med/p95/p99/max = {b[0]}/{q(b,.5)}/{q(b,.95)}/{q(b,.99)}/{b[-1]}  mean={st.mean(b):.0f} ({st.mean(b)/FB*100:.0f}%)  isr med/p95/max={q(i,.5)}/{q(i,.95)}/{i[-1]}  >CV:{over}  longISR(>1.2fr):{tr}")
allp={}
for fn in sys.argv[1:]:
    allp[fn]=load(fn)
cats=collections.defaultdict(list)
for fn,per in allp.items():
    for p in per[60:]:
        s=p['st']; g=int(s[6],16)
        if g&0x80 and g&0x40: c='play'
        elif g&0x40: c='demo(attract)'
        else: c='other screens'
        if p['L']>FB*1.2 or p['L']<FB*0.8: c+=' [transition]'
        cats[c].append(p)
        if 'play' in c and 'trans' not in c:
            cats['play nmon=%s'%s[1]].append(p)
            if s[3]!='0': cats['play chompers>0'].append(p)
for c in sorted(cats): rep(c,cats[c])
print()
for c in ('play','demo(attract)','play chompers>0'):
    per=cats[c]; n=len(per)
    isr=[p['isr'] for p in per]
    for th in (40000,50000,55659,59659):
        print(c,"ISR >",th,":",sum(1 for x in isr if x>th),"of",n, "(%.3f%%)"%(100*sum(1 for x in isr if x>th)/n))
    # average spare-cycle need: BFS background work fits? mean isr
    print(c,"mean isr %.0f, mean busy %.0f"%(st.mean(isr),st.mean(p['busy'] for p in per)))
    # consecutive frames with isr>55659
