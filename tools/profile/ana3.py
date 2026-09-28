import sys, statistics as st
FB=68398; CV=59659
def q(v,x): v=sorted(v); return v[min(len(v)-1,int(x*len(v)))]
for fn in sys.argv[1:]:
    ev=[]; state=None
    for line in open(fn):
        p=line.split()
        if p and p[0] in ('I','D','E','P0','P1','P2'): ev.append((p[0],int(p[1])))
    # jobs: from P* until D, subtract ISR time (I..E/P) inside
    jobs=[]; cur=None; isr_in=0; ti=None; kind=None
    isrs=[]
    for k,(t,c) in enumerate(ev):
        if t=='I': ti=c
        elif t in('E','P0','P1','P2') and ti is not None:
            isrs.append(c-ti)
            if cur is not None: isr_in+=c-ti+14 if t=='E' else 0
            if t!='E':
                if cur is not None and t=='P0': jobs.append(('restart',cur[0],c-cur[1]-isr_in)); 
                if cur is None or t=='P0': cur=(t,c); isr_in=0
                # P1/P2 during a running job would be odd
            ti=None
        elif t=='D' and cur is not None:
            jobs.append((cur[0],c-cur[1]-isr_in,c-cur[1])); cur=None
    for kind in ('P0','P1','P2'):
        w=[j[1] for j in jobs if j[0]==kind]
        wall=[j[2]/FB for j in jobs if j[0]==kind]
        if w: print(fn,kind,"n=%d work med/p95/max=%d/%d/%d  wall-frames med/max=%.2f/%.2f"%(len(w),q(w,.5),q(w,.95),max(w),q(wall,.5),max(wall)))
    print(fn,"restarts",sum(1 for j in jobs if j[0]=='restart'))
