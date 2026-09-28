import glob, collections, sys
sys.argv=['x']; exec(open('ana2.py').read().split("allp={}")[0])  # reuse load(), q()
exec(open('sim.py').read().split("for b,v,name")[0])
groups=collections.defaultdict(list)
lat={}
for fn in sorted(glob.glob('c_*.log')):
    name=fn[2:-4]
    for p in load(fn)[60:]:
        s=p['st']; g=int(s[6],16)
        if (g&0xC0)!=0xC0 or p['L']>FB*1.2 or p['L']<FB*0.8: continue
        nm,nc=int(s[1]),int(s[3])
        objs=s[11] if len(s)>11 else ''
        moving=any(o!='80' for o in objs.split(',') if o)
        key=name.split('_s')[0] if name.startswith(('w3','w4','w5','w6','old_play')) else name
        groups[key].append(p)
        if nm>=7 and nc==3: groups['* >=7 mon + 3 chompers'].append(p)
        if nm>=8 and nc==3: groups['* 8 mon + 3 chompers'].append(p)
        if nm>=6 and moving: groups['* >=6 mon + apple moving'].append(p)
    if 'play' in name or name.startswith('w'):
        for b,v,nmx in ((68398,0,'arc'),(59659,4000,'cv4k')):
            n,over,l=run(fn,b,v); lat.setdefault(name.split('_s')[0] if '_s' in name else name,{}).setdefault(nmx,[]).extend(l)
print(f"{'scenario':28s} {'n':>6s} {'min':>6s} {'med':>6s} {'p95':>6s} {'max':>6s}  >55659  >59659  busy-mean")
for g,per in sorted(groups.items()):
    i=sorted(p['isr'] for p in per); n=len(i)
    a=sum(1 for x in i if x>55659)/n*100; b=sum(1 for x in i if x>59659)/n*100
    print(f"{g:28s} {n:6d} {i[0]:6d} {q(i,.5):6d} {q(i,.95):6d} {i[-1]:6d}  {a:5.2f}%  {b:5.2f}%  {st.mean(p['busy'] for p in per):.0f}")
print("pathfinder latency frames med/p95/max  arcade | CV(59659-4k)")
for k,d in sorted(lat.items()):
    A=sorted(d['arc']); C=sorted(d['cv4k'])
    print(f"{k:22s} {q(A,.5)}/{q(A,.95)}/{A[-1]}  |  {q(C,.5)}/{q(C,.95)}/{C[-1]}")
