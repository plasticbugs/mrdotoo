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
    """ROM addresses of words read by the given lo-byte reader PCs (the
    tools/profile sweep, plus the cutscenes recorded with
    tools/capture/scene_record.lua DATAOUT=)."""
    return json.loads((SWEEP / "rom_data_reads.json").read_text())


def patch_tables(cm):
    """Pointer words inside ROM tables (verified consumers only)."""
    reads = word_readers()
    # reader PC -> what the word is (all are video or work-RAM pointers)
    readers = {"00E9": "actor table: actor struct pointer",
               "03D4": "block record: video destination",
               "0403": "column record: video destination",
               "0425": "cell record: video destination",
               "49B1": "EXTRA letter rect: video destination",
               # scene code: tables of column-record pointers (EXTRA and
               # diamond scenes; reads recorded by tools/capture/scene_record.lua)
               "73FC": "record pointer table",
               "78C3": "record pointer table"}
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


# Speed patches: hot loops rewritten in place (same address, same RAM effects
# every frame; `make validate` proves it). Rare slow paths call into the
# driver's fixed bank through a jump table at OPT_BASE (src/opt.asm): entry k
# is at OPT_BASE + 3k.
OPT_BASE = 0xBD00
OPT_SND_SLOT = OPT_BASE + 0
OPT_SPR_COPY = OPT_BASE + 3
# (the same skipper for trigger_apple_wobble ($80) and chomper_scan_apple
# ($80-$B7) measured slower: those states are common, so it rarely skips)
OPT_SND_W1 = OPT_BASE + 9
OPT_SND_W2 = OPT_BASE + 12
OPT_FILL_046C = OPT_BASE + 15
OPT_SCAN = [(0x420D, 0x41EC, 0x4211, OPT_BASE + 6, "alpha_advance: next object in state $98")]


def sound_patches():
    """Normal build: the arcade's sound chip writes go to src/sound.asm (the CV
    SN76489 + SGM AY). The validation build keeps the plain stores (rst $10
    is its pathfinder hook)."""
    for a in (0x5C3A, 0x5C3E, 0x5C45, 0x5C4C, 0x5C53):   # ld (bc),a, BC = $9801/2
        assert ORIG[a] == 0x02
        put_bytes(a, bytes([0xD7]), "sound chip store -> rst $10 (snd_rst_bc)")
    for a, entry, chip in ((0x5AE7, OPT_SND_W1, 1), (0x5AEE, OPT_SND_W2, 2)):
        assert ORIG[a:a + 3] == bytes([0x32, 0x00 + chip, 0x98])
        put_bytes(a, bytes([0xCD, entry & 0xFF, entry >> 8]), f"ld ($980{chip}),a -> call snd_w{chip}")
    # The sound tick runs from our NMI every vblank (src/sound.asm
    # snd_nmi_tick), not from the handler: music keeps time when the logic lags.
    assert ORIG[0x00D2:0x00D5] == bytes([0xCD, 0x90, 0x5A])
    put_bytes(0x00D2, bytes(3), "call $5A90 (sound tick) -> nops: the NMI ticks")


def speed_patches():
    if os.environ.get("NOSPEED"):       # A/B testing: the plain arcade loops
        return
    # Sound tick $5A90: 38 request-flag bytes at $EC00, each tested with three
    # `bit n,(ix+0)` / `call nz` pairs (~113 T a slot, nearly all idle). Now:
    # one `ld a,(hl) / and 7` per slot (~43 T); a slot with a request calls
    # the original three tests (opt_snd_slot). IX ends at $EC26 as before.
    assert ORIG[0x5A90:0x5AAF] == bytes.fromhex(
        "dd2100ec0626ddcb0056c4f65addcb0046c41d5bddcb004ec4f65add2310e7")
    code = bytes([0x21, 0x00, 0x6C,                 # ld hl,$EC00 (CV $6C00)
                  0x06, 0x26,                       # ld b,$26
                  0x7E,                             # L: ld a,(hl)
                  0xE6, 0x07,                       # and 7
                  0xC4, OPT_SND_SLOT & 0xFF, OPT_SND_SLOT >> 8,   # call nz,opt_snd_slot
                  0x23,                             # inc hl
                  0x10, 0xF7,                       # djnz L
                  0xDD, 0x21, 0x26, 0x6C,           # ld ix,$EC26
                  0x18])                            # jr $5AAF
    code += bytes([0x5AAF - (0x5A90 + len(code) + 1)])
    code += bytes([0x00] * (0x5AAF - 0x5A90 - len(code)))
    put_bytes(0x5A90, code, "sound tick: fast idle-slot scan (opt_snd_slot)")
    # $028B: after copying the queue to sprite RAM, the arcade zeroes Y in
    # every unused entry (~31 T each). No CPU code reads sprite RAM (MAME read
    # tap over 8000 frames of play), and the renderer stops at the first Y = 0,
    # so one terminator does. Registers and flags end as the loop left them:
    # HL = $9101 (CV $6A51), DE = 4, B = 0, A = 0, flags of `xor a` (the last
    # `add hl,de` to $9101 sets neither H nor C).
    assert ORIG[0x028B:0x0297] == bytes.fromhex("47eb23110400af771910fcc9")
    put_bytes(0x028B, bytes([0xEB, 0x23, 0xAF, 0x77,           # ex de,hl / inc hl / xor a / ld (hl),a
                             0x21, 0x51, 0x6A,                 # ld hl,$9101 (CV $6A51)
                             0x11, 0x04, 0x00,                 # ld de,4
                             0x47, 0xC9]),                     # ld b,a / ret
              "sprite RAM: one Y=0 terminator instead of zeroing every unused entry")
    # Object-table scans (12 objects, stride 7, IY-indexed, ~66 T an object):
    # the loop tail `add iy,de / djnz body` jumps to a skipper that runs the
    # same two instructions (the exit keeps its flags), then passes over
    # objects that cannot match via HL and re-enters the body at the next
    # candidate. The last object always goes through the original body.
    for tail, body, exit_, entry, why in OPT_SCAN:
        assert ORIG[tail:tail + 2] == b"\xfd\x19" and ORIG[tail + 2] == 0x10
        assert tail + 4 + (ORIG[tail + 3] - 256) == body and ORIG[exit_:exit_ + 2] == b"\xfd\xe1"
        put_bytes(tail, bytes([0xC3, entry & 0xFF, entry >> 8, 0x00]), f"{why} (opt skipper)")
    # The handler's sprite RAM copy ($026D, called when $E001 bit 7 is set):
    # through opt_spr_copy, which also tells the renderer there is new
    # sprite data (vblanks without any skip the sprite pass).
    assert ORIG[0x00C8:0x00CB] == bytes([0xC4, 0x6D, 0x02])
    put_bytes(0x00C8, bytes([0xC4, OPT_SPR_COPY & 0xFF, OPT_SPR_COPY >> 8]),
              "sprite RAM copy via opt_spr_copy (new-sprites flag)")
    # Video fill $046C/$046D (attr A + tile $29 over C rows of B cells): native
    # loop in src/opt.asm (fill_046c) that stores big fills directly and asks
    # for one full redraw instead of queueing ~3600 hooked stores (the coin-up
    # clear stalled the logic for 33 frames). Same pushes, exit registers, flags.
    # Entered at $046D (after $046C's `xor a`, or directly by $7076).
    assert ORIG[0x046C:0x0470] == bytes([0xAF, 0xC5, 0xD5, 0x21])
    put_bytes(0x046D, bytes([0xC3, OPT_FILL_046C & 0xFF, OPT_FILL_046C >> 8]),
              "video fill $046D -> fill_046c (direct stores + full redraw)")


# Video RAM write sites (tools/profile/sweep: every PC that wrote $8000-$8FFF).
# Each store becomes a same-size hook into the driver, which does the store,
# queues the cell for the renderer, and drops or redirects stores that miss
# video RAM (ROM addresses, the scroll-register range). Hook vectors (main.asm):
#   rst $00 ld (hl),b   rst $20 ld (hl),a   rst $28 ld (de),a
#   rst $30 ld (hl),n   rst $38 ld (hl),c   call VSTUB+16k  ld (nn),a
VSTUB_BASE = 0xBE00
VIDEO_WRITES = {
    0x03A5: "ld (hl),c", 0x03BB: "ld (de),a", 0x03ED: "ld (hl),a", 0x03EF: "ld (de),a",
    0x0410: "ld (de),a", 0x0419: "ld (hl),a", 0x043B: "ld (hl),c", 0x0440: "ld (hl),a",
    0x0448: "ld (de),a", 0x044A: "ld (hl),a", 0x045E: "ld (hl),a", 0x0473: "ld (de),a",
    0x0474: "ld (hl),$29", 0x048D: "ld (de),a", 0x0492: "ld (de),a",
    0x0517: "ld ($8f22),a", 0x051D: "ld ($8f42),a", 0x0F47: "ld ($8f24),a",
    0x0F4D: "ld ($8b24),a", 0x1020: "ld (hl),a", 0x1027: "ld (hl),a", 0x1510: "ld (hl),a",
    0x152F: "ld (hl),a", 0x1675: "ld (de),a", 0x167B: "ld (hl),$2d", 0x175B: "ld (de),a",
    0x17E4: "ld (hl),$29", 0x1855: "ld (hl),$22", 0x185E: "ld (hl),a", 0x1B9E: "ld (hl),a",
    0x1BB0: "ld (hl),a", 0x1BBF: "ld (hl),a", 0x1D67: "ld (hl),b",
    0x3102: "ld ($85cf),a", 0x3107: "ld ($85ef),a", 0x310C: "ld ($81cf),a",
    0x310F: "ld ($81ef),a", 0x7C9E: "ld (de),a", 0x7CA4: "ld (hl),$2d",
    # Direct stores the play sweep never executed (found statically, every
    # `ld ($8xxx),a` in the code map): the credit digit in the attract and
    # diamond scenes ($7446, $74D8: its coin dropped but the screen kept "0"),
    # a column of foreground cells ($56E1-$57EF) and the corner cells ($5951-).
    0x56E1: "ld ($8d90),a", 0x56E6: "ld ($8db0),a", 0x56EB: "ld ($8dd0),a",
    0x570C: "ld ($8e50),a", 0x5714: "ld ($8e70),a", 0x571A: "ld ($8e10),a",
    0x5732: "ld ($8e30),a", 0x5737: "ld ($8e50),a", 0x5744: "ld ($8d90),a",
    0x5749: "ld ($8db0),a", 0x574E: "ld ($8dd0),a", 0x5753: "ld ($8e30),a",
    0x5756: "ld ($8e50),a", 0x57B6: "ld ($8d90),a", 0x57BB: "ld ($8db0),a",
    0x57C0: "ld ($8dd0),a", 0x57CA: "ld ($8e30),a", 0x57CF: "ld ($8e50),a",
    0x57EF: "ld ($8e30),a", 0x5951: "ld ($8480),a", 0x5956: "ld ($849f),a",
    0x595B: "ld ($8760),a", 0x5960: "ld ($877f),a", 0x7446: "ld ($8e65),a",
    0x74D8: "ld ($8e65),a",
}
VSTUB_SIZE = 11
RST_OF = {"ld (hl),b": 0xC7, "ld (hl),a": 0xE7, "ld (de),a": 0xEF, "ld (hl),c": 0xFF}


def video_hooks(cm):
    """Returns the ld (nn),a stub table [(cv_address, arcade_site)]."""
    text = {a: t for a, s, t, *_ in cm["insns"]}
    stubs = []
    for a, form in sorted(VIDEO_WRITES.items()):
        assert text.get(a) == form, f"${a:04x}: expected {form}, found {text.get(a)}"
        if form in RST_OF:
            put_bytes(a, [RST_OF[form]], f"{form} -> video hook")
        elif form.startswith("ld (hl),$"):
            put_bytes(a, [0xF7], f"{form} -> rst $30 (value inline)")
            claimed.discard(a + 1)       # keep the inline value byte
        else:                           # ld (nn),a
            nn = ORIG[a + 1] | (ORIG[a + 2] << 8)
            stub = VSTUB_BASE + VSTUB_SIZE * len(stubs)
            stubs.append((reloc(nn, "mem"), a))
            put_bytes(a, [0xCD, stub & 0xFF, stub >> 8], f"{form} -> call video stub")
    return stubs


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


# The arcade checks two ROM ranges with a byte sum. Both contain bytes this
# script patches (the PAL checks at $0494 and $7729, video hooks), so each
# compare gets the sum of the patched bytes: the check passes exactly when the
# arcade's does (always). Failing the first one stops the level counters
# $E09F/$E0A0 from advancing at the end of a round.
CHECKSUMS = [  # (compare operand, expected, [(start, length), ...])
    (0x1A0E, 0x4F, [(0x0485, 0x1A), (0x0547, 0x08)]),   # $19FA
    (0x74C6, 0xDF, [(0x770B, 0x42)]),                   # $74BB
]


def fix_checksums():
    for operand, want, ranges in CHECKSUMS:
        assert ORIG[operand] == want
        assert sum(ORIG[a + i] for a, n in ranges for i in range(n)) & 0xFF == want
        got = sum(ROM[a + i] for a, n in ranges for i in range(n)) & 0xFF
        if got != want:
            put_bytes(operand, bytes([got]), f"checksum compare ${want:02x} -> ${got:02x} (patched bytes)")


def main():
    cm = json.loads((ROOT / "build" / "codemap.json").read_text())
    validate = "--validate" in sys.argv
    special_patches()
    speed_patches()
    if not validate:
        sound_patches()
    stubs = video_hooks(cm)
    if validate:
        for a, data, why in VALIDATE_PATCHES:
            put_bytes(a, data, why)
    review = patch_code(cm)
    missed = patch_tables(cm)
    patch_sound()
    fix_checksums()                     # last: sums the final bytes
    out = ROOT / "build"
    inc = [f"; generated by tools/patch_arcade.py: ld (nn),a video stubs, {VSTUB_SIZE} bytes each"]
    for cv, site in stubs:
        inc += [f"        assert $ == VSTUB_BASE + {VSTUB_SIZE * stubs.index((cv, site))}",
                f"        push af                 ; arcade ${site:04x}: ld (${cv:04x}),a",
                "        push hl",
                f"        ld hl, ${cv:04x}",
                "        call vstore",
                "        pop hl",
                "        pop af",
                "        ret"]
    (out / "vstubs.inc").write_text("\n".join(inc) + "\n")
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
