"""Complete Z80 instruction decoder for the arcade-image patcher.

decode(mem, addr) -> Insn with the instruction length, a readable text form,
control-flow info, and the byte offsets of any immediate/address operands so a
patcher can rewrite them in place without changing instruction lengths.

Includes undocumented IXH/IXL/IYH/IYL forms and DDCB/FDCB register copies,
since 1982 code occasionally relies on them.
"""
from dataclasses import dataclass, field

R8 = ["b", "c", "d", "e", "h", "l", "(hl)", "a"]
R16 = ["bc", "de", "hl", "sp"]
R16P = ["bc", "de", "hl", "af"]
CC = ["nz", "z", "nc", "c", "po", "pe", "p", "m"]
ALU = ["add a,", "adc a,", "sub ", "sbc a,", "and ", "xor ", "or ", "cp "]
ROT = ["rlc", "rrc", "rl", "rr", "sla", "sra", "sll", "srl"]

# flow kinds
SEQ, JUMP, BRANCH, CALL, RET, RETCC, INDIRECT, HALT = range(8)


@dataclass
class Insn:
    addr: int
    size: int
    text: str
    flow: int = SEQ
    target: int | None = None
    # operand fields: (offset_in_insn, width, kind) with kind in
    #   "mem"  - (nn) memory operand, always an address
    #   "imm"  - 16-bit immediate load (address or plain number)
    #   "tgt"  - jp/call target
    #   "imm8" - 8-bit immediate
    fields: list = field(default_factory=list)

    def operand(self, mem, off, width):
        a = self.addr + off
        return mem[a] if width == 1 else mem[a] | (mem[a + 1] << 8)


def _s8(v):
    return v - 256 if v > 127 else v


def decode(mem, addr):
    b = mem[addr]
    if b in (0xDD, 0xFD):
        return _decode_xy(mem, addr, "ix" if b == 0xDD else "iy")
    if b == 0xCB:
        return _decode_cb(mem, addr)
    if b == 0xED:
        return _decode_ed(mem, addr)
    return _decode_main(mem, addr, b, 0, "hl", None)


def _decode_main(mem, addr, b, pfx, hl, disp):
    """Unprefixed opcode b at addr+pfx. hl = 'hl'/'ix'/'iy'. With an index
    prefix, (hl) operands take a displacement byte right after the opcode."""
    o = addr + pfx                      # opcode position
    x, y, z = b >> 6, (b >> 3) & 7, b & 7
    p, q = y >> 1, y & 1
    xy = hl != "hl"

    def r8(i, allow_half=True):
        if i == 6:
            return f"({hl}{_s8(mem[o + 1]):+d})" if xy else "(hl)"
        if xy and allow_half and i in (4, 5):
            return hl + ("h" if i == 4 else "l")
        return R8[i]

    def rp(i):
        return hl if i == 2 else R16[i]

    def rp2(i):
        return hl if i == 2 else R16P[i]

    uses_mem = False
    n_off = 1                           # offset of an 8-bit immediate after opcode
    if xy:
        # which forms read (hl) and therefore carry a displacement
        if (x == 1 and (y == 6 or z == 6) and b != 0x76) or (x == 2 and z == 6) \
                or (x == 0 and y == 6 and z in (4, 5, 6)):
            uses_mem = True
            n_off = 2
    base = pfx + (1 if not uses_mem else 2)   # bytes up to and including disp

    def ins(size_after_base, text, **kw):
        return Insn(addr, base + size_after_base, text, **kw)

    if x == 0:
        if z == 0:
            if y == 0: return ins(0, "nop")
            if y == 1: return ins(0, "ex af,af'")
            t = (o + 2 + _s8(mem[o + 1])) & 0xFFFF
            if y == 2: return ins(1, f"djnz ${t:04x}", flow=BRANCH, target=t)
            if y == 3: return ins(1, f"jr ${t:04x}", flow=JUMP, target=t)
            return ins(1, f"jr {CC[y-4]},${t:04x}", flow=BRANCH, target=t)
        if z == 1:
            if q == 0:
                v = mem[o + 1] | (mem[o + 2] << 8)
                return ins(2, f"ld {rp(p)},${v:04x}", fields=[(pfx + 1, 2, "imm")])
            return ins(0, f"add {hl},{rp(p)}")
        if z == 2:
            if y < 4:
                return ins(0, ["ld (bc),a", "ld a,(bc)", "ld (de),a", "ld a,(de)"][y])
            v = mem[o + 1] | (mem[o + 2] << 8)
            f = [(pfx + 1, 2, "mem")]
            if y == 4: return ins(2, f"ld (${v:04x}),{hl}", fields=f)
            if y == 5: return ins(2, f"ld {hl},(${v:04x})", fields=f)
            if y == 6: return ins(2, f"ld (${v:04x}),a", fields=f)
            return ins(2, f"ld a,(${v:04x})", fields=f)
        if z == 3: return ins(0, f"{'inc' if q == 0 else 'dec'} {rp(p)}")
        if z == 4: return ins(0, f"inc {r8(y)}")
        if z == 5: return ins(0, f"dec {r8(y)}")
        if z == 6:
            return ins(1, f"ld {r8(y)},${mem[o + n_off]:02x}", fields=[(pfx + n_off, 1, "imm8")])
        return ins(0, ["rlca", "rrca", "rla", "rra", "daa", "cpl", "scf", "ccf"][y])
    if x == 1:
        if b == 0x76: return ins(0, "halt", flow=HALT)
        # ld r,(ix+d) / ld (ix+d),r keep plain h/l on the other side
        if xy and (y == 6 or z == 6):
            return ins(0, f"ld {r8(y, False)},{r8(z, False)}")
        return ins(0, f"ld {r8(y)},{r8(z)}")
    if x == 2:
        return ins(0, f"{ALU[y]}{r8(z)}")
    # x == 3
    if z == 0: return ins(0, f"ret {CC[y]}", flow=RETCC)
    if z == 1:
        if q == 0: return ins(0, f"pop {rp2(p)}")
        if p == 0: return ins(0, "ret", flow=RET)
        if p == 1: return ins(0, "exx")
        if p == 2: return ins(0, f"jp ({hl})", flow=INDIRECT)
        return ins(0, f"ld sp,{hl}")
    if z == 2:
        t = mem[o + 1] | (mem[o + 2] << 8)
        return ins(2, f"jp {CC[y]},${t:04x}", flow=BRANCH, target=t, fields=[(pfx + 1, 2, "tgt")])
    if z == 3:
        if y == 0:
            t = mem[o + 1] | (mem[o + 2] << 8)
            return ins(2, f"jp ${t:04x}", flow=JUMP, target=t, fields=[(pfx + 1, 2, "tgt")])
        if y == 2: return ins(1, f"out (${mem[o + 1]:02x}),a", fields=[(pfx + 1, 1, "port")])
        if y == 3: return ins(1, f"in a,(${mem[o + 1]:02x})", fields=[(pfx + 1, 1, "port")])
        if y == 4: return ins(0, f"ex (sp),{hl}")
        if y == 5: return ins(0, "ex de,hl")
        if y == 6: return ins(0, "di")
        if y == 7: return ins(0, "ei")
        raise ValueError(f"CB/prefix misroute @ {addr:04x}")
    if z == 4:
        t = mem[o + 1] | (mem[o + 2] << 8)
        return ins(2, f"call {CC[y]},${t:04x}", flow=CALL, target=t, fields=[(pfx + 1, 2, "tgt")])
    if z == 5:
        if q == 0: return ins(0, f"push {rp2(p)}")
        if p == 0:
            t = mem[o + 1] | (mem[o + 2] << 8)
            return ins(2, f"call ${t:04x}", flow=CALL, target=t, fields=[(pfx + 1, 2, "tgt")])
        raise ValueError(f"prefix byte as opcode @ {addr:04x}")
    if z == 6:
        return ins(1, f"{ALU[y]}${mem[o + 1]:02x}", fields=[(pfx + 1, 1, "imm8")])
    return ins(0, f"rst ${y * 8:02x}", flow=CALL, target=y * 8)


def _decode_cb(mem, addr):
    b = mem[addr + 1]
    x, y, z = b >> 6, (b >> 3) & 7, b & 7
    if x == 0: return Insn(addr, 2, f"{ROT[y]} {R8[z]}")
    return Insn(addr, 2, f"{['', 'bit', 'res', 'set'][x]} {y},{R8[z]}")


def _decode_xy(mem, addr, xy):
    b = mem[addr + 1]
    if b == 0xCB:
        d = _s8(mem[addr + 2])
        op = mem[addr + 3]
        x, y, z = op >> 6, (op >> 3) & 7, op & 7
        m = f"({xy}{d:+d})"
        base = f"{ROT[y]} {m}" if x == 0 else f"{['', 'bit', 'res', 'set'][x]} {y},{m}"
        if z != 6 and x != 1:
            base += f",{R8[z]}"            # undocumented register copy
        return Insn(addr, 4, base)
    if b in (0xDD, 0xFD, 0xED):
        return Insn(addr, 1, f"nop ; lone {xy} prefix")
    return _decode_main(mem, addr, b, 1, xy, None)


_ED = {0x44: "neg", 0x4D: "reti", 0x45: "retn", 0x46: "im 0", 0x56: "im 1",
       0x5E: "im 2", 0x47: "ld i,a", 0x4F: "ld r,a", 0x57: "ld a,i",
       0x5F: "ld a,r", 0x67: "rrd", 0x6F: "rld",
       0xA0: "ldi", 0xA1: "cpi", 0xA2: "ini", 0xA3: "outi",
       0xA8: "ldd", 0xA9: "cpd", 0xAA: "ind", 0xAB: "outd",
       0xB0: "ldir", 0xB1: "cpir", 0xB2: "inir", 0xB3: "otir",
       0xB8: "lddr", 0xB9: "cpdr", 0xBA: "indr", 0xBB: "otdr"}


def _decode_ed(mem, addr):
    b = mem[addr + 1]
    if b in _ED:
        flow = RET if b in (0x4D, 0x45) else SEQ
        return Insn(addr, 2, _ED[b], flow=flow)
    x, y, z = b >> 6, (b >> 3) & 7, b & 7
    p, q = y >> 1, y & 1
    if x == 1:
        if z == 0: return Insn(addr, 2, f"in {R8[y] if y != 6 else 'f'},(c)")
        if z == 1: return Insn(addr, 2, f"out (c),{R8[y] if y != 6 else '0'}")
        if z == 2: return Insn(addr, 2, f"{'sbc' if q == 0 else 'adc'} hl,{R16[p]}")
        if z == 3:
            v = mem[addr + 2] | (mem[addr + 3] << 8)
            t = f"ld (${v:04x}),{R16[p]}" if q == 0 else f"ld {R16[p]},(${v:04x})"
            return Insn(addr, 4, t, fields=[(2, 2, "mem")])
    return Insn(addr, 2, f"db $ed,${b:02x} ; undefined ED")
