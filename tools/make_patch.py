#!/usr/bin/env python3
"""Make the release patch: build/release/mrdo_cv.bps turns MAME's mrdo set
into build/mrdo.rom; build/release/ also gets tools/mrdo2cv.py, which
applies it.

The patch is BPS (byuu's format). Its source is the romset files
mrdo2cv.SOURCE names, joined in that order. Every run of the ROM found in the
source (or earlier in the ROM itself) is encoded as a copy, so the arcade's
program comes from the user's set; only the rest is stored in the patch.
Afterwards mrdo2cv.py rebuilds the ROM from $DO_DISASM's files and the
result must be byte-identical.

usage: tools/make_patch.py [ROM]   (default build/mrdo.rom)
"""
import bisect
import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIS = Path(os.environ.get("DO_DISASM", Path.home() / "work/do_disassemble"))
OUT = ROOT / "build" / "release"
sys.path.insert(0, str(ROOT / "tools"))
import mrdo2cv  # noqa: E402

GRAM = 4        # shortest copy


def varint(n):
    out = bytearray()
    while True:
        x = n & 0x7F
        n >>= 7
        if n == 0:
            out.append(0x80 | x)
            return out
        out.append(x)
        n -= 1


def offset(n):
    return varint((abs(n) << 1) | (n < 0))


def common(a, ai, b, bi, limit):
    """Length of the common run of a[ai:] and b[bi:], at most limit."""
    n = 0
    for step in (1024, 64, 8):
        while n + step <= limit and a[ai + n:ai + n + step] == b[bi + n:bi + n + step]:
            n += step
    while n < limit and a[ai + n] == b[bi + n]:
        n += 1
    return n


def encode(src, tgt, meta):
    """BPS patch src -> tgt (greedy longest match), and byte counts per action."""
    out = bytearray(b"BPS1") + varint(len(src)) + varint(len(tgt)) + varint(len(meta)) + meta
    sidx = {}
    for p in range(len(src) - GRAM + 1):
        sidx.setdefault(src[p:p + GRAM], []).append(p)
    tidx = {}
    stats = {"source": 0, "rom": 0, "stored": 0}
    from_src = bytearray(len(src))      # which source bytes the ROM uses
    src_rel = tgt_rel = 0
    lit = None
    i, n = 0, len(tgt)

    def note(a, b):
        for p in range(a, min(b, n - GRAM + 1)):
            tidx.setdefault(tgt[p:p + GRAM], []).append(p)

    while i < n:
        best = (0, 0, 0)        # (length, -cost, kind/pos)
        gram = tgt[i:i + GRAM]
        if i < len(src):
            m = common(src, i, tgt, i, min(len(src), n) - i)
            if m >= GRAM:
                best = (m, -1, ("read", i))
        cands = sidx.get(gram, ())
        if cands:
            k = bisect.bisect_left(cands, src_rel)
            for p in cands[max(0, k - 16):k + 16]:
                m = common(src, p, tgt, i, min(len(src) - p, n - i))
                key = (m, -len(offset(p - src_rel)) - 1, ("src", p))
                if key[:2] > best[:2]:
                    best = key
        for p in tidx.get(gram, ())[-16:]:
            m = common(tgt, p, tgt, i, n - i)
            key = (m, -len(offset(p - tgt_rel)) - 1, ("tgt", p))
            if key[:2] > best[:2]:
                best = key
        m, _, how = best
        if m < GRAM:
            if lit is None:
                lit = i
            note(i, i + 1)
            i += 1
            continue
        if lit is not None:
            out += varint(((i - lit - 1) << 2) | 1) + tgt[lit:i]
            stats["stored"] += i - lit
            lit = None
        kind, p = how
        if kind == "read":
            out += varint((m - 1) << 2)
            stats["source"] += m
            from_src[p:p + m] = b"\1" * m
        elif kind == "src":
            out += varint(((m - 1) << 2) | 2) + offset(p - src_rel)
            src_rel = p + m
            stats["source"] += m
            from_src[p:p + m] = b"\1" * m
        else:
            out += varint(((m - 1) << 2) | 3) + offset(p - tgt_rel)
            tgt_rel = p + m
            stats["rom"] += m
        note(i, i + m)
        i += m
    if lit is not None:
        out += varint(((n - lit - 1) << 2) | 1) + tgt[lit:n]
        stats["stored"] += n - lit
    for data in (src, tgt):
        out += (mrdo2cv.crc32(data)).to_bytes(4, "little")
    out += mrdo2cv.crc32(out).to_bytes(4, "little")
    return bytes(out), stats, from_src


def main():
    rom = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "build" / "mrdo.rom").read_bytes()
    src = mrdo2cv.source_from(str(DIS))
    rev = subprocess.run(["git", "describe", "--always", "--dirty"], cwd=ROOT,
                         capture_output=True, text=True).stdout.strip()
    meta = ("Mr. Do! for ColecoVision + Super Game Module, build %s" % rev).encode()
    patch, stats, used = encode(src, rom, meta)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "mrdo_cv.bps").write_bytes(patch)
    shutil.copy(ROOT / "tools" / "mrdo2cv.py", OUT / "mrdo2cv.py")
    print("mrdo_cv.bps: %d bytes (%s)" % (len(patch), meta.decode()))
    print("ROM %d bytes: %d copied from the romset, %d repeats within the ROM, %d stored"
          % (len(rom), stats["source"], stats["rom"], stats["stored"]))
    at = 0
    for name, size, _, _ in mrdo2cv.SOURCE:
        print("  %-10s %5d of %5d bytes used" % (name, sum(used[at:at + size]), size))
        at += size
    # round trip: what a user gets from the files
    back, _ = mrdo2cv.bps_apply(patch, src)
    if back != rom:
        sys.exit("make_patch: the patch does not rebuild the ROM")
    print("round trip OK, SHA-1 %s" % hashlib.sha1(back).hexdigest())


if __name__ == "__main__":
    main()
