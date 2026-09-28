import sys, re, json, collections
fn=sys.argv[1]
labels={int(k,16):v for k,v in json.load(open('labels.json')).items()}
EXC=collections.Counter(); INC=collections.Counter(); CALLS=collections.Counter()
LOOP=collections.Counter()   # exclusive cycles per instruction address
ninst=0; nisr=0; unmatched=0; isrcyc=0; isrlist=[]
stack=None
prev=None  # (cyc, pc, mnem)
def handle(pc, mn, cyc, npc):
    global stack, unmatched, isrcyc, nisr
    if stack is None: return
    top=stack[-1][0]
    EXC[top]+=cyc; LOOP[pc]+=cyc; isrcyc_add(cyc)
    for f in {fr[0] for fr in stack}: INC[f]+=cyc
    op=mn.split()[0]
    if op in('call','rst'):
        ln=3 if op=='call' else 1
        if npc!=pc+ln:
            stack.append((npc,pc+ln)); CALLS[npc]+=1
    elif pc==0x0103:  # actor dispatch: push $0104 ; jp (hl)
        stack.append((npc,0x0104)); CALLS[npc]+=1
    elif op.startswith('ret') and npc!=pc+1 and not (op=='retn' or op=='reti' and False):
        for k in range(len(stack)-1,0,-1):
            if stack[k][1]==npc: del stack[k:]; break
        else: unmatched+=1
cur=[0]
def isrcyc_add(c): cur[0]+=c
for line in open(fn):
    if not line.startswith('C'): continue
    m=re.match(r'C(\d+) ([0-9A-F]{4}): (.*)',line)
    if not m: continue
    cyc=int(m.group(1)); pc=int(m.group(2),16); mn=m.group(3).strip()
    if prev:
        pcyc,ppc,pmn=prev
        if ppc==0x0038 and stack is None:
            stack=[(0x0038,None)]; CALLS[0x0038]+=1; cur[0]=0
        handle(ppc,pmn,cyc-pcyc,pc)
        if stack is not None and (ppc==0x0137 or pc in (0x0138,0x0141,0x014D)):
            isrlist.append(cur[0]); stack=None
    prev=(cyc,pc,mn)
n=len(isrlist); tot=sum(isrlist)
isrlist.sort()
print(f"ISRs {n}  mean {tot/n:.0f}  median {isrlist[n//2]}  unmatched-rets {unmatched}")
def nm(a): return labels.get(a,'')
json.dump(dict(EXC={hex(k):v for k,v in EXC.items()},INC={hex(k):v for k,v in INC.items()},CALLS={hex(k):v for k,v in CALLS.items()},LOOP={hex(k):v for k,v in LOOP.items()},n=n,tot=tot),open(fn+'.json','w'))
for title,C in (('INCLUSIVE',INC),('EXCLUSIVE',EXC)):
    print(title)
    for a,v in C.most_common(22):
        c=CALLS[a]
        print(f"  {a:04X} {nm(a):24s} {v/n:8.0f}/fr {100*v/tot:5.1f}%  calls/fr {c/n:6.2f}  cyc/call {v/max(c,1):8.0f}")
