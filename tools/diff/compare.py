#!/usr/bin/env python3
"""Compare arcade work RAM, handler by handler: MAME reference vs ColecoVision.

usage: compare.py REF.ram CV.ram [--show N]
Both files hold one 8192-byte record per vblank handler, taken at the same
sync point: arcade work RAM $E000-$EFFF, then video RAM $8000-$8FFF. Prints the first handler where
they differ (outside the masked ranges) and the differing bytes.
"""
import sys

# Arcade addresses the port uses for its own purposes, or that legitimately
# differ: I/O cells, the sprite RAM copy, and the stack (its contents depend on
# where the vblank interrupted the background code, which is timing).
MASK = [(0xE3B0, 0xE3BA, "I/O cells"),
        (0xE950, 0xEA50, "sprite RAM copy"),
        (0xEA50, 0xEB80, "stack (the arcade never touches $EA50-$EB4B; our NMI frames sit below its deepest use)")]


def masked(a):
    return any(lo <= a < hi for lo, hi, _ in MASK)


def addr(i):
    """Arcade address of byte i of a record."""
    return 0xE000 + i if i < 4096 else 0x8000 + i - 4096


def relocated_high(r, c):
    """Same pointer, relocated: the high byte moved by the port's offset."""
    if 0xE0 <= r <= 0xEF:
        return c == r - 0x80          # work RAM  $E000 -> $6000
    if 0x80 <= r <= 0x8F:
        return c == r - 0x10          # video RAM $8000 -> $7000
    if 0x60 <= r <= 0x7F:
        return c == r + 0x60          # sound data / scenes $6000 -> $C000
    return False


def main():
    ref = open(sys.argv[1], "rb").read()
    cv = open(sys.argv[2], "rb").read()
    show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 3
    REC = 8192
    n = min(len(ref), len(cv)) // REC
    print(f"{len(ref)//REC} reference handlers, {len(cv)//REC} ColecoVision handlers, comparing {n}")
    first = None
    shown = 0
    for h in range(n):
        r = ref[h * REC:(h + 1) * REC]
        c = cv[h * REC:(h + 1) * REC]
        if r == c:
            continue
        diffs = [i for i in range(REC) if r[i] != c[i] and not masked(addr(i))
                 and not relocated_high(r[i], c[i])]
        if not diffs:
            continue
        if first is None:
            first = h
        if shown < show:
            print(f"handler {h}: {len(diffs)} bytes differ")
            for i in diffs[:24]:
                print(f"   ${addr(i):04X}  arcade {r[i]:02X}  cv {c[i]:02X}")
            shown += 1
    if first is None:
        print(f"IDENTICAL for all {n} handlers (masks: {', '.join(m[2] for m in MASK)})")
    else:
        print(f"first divergence at handler {first}")


if __name__ == "__main__":
    main()
