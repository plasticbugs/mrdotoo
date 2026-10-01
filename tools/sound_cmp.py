#!/usr/bin/env python3
"""Compare two tools/sound_harness.sh logs: chip writes per engine tick and
the engine RAM crc per tick. Prints the first difference of each kind."""
import sys


def load(p):
    ticks, cur, crc = [], [], []
    for l in open(p):
        if l.startswith('v '):
            if crc:
                ticks.append(cur)
            cur = []
            crc.append(l.split()[2])
        else:
            cur.append(l.strip())
    ticks.append(cur)
    return ticks, crc


a, ca = load(sys.argv[1])
b, cb = load(sys.argv[2])
ok = True
for i, (x, y) in enumerate(zip(a, b)):
    if x != y:
        print(f"first write difference in tick {i}:\n  base {x}\n  new  {y}")
        ok = False
        break
for i, (x, y) in enumerate(zip(ca, cb)):
    if x != y:
        print(f"first engine RAM difference at the start of tick {i}")
        ok = False
        break
if len(a) != len(b):
    print("tick counts differ", len(a), len(b)); ok = False
print("IDENTICAL" if ok else "DIFFERENT")
sys.exit(0 if ok else 1)
