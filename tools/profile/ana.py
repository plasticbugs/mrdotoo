import sys, statistics as st
ev=[]
for line in open(sys.argv[1]):
    p=line.split()
    if not p or p[0] not in ('I','D','E','P0','P1','P2'): continue
    ev.append((p[0],int(p[1]), p[2] if len(p)>2 else None))
skip=int(sys.argv[2]) if len(sys.argv)>2 else 0
Is=[i for i,e in enumerate(ev) if e[0]=='I']
periods=[]; isr=[]; nonidle_int=0
for a,b in zip(Is,Is[1:]):
    t0=ev[a][1]; t1=ev[b][1]
    idle=0; start=None
    # was idle at t0? interrupted pc
    for k in range(a+1,b):
        if ev[k][0]=='D': start=ev[k][1]
        if ev[k][0] in('E','P0','P1','P2') and not any(x[0]=='E' or x[0][0]=='P' for x in ev[a+1:k]): isr.append(ev[k][1]-t0)
    if start is not None: idle=t1-start
    periods.append((t1-t0, t1-t0-idle, ev[a][2]))
periods=periods[skip:]
n=len(periods)
busy=sorted(p[1] for p in periods); L=[p[0] for p in periods]
isr=sorted(isr[skip:])
def q(v,x): return v[min(len(v)-1,int(x*len(v)))]
print("frames",n,"period mean",st.mean(L), "min",min(L),"max",max(L))
print("busy min %d med %d p95 %d p99 %d max %d mean %.0f"%(busy[0],q(busy,.5),q(busy,.95),q(busy,.99),busy[-1],st.mean(busy)))
print("isr  min %d med %d p95 %d max %d"%(isr[0],q(isr,.5),q(isr,.95),isr[-1]))
print("full-busy frames (no idle):",sum(1 for p in periods if p[0]==p[1]))
print("interrupted non-idle pc:", {p[2] for p in periods if p[2] not in ('AC','154')})
