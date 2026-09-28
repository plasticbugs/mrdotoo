#!/usr/bin/env python3
"""Exclusive profile from tools/perf_sample.tcl samples: arcade PCs grouped
by the Ghidra function entries (tools/data/ghidra_functions.txt), driver PCs
($8000+, RAM stubs) by build/mrdo.sym labels.

usage: perf_report.py SAMPLES [N]"""
import bisect, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
funcs = []
for line in (ROOT / "tools/data/ghidra_functions.txt").read_text().splitlines():
    if line and line[0] != "#":
        f = line.split()
        funcs.append((int(f[0], 16), f[1] if len(f) > 1 else ""))
labels = json.loads((ROOT / "tools/profile/labels.json").read_text())
funcs.sort()
starts = [a for a, _ in funcs]
syms = []
for line in (ROOT / "build/mrdo.sym").read_text().splitlines():
    m = re.match(r"^([A-Za-z_][\w.]*): EQU 0x([0-9A-F]+)", line)
    if m and "." not in m.group(1):
        syms.append((int(m.group(2), 16), m.group(1)))
syms.sort()
sstarts = [a for a, _ in syms]

def owner(pc):
    if pc >= 0x8000:
        i = bisect.bisect_right(sstarts, pc) - 1
        return f"drv {syms[i][1]}" if i >= 0 else "drv ?"
    i = bisect.bisect_right(starts, pc) - 1
    a, n = funcs[i]
    lab = labels.get(f"{a:04X}", "")
    return f"${a:04X} {n} {lab}".strip()

tot = {}
n = 0
for line in Path(sys.argv[1]).read_text().splitlines():
    pc, c = line.split()
    c = int(c); n += c
    k = owner(int(pc, 16))
    tot[k] = tot.get(k, 0) + c
top = int(sys.argv[2]) if len(sys.argv) > 2 else 30
for k, c in sorted(tot.items(), key=lambda kv: -kv[1])[:top]:
    print(f"{100.0 * c / n:5.1f}%  {k}")
print(f"({n} samples)")
