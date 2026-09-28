import re, json
m=json.load(open('sweep/merged.json'))
execset=set()
for a,b in m['exec_ranges']: execset|=set(range(a,b+1))
D={}; order=[]
for l in open('dasm.txt'):
    mm=re.match(r'([0-9A-F]{4}): ((?:[0-9A-F]{2} )+)\s*(.*)',l)
    if mm: a=int(mm.group(1),16); D[a]=mm.group(3).strip(); order.append(a)
ex=[a for a in order if a in execset and a<0x8000]
out=[]
HB=('h','d','b','ixh','iyh')
for i,a in enumerate(ex):
    t=D[a]
    mm=re.match(r'ld\s+(h|d|b|ixh|iyh),\$([0-9A-F]{2})$',t)
    if mm and int(mm.group(2),16)>=0x80:
        out.append(('A ld hi,imm',a,t,'')); continue
    # arithmetic with imm feeding a high-byte register
    mm=re.match(r'(add|adc|sub|sbc|or|and|xor)\s+(?:a,)?\$([0-9A-F]{2})$',t)
    if mm:
        nxt=[D[x] for x in ex[i+1:i+4]]; prv=[D[x] for x in ex[max(0,i-3):i]]
        dest=[n for n in nxt if re.match(r'ld\s+(h|d|b|ixh|iyh),a$',n)]
        src=[p for p in prv if re.match(r'ld\s+a,(h|d|b|ixh|iyh)$',p)]
        if dest and (int(mm.group(2),16)>=0x80 or src):
            out.append(('B hi arith',a,t,' | prev: '+'; '.join(prv)+' | next: '+'; '.join(nxt)))
        continue
    mm=re.match(r'cp\s+\$([0-9A-F]{2})$',t)
    if mm and int(mm.group(1),16)>=0x80:
        prv=[D[x] for x in ex[max(0,i-2):i]]
        if any(re.match(r'ld\s+a,(h|d|b|ixh|iyh)$',p) for p in prv):
            out.append(('C cmp hi',a,t,' | prev: '+'; '.join(prv)))
for k,a,t,c in out: print(f"{k:12s} {a:04X} {t:18s}{c}")
json.dump([dict(kind=k,pc='%04X'%a,ins=t,ctx=c) for k,a,t,c in out],open('sweep/highbyte_builders.json','w'),indent=1)
