#!/usr/bin/env python3
"""Code map of the arcade main ROM by recursive descent.

Seeds: the Ghidra function entry points (tools/data/ghidra_functions.txt) plus
any extra entries (tools/data/extra_entries.txt, e.g. jump-table targets found
by MAME execution coverage). Every reachable instruction is decoded with
z80dis; indirect jumps end a path. Writes build/codemap.json:
  {"insns": [[addr, size, text, flow, target, fields], ...],
   "ranges": [[start, end], ...]}   (merged code byte ranges)
and prints a summary.
"""
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from z80dis import decode, JUMP, RET, INDIRECT  # noqa: E402

DIS = Path(os.environ.get("DO_DISASM", Path.home() / "work/do_disassemble"))
ROM = (DIS / "mrdo_main.bin").read_bytes()
OUT = HERE.parent / "build" / "codemap.json"


def seeds():
    out = []
    for name in ("ghidra_functions.txt", "extra_entries.txt"):
        p = HERE / "data" / name
        if not p.exists():
            continue
        for line in p.read_text().splitlines():
            line = line.split("#")[0].strip()
            if line:
                out.append(int(line.split()[0], 16))
    return out


def build():
    mem = ROM + bytes(4)
    insns, owner = {}, {}
    work = list(seeds())
    conflicts = []
    while work:
        a = work.pop()
        while 0 <= a < 0x8000 and a not in insns:
            if a in owner:                      # lands inside another insn
                conflicts.append((a, owner[a]))
                break
            i = decode(mem, a)
            insns[a] = i
            for k in range(a, a + i.size):
                owner[k] = a
            if i.target is not None and i.target < 0x8000:
                work.append(i.target)
            if i.flow in (JUMP, RET, INDIRECT):
                break
            a += i.size
    return insns, conflicts


def ranges(insns):
    out = []
    for a in sorted(insns):
        e = a + insns[a].size
        if out and out[-1][1] == a:
            out[-1][1] = e
        else:
            out.append([a, e])
    return out


def main():
    insns, conflicts = build()
    rs = ranges(insns)
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps({
        "insns": [[i.addr, i.size, i.text, i.flow, i.target, i.fields]
                  for _, i in sorted(insns.items())],
        "ranges": rs}))
    code_bytes = sum(e - s for s, e in rs)
    print(f"{len(insns)} instructions, {code_bytes} code bytes in {len(rs)} ranges")
    for lo, hi in ((0x0000, 0x6000), (0x6000, 0x7000), (0x7000, 0x8000)):
        n = sum(min(e, hi) - max(s, lo) for s, e in rs if s < hi and e > lo)
        print(f"  ${lo:04x}-${hi-1:04x}: {n} code bytes")
    if conflicts:
        print(f"{len(conflicts)} overlapping decodes (data decoded as code?):")
        for a, o in conflicts[:10]:
            print(f"  ${a:04x} inside insn at ${o:04x}")


if __name__ == "__main__":
    main()
