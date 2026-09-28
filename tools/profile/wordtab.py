import json, glob, re, collections
rom=open('/Users/scottmoschella/work/do_disassemble/mrdo_main.bin','rb').read()
D={}
for l in open('dasm.txt'):
    mm=re.match(r'([0-9A-F]{4}): ((?:[0-9A-F]{2} )+)\s*(.*)',l)
    if mm: D[int(mm.group(1),16)]=mm.group(3).strip()
RA=collections.defaultdict(set)
for fn in glob.glob('sweep/s*.json'):
    d=json.load(open(fn))
    for k,v in d['romaddr'].items(): RA[int(k)]|=set(v)
json.dump({'%04X'%k:sorted(v) for k,v in RA.items()},open('sweep/rom_data_reads.json','w'))
# word loads: low-byte reader PC p and high-byte reader PC q where addresses of q = addresses of p + 1
pcs=sorted(RA); res=[]
for p in pcs:
    A=RA[p]
    for q in pcs:
        if q<=p or q-p>8: continue
        B=RA[q]
        if len(A)>0 and len({a+1 for a in A}&B)>=0.8*len(A):
            words=sorted({(a, rom[a]|rom[a+1]<<8) for a in A if a+1<len(rom)})
            hi=[(a,w) for a,w in words if w>=0x8000]
            if hi:
                rngs=collections.Counter(('%X'%(w>>12)) for a,w in hi)
                res.append((p,q,len(words),len(hi),min(a for a,w in hi),max(a for a,w in hi),dict(rngs),sorted({w for a,w in hi})[:6]))
for p,q,n,nh,lo,hi,r,ex in res:
    print(f"{p:04X}/{q:04X} {D.get(p,'?'):18s}/{D.get(q,'?'):18s} words {n:4d} >=8000: {nh:4d} table {lo:04X}-{hi+1:04X} hi-nibbles {r} e.g. {' '.join('%04X'%w for w in ex)}")
json.dump([dict(lo_pc='%04X'%p,hi_pc='%04X'%q,words=n,ptr_words=nh,table='%04X-%04X'%(lo,hi+1),regions=r) for p,q,n,nh,lo,hi,r,ex in res],open('sweep/rom_pointer_tables.json','w'),indent=1)
