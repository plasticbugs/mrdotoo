#!/usr/bin/env python3
"""Build the ColecoVision images of the arcade main ROM.

The arcade code runs at its ORIGINAL addresses: $0000-$5FFF is copied into SGM
RAM. Only references to things that move are rewritten, in place, so every
instruction keeps its length and timing:

  arcade            CV             what
  $0000-$5FFF   ->  $0000-$5FFF    code + tables (RAM, native)
  $6000-$7FFF   ->  $C000-$DFFF    sound data + scene code (MegaCart window, bank 0)
  $8000-$8FFF   ->  $7000-$7FFF    video RAM (bg attr/tile, fg attr/tile)
  $9000-$90FF   ->  $6950-$6A4F    sprite RAM copy (untouched work-RAM block)
  $9800-$9803   ->  IO+0..3        flip / 2x SN76489 / protection PAL
  $A000-$A003   ->  IO+4..7        inputs + DIP switches
  $F000, $F800  ->  IO+8, IO+9     scroll registers
  $E000-$EFFF   ->  $6000-$6FFF    work RAM

Outputs build/arc_lo.bin ($0000-$5FFF) and build/arc_hi.bin ($6000-$7FFF,
loaded at $C000), plus build/arc_patches.txt listing every change.

Values of $F000 and up that are not exact scroll-register operands are
negative offsets (e.g. `ld de,$ffe0` = -32) and are never relocated. Relocating
a region by a constant keeps offsets inside that region valid.
"""
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from z80dis import decode  # noqa: E402

DIS = Path(os.environ.get("DO_DISASM", Path.home() / "work/do_disassemble"))
ROM = bytearray((DIS / "mrdo_main.bin").read_bytes())
ORIG = bytes(ROM)
SWEEP = HERE / "profile" / "sweep"

IO = 0x63B0             # I/O cells in the untouched work-RAM block $E3AA-$E411
SPRITE_RAM = 0x6950     # 256B inside the untouched block $E94B-$EB4B
IO_CELLS = {0x9800: 0, 0x9801: 1, 0x9802: 2, 0x9803: 3,
            0xA000: 4, 0xA001: 5, 0xA002: 6, 0xA003: 7,
            0xF000: 8, 0xF800: 9}

# 16-bit immediates that fall in a relocated range but are plain numbers.
KEEP_IMM = {
    0x2AB2: "ld bc,$6606: B/C loop constants, not a pointer",
    0x2353: "ld bc,$710a: sprite code/colour for queue_sprite_xy",
    0x2D7C: "ld bc,$700a: ball sprite code/colour",
    0x2D85: "ld bc,$790a: ball sprite code/colour",
    0x3050: "ld de,$7880: nest screen position",
    0x3091: "ld de,$7880: nest screen position",
    0x30A7: "ld de,$7880: nest screen position (collision box)",
    0x5E3C: "ld de,$8000: bit mask (ld a,h / and d), sound engine",
}
# Reviewed 2026-09-27: every other relocated BC/DE/HL/IX/IY immediate is used
# as a pointer by the following instructions (see git history for the list).


def reloc(v, kind):
    """CV address for arcade address v, or None if v is not relocated."""
    if 0xE000 <= v < 0xF000:
        return v - 0x8000
    if 0x8000 <= v < 0x9000:
        return v - 0x1000
    if 0x6000 <= v < 0x8000:
        return v + 0x6000
    if 0x9000 <= v < 0x9100:
        return SPRITE_RAM + (v - 0x9000)
    if v in IO_CELLS:
        return IO + IO_CELLS[v]
    if v >= 0xF000:
        if kind == "mem":
            raise ValueError(f"memory operand ${v:04x} in the scroll range")
        return None                    # negative offset
    return None


log = []
claimed = set()        # bytes rewritten by special patches: operand pass skips them


def put16(addr, new, why):
    old = ROM[addr] | (ROM[addr + 1] << 8)
    ROM[addr], ROM[addr + 1] = new & 0xFF, new >> 8
    log.append(f"{addr:04x}  ${old:04x} -> ${new:04x}  {why}")


def put_bytes(addr, data, why):
    claimed.update(range(addr, addr + len(data)))
    old = ROM[addr:addr + len(data)].hex()
    ROM[addr:addr + len(data)] = bytes(data)
    log.append(f"{addr:04x}  {old} -> {bytes(data).hex()}  {why}")


def patch_code(cm):
    review = []
    for a, size, text, flow, tgt, fields in cm["insns"]:
        if claimed.intersection(range(a, a + size)):
            continue                    # replaced wholesale by a special patch
        for off, w, kind in fields:
            if w != 2:
                continue
            p = a + off
            v = ORIG[p] | (ORIG[p + 1] << 8)
            if kind == "imm" and a in KEEP_IMM:
                continue
            if kind == "tgt":
                if 0x6000 <= v < 0x8000:
                    put16(p, v + 0x6000, f"{text}")
                elif v >= 0x8000:
                    raise ValueError(f"jump/call to ${v:04x} at ${a:04x}")
                continue
            n = reloc(v, kind)
            if n is not None:
                put16(p, n, text)
                if kind == "imm" and 0x6000 <= v < 0x8000 and a < 0x5A80:
                    review.append(f"  ${a:04x} {text}  (pointer into $6000-$7FFF?)")
    return review


def word_readers():
    """ROM addresses of words read by the given lo-byte reader PCs (sweep)."""
    return json.loads((SWEEP / "rom_data_reads.json").read_text())


def patch_tables(cm):
    """Pointer words inside ROM tables (verified consumers only)."""
    reads = word_readers()
    # reader PC -> what the word is (all are video or work-RAM pointers)
    readers = {"00E9": "actor table: actor struct pointer",
               "03D4": "block record: video destination",
               "0403": "column record: video destination",
               "0425": "cell record: video destination",
               "49B1": "EXTRA letter rect: video destination"}
    seen = set()
    for pc, why in readers.items():
        for a in reads.get(pc, []):
            v = ORIG[a] | (ORIG[a + 1] << 8)
            n = reloc(v, "imm")
            if n is None or a in seen:
                continue
            seen.add(a)
            put16(a, n, f"table word ({why})")
    # records passed to those routines by an immediate `ld hl,nn` + call
    record_entry = {0x03D4, 0x0403, 0x0425}
    ins = cm["insns"]
    static = set()
    for i, (a, size, text, flow, tgt, fields) in enumerate(ins):
        if tgt in record_entry and text.startswith("call"):
            for back in range(1, 5):
                pa, _, pt, *_ = ins[i - back]
                if pt.startswith("ld hl,$"):
                    rec = int(pt[7:11], 16)
                    if rec < 0x8000:
                        static.add(rec)
                    break
    missed = []
    for rec in sorted(static):
        if rec not in seen:
            v = ORIG[rec] | (ORIG[rec + 1] << 8)
            if reloc(v, "imm") is not None:
                seen.add(rec)
                put16(rec, reloc(v, "imm"), "table word (record found statically)")
                missed.append(rec)
    return missed


def patch_sound():
    """Descriptor table $6001: 38 x [header ptr, work ptr, priority]; headers
    [n, n x ($40, stream ptr)]; stream loop ops $80-$BF carry a pointer."""
    note_len = [2, 3, 3, 3, 2, 2, 7, 7]
    streams = set()
    for sid in range(38):
        d = 0x6001 + sid * 5
        hdr = ORIG[d] | (ORIG[d + 1] << 8)
        work = ORIG[d + 2] | (ORIG[d + 3] << 8)
        put16(d, reloc(hdr, "imm"), f"sound ${sid:02x} header ptr")
        put16(d + 2, reloc(work, "imm"), f"sound ${sid:02x} work ptr")
        n = ORIG[hdr]
        for v in range(n):
            sp = hdr + 1 + v * 3 + 1
            s = ORIG[sp] | (ORIG[sp + 1] << 8)
            put16(sp, reloc(s, "imm"), f"sound ${sid:02x} voice {v} stream ptr")
            streams.add(s)
    done = set()
    for s in sorted(streams):
        pos, mode = s, 0
        while pos not in done:
            done.add(pos)
            b = ORIG[pos]
            if b == 0xFF:
                break
            if b >= 0xC0:
                mode = b & 7
                pos += 1
            elif b >= 0x80:
                t = ORIG[pos + 1] | (ORIG[pos + 2] << 8)
                put16(pos + 1, reloc(t, "imm"), f"stream loop target")
                pos += 3
            else:
                pos += note_len[mode]


def special_patches():
    # Every `ei` becomes `rst $08`: the driver's hook there delivers a vblank
    # that arrived while interrupts were off (the arcade IRQ is level-held).
    for a in (0x00AB, 0x0136, 0x013B, 0x0144, 0x0150):
        assert ORIG[a] == 0xFB
        put_bytes(a, [0xCF], "ei -> rst $08 (pending-vblank hook)")
    # Arcade bug: `ld (hl),$3e` with HL = $E01A+n-$400 hits unmapped space.
    # Relocated, it would land on sound-engine code at $5C1A.
    assert ORIG[0x1761:0x1763] == b"\x36\x3e"
    put_bytes(0x1761, [0x00, 0x00], "stray arcade write to unmapped $DC1A: nop")
    # Protection: the PAL echoes table bytes; a real board always passes.
    # `ld a,($9803) / and $7e / cp (hl)` -> `ld a,(hl) / nop x4 / cp (hl)`.
    for a in (0x0494, 0x7729):
        assert ORIG[a] == 0x3A and ORIG[a + 3:a + 5] == b"\xe6\x7e"
        put_bytes(a, [0x7E, 0x00, 0x00, 0x00, 0x00], "protection read: always pass")


VALIDATE_PATCHES = [
    # Validation mode: the background pathfinder runs to completion with the
    # vblank held off, so the logic no longer depends on CPU speed and the
    # MAME reference (patched identically by tools/diff/mame_record.lua) and
    # the ColecoVision agree handler by handler. Interrupts come back on where
    # the pathfinder finishes, through hooks at $0010 / $0018 (see main.asm).
    (0x013B, [0x00], "validate: pathfinder start, interrupts stay off"),
    (0x0144, [0x00], "validate: path1 start, interrupts stay off"),
    (0x0150, [0x00], "validate: path2 start, interrupts stay off"),
    (0x014C, [0xDF], "validate: path1 done: ret -> rst $18 (ei / ret)"),
    (0x0154, [0xD7], "validate: path2 done: jr $ -> rst $10 (ei / idle)"),
]


def main():
    cm = json.loads((ROOT / "build" / "codemap.json").read_text())
    validate = "--validate" in sys.argv
    special_patches()
    if validate:
        for a, data, why in VALIDATE_PATCHES:
            put_bytes(a, data, why)
    review = patch_code(cm)
    missed = patch_tables(cm)
    patch_sound()
    out = ROOT / "build"
    if validate:
        (out / "arc_lo_validate.bin").write_bytes(bytes(ROM[0x0000:0x6000]))
        print("validation image: build/arc_lo_validate.bin")
        return
    (out / "arc_lo.bin").write_bytes(bytes(ROM[0x0000:0x6000]))
    (out / "arc_hi.bin").write_bytes(bytes(ROM[0x6000:0x8000]))
    (out / "arc_patches.txt").write_text("\n".join(log) + "\n")
    changed = sum(1 for a, b in zip(ROM, ORIG) if a != b)
    print(f"{len(log)} patches, {changed} bytes changed")
    if missed:
        print("table records found only statically:", " ".join(f"${r:04x}" for r in missed))
    if review:
        print("immediates into $6000-$7FFF from low code (check these are pointers):")
        print("\n".join(review))


if __name__ == "__main__":
    main()
