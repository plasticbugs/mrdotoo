import sys,re,collections,json
fn=sys.argv[1]; ranges=[tuple(int(x,16) for x in r.split('-')) for r in sys.argv[2:]]
cnt=collections.Counter(); cyc=collections.Counter(); txt={}
prev=None
for line in open(fn):
    m=re.match(r'C(\d+) ([0-9A-F]{4}): (.*)',line)
    if not m: continue
    c=int(m.group(1)); pc=int(m.group(2),16)
    if prev:
        pc0,c0=prev
        if any(a<=pc0<=b for a,b in ranges): cnt[pc0]+=1; cyc[pc0]+=c-c0
    txt[pc]=m.group(3).strip(); prev=(pc,c)
n=300
for a,b in ranges:
    print(f"--- {a:04X}-{b:04X}")
    for pc in sorted(p for p in cnt if a<=p<=b):
        print(f"  {pc:04X} {txt[pc]:28s} n/fr {cnt[pc]/n:7.1f}  T {cyc[pc]/max(cnt[pc],1):5.1f}  cyc/fr {cyc[pc]/n:7.0f}")
