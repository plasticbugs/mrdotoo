import json, glob, re, collections
D={}
for l in open('dasm.txt'):
    m=re.match(r'([0-9A-F]{4}): ((?:[0-9A-F]{2} )+)\s*(.*)',l)
    if m: D[int(m.group(1),16)]=(m.group(3).strip(), len(m.group(2).split()))
rom=open('/Users/scottmoschella/work/do_disassemble/mrdo_main.bin','rb').read()
files=sorted(glob.glob('sweep/s*.json'))
exec_=set(); code=set(); into7=collections.Counter(); romdata={}; ram={}; rampc={}; vid={}; io={}; minsp=0xffff; frames=0
def mrg(t,k,v,sumidx=None,mn=(),mx=(),orr=()):
    if k not in t: t[k]=list(v); return
    e=t[k]
    for i in mn: e[i]=min(e[i],v[i])
    for i in mx: e[i]=max(e[i],v[i])
    if sumidx is not None: e[sumidx]+=v[sumidx]
    for i in orr: e[i]|=v[i]
perfile={}
for fn in files:
    d=json.load(open(fn)); frames+=d['frames']
    exec_|=set(d['exec']); code|=set(d['code'])
    for k,v in d['into7'].items(): into7[k]+=v
    for k,v in d['romdata'].items(): mrg(romdata,int(k),v,2,(0,),(1,))
    for k,v in d['ram'].items(): ram[int(k)]=ram.get(int(k),0)|v
    for k,v in d['rampc'].items(): mrg(rampc,k,v,2,(0,3),(1,4))
    for k,v in d['vid'].items(): mrg(vid,k,v,2,(0,3),(1,4),(5,))
    for k,v in d['io'].items(): mrg(io,k,v,0,(1,),(2,))
    minsp=min(minsp,d['minsp'])
    perfile[fn]=(d['frames'],len(d['exec']))
def ranges(s):
    s=sorted(s); out=[]
    for a in s:
        if out and a==out[-1][1]+1: out[-1][1]=a
        else: out.append([a,a])
    return out
def ins(pc): return D.get(pc,('?',1))[0]
R={}
print("frames",frames, perfile)
# 1 video
Q=['8000 bg attr','8400 bg tile','8800 fg attr','8C00 fg tile']
print("\n## VIDEO RAM")
for rw in 'rw':
    byq=collections.defaultdict(list)
    for k,v in vid.items():
        pc,r=k.split(':'); 
        if r!=rw: continue
        for qi in range(4):
            if v[5]>>qi&1: byq[qi].append(int(pc))
    for qi in range(4): print(rw,Q[qi],len(byq[qi]),'PCs' + (': '+' '.join('%04X'%p for p in sorted(byq[qi])) if rw=='r' or len(byq[qi])<=40 else ''))
print("read PCs detail:")
for k,v in sorted(vid.items(), key=lambda kv:int(kv[0].split(':')[0])):
    pc,r=k.split(':')
    if r=='r': print(f"  {int(pc):04X} {ins(int(pc)):26s} {v[0]:04X}-{v[1]:04X} n={v[2]} q={v[5]:04b}")
# 2 RAM
print("\n## WORK RAM")
touched=sorted(ram); rr=ranges([a for a in ram])
print("touched bytes",len(touched),"untouched",4096-len(touched),"minSP %04X depth below EB80: %d"%(minsp,0xEB80-minsp))
print("touched ranges:",' '.join('%04X-%04X'%(a+0xE000,b+0xE000) for a,b in rr))
ro=[a for a,v in ram.items() if v==1]; wo=[a for a,v in ram.items() if v==2]
print("read-only bytes",len(ro),' '.join('%04X-%04X'%(a+0xE000,b+0xE000) for a,b in ranges(ro))[:400])
print("write-only bytes",len(wo),' '.join('%04X-%04X'%(a+0xE000,b+0xE000) for a,b in ranges(wo))[:600])
# 3 IO
print("\n## IO")
grp=collections.defaultdict(lambda:[set(),256,-1,0])
for k,v in io.items():
    pc,r,a=k.split(':'); a=int(a)
    key=('9000-90FF +%d'%(a&3)) if 0x9000<=a<=0x90FF else ('F000-F7FF' if 0xF000<=a<=0xF7FF else ('F800-FFFF' if a>=0xF800 else '%04X'%a))
    e=grp[(key,r)]; e[0].add(int(pc)); e[3]+=v[0]
    if r=='w': e[1]=min(e[1],v[1]); e[2]=max(e[2],v[2])
for (a,r),e in sorted(grp.items()):
    print(f"  {a:16s} {r} n={e[3]} vals {'%02X-%02X'%(e[1],e[2]) if r=='w' else '':6s} PCs: "+' '.join('%04X'%p for p in sorted(e[0])))
# 4 exec
print("\n## EXEC")
for lo,hi,name in ((0,0x5fff,'0000-5FFF'),(0x6000,0x6fff,'6000-6FFF'),(0x7000,0x7fff,'7000-7FFF')):
    cs=[a for a in code if lo<=a<=hi]; es=[a for a in exec_ if lo<=a<=hi]
    rg=ranges(cs)
    print(name,"code bytes",len(cs),"instr",len(es),"ranges",len(rg))
    if name!='0000-5FFF': print('   ',' '.join('%04X-%04X'%(a,b) for a,b in rg))
print("transfers into 7000-7FFF:")
for k,v in sorted(into7.items()):
    s,d=map(int,k.split('>')); print(f"  {s:04X} {ins(s):24s} -> {d:04X} x{v}")
# 5 rom data reads
print("\n## DATA READS 6000-7FFF")
for pc,v in sorted(romdata.items()):
    if v[1]>=0x6000: print(f"  {pc:04X} {ins(pc):24s} {v[0]:04X}-{v[1]:04X} n={v[2]}")
json.dump(dict(exec_ranges=ranges(exec_),code_ranges=ranges(code),into7=into7,romdata={'%04X'%k:v for k,v in romdata.items()},
  ram_bitmap={'%04X'%(k+0xE000):v for k,v in sorted(ram.items())},rampc=rampc,vid=vid,io=io,minsp=minsp,frames=frames),open('sweep/merged.json','w'))
R.update(vid=vid,rampc=rampc,io=io,romdata=romdata)
import pickle; pickle.dump((vid,rampc,io,romdata,code),open('sweep/merged.pkl','wb'))
