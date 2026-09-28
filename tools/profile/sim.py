import sys
FB=68398
def run(fn, budget, vdp):
    ev=[(p[0],int(p[1])) for p in (l.split() for l in open(fn)) if p and p[0] in('I','D','E','P0','P1','P2')]
    # per ISR: isr cycles, and bg job work started at it (P0/P1 work measured on arcade)
    frames=[]; ti=None
    cur=None; isr_in=0
    for t,c in ev:
        if t=='I': ti=c
        elif t in('E','P0','P1','P2') and ti is not None:
            frames.append([c-ti,None]); 
            if cur and t=='E': isr_in+=c-ti+14
            if t in('P0','P1') : cur=(len(frames)-1,c); isr_in=0
            ti=None
        elif t=='D' and cur:
            frames[cur[0]][1]=c-cur[1]-isr_in; cur=None
    lat=[]; over=0; q=[]  # queue of [remaining, startframe]
    for i,(isr,job) in enumerate(frames):
        if job: q=[[job,i]]   # new request supersedes (BFS restart semantics)
        spare=budget-vdp-isr
        if spare<0: over+=1; spare=0
        while q and spare>0:
            use=min(spare,q[0][0]); q[0][0]-=use; spare-=use
            if q[0][0]==0: lat.append(i-q[0][1]+1); q.pop(0)
    lat.sort()
    return len(frames),over,lat
for b,v,name in ((68398,0,'arcade'),(59659,0,'CV no VDP'),(59659,4000,'CV -4k VDP'),(59659,8000,'CV -8k VDP')):
    n,over,lat=run(sys.argv[1],b,v)
    print(f"{name:12s} frames={n} overrun={over} bg-job latency (frames) med={lat[len(lat)//2]} p95={lat[int(.95*len(lat))]} max={lat[-1]}")
