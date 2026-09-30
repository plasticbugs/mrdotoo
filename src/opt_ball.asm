; =============================================================================
; opt_ball.asm - the power ball's fragment groups (draw_ball_segment $2CEB)
; =============================================================================
; While the ball bursts or re-forms, the arcade draws 5 groups of 4 mirrored
; fragments a frame: each fragment's position comes from 8 indexed loads,
; then the clip at $2E20 and queue_sprite_xy ($029D): ~20k T a frame, a third
; of it. Same work here with less overhead: the group's step is the
; original's (same instructions), fragments 0-2 are clipped and queued
; natively (the queue entry, its count and $E001 bit 7 exactly as $029D
; writes them; their registers are dead in the original: each fragment's
; are recomputed), fragment 3 goes through the original $2E20, so the
; routine returns with the original's registers and flags. (patch_arcade.py
; jumps here from $2CEB; `make validate` compares the queue in work RAM.)
; =============================================================================
QUEUE_N         equ $6311       ; arcade $E311: sprite queue count, entries after
opt_bseg:
        bit 5, (iy+0)
        jr nz, .b
        ld a, (iy+1)            ; $2CF1: moving out
        cp $30
        jr nc, .z
        ld a, (iy+3)
        cp $36
        jr c, .a
.z:     ld (iy+0), $00          ; $2CFF
        ret
.b:     bit 7, (iy+1)           ; $2D39: coming back
        jr nz, .z
        bit 7, (iy+3)
        jr nz, .z
        call $2E39
        ld a, (bc)
        and $F0
        rrca
        rrca
        rrca
        ld hl, $2E80
        call $2CC0
        ld h, (iy+1)
        ld l, (iy+2)
        and a
        sbc hl, de
        ld (iy+1), h
        ld (iy+2), l
        ld a, (bc)
        and $0F
        add a, a
        ld hl, $2E80
        call $2CC0
        ld h, (iy+3)
        ld l, (iy+4)
        and a
        sbc hl, de
        ld (iy+3), h
        ld (iy+4), l
        jr .m
.a:     call $2E39              ; $2D04
        ld a, (bc)
        and $F0
        rrca
        rrca
        rrca
        ld hl, $2E80
        call $2CC0
        ld h, (iy+1)
        ld l, (iy+2)
        add hl, de
        ld (iy+1), h
        ld (iy+2), l
        ld a, (bc)
        and $0F
        add a, a
        ld hl, $2E80
        call $2CC0
        ld h, (iy+3)
        ld l, (iy+4)
        add hl, de
        ld (iy+3), h
        ld (iy+4), l
; $2D7C: the four mirrored fragments. X = (ix+1,2), Y = (ix+3,4), the
; offsets dx = (iy+1,2), dy = (iy+3,4); code $70 ($79 when (ix+0) bit 2),
; attribute $0A / $1A / $2A / $3A. (px in DE, py in HL, as at $2E20.)
.m:     ld b, $70
        bit 2, (ix+0)
        jr z, .c
        ld b, $79
.c:     ld h, (ix+1)            ; 0: X + dx, Y + dy
        ld l, (ix+2)
        ld d, (iy+1)
        ld e, (iy+2)
        add hl, de
        push hl
        ld h, (ix+3)
        ld l, (ix+4)
        ld d, (iy+3)
        ld e, (iy+4)
        add hl, de
        pop de
        ld c, $0A
        call .q
        ld h, (ix+1)            ; 1: X + dy, Y - dx
        ld l, (ix+2)
        ld d, (iy+3)
        ld e, (iy+4)
        add hl, de
        push hl
        ld h, (ix+3)
        ld l, (ix+4)
        ld d, (iy+1)
        ld e, (iy+2)
        and a
        sbc hl, de
        pop de
        ld c, $1A
        call .q
        ld h, (ix+1)            ; 2: X - dy, Y + dx
        ld l, (ix+2)
        ld d, (iy+3)
        ld e, (iy+4)
        and a
        sbc hl, de
        push hl
        ld h, (ix+3)
        ld l, (ix+4)
        ld d, (iy+1)
        ld e, (iy+2)
        add hl, de
        pop de
        ld c, $2A
        call .q
        ld h, (ix+1)            ; 3: X - dx, Y - dy, the original tail
        ld l, (ix+2)
        ld d, (iy+1)
        ld e, (iy+2)
        and a
        sbc hl, de
        push hl
        ld h, (ix+3)
        ld l, (ix+4)
        ld d, (iy+3)
        ld e, (iy+4)
        and a
        sbc hl, de
        pop de
        ld c, $3A
        jp $2E20
; $2E20 + $029D natively: DE = px, HL = py, B = code, C = attribute.
.q:     ld a, d                 ; on the playfield?
        cp $06
        ret c
        cp $3A
        ret nc
        ld a, h
        cp $01
        ret c
        cp $3E
        ret nc
        ex de, hl               ; D, E = the high bytes of px * 4, py * 4
        add hl, hl
        add hl, hl
        ex de, hl
        add hl, hl
        add hl, hl
        ld e, h
        ld hl, QUEUE_N          ; $029D: the next queue slot (none when full)
        ld a, (hl)
        cp $40
        ret nc
        add a, a
        add a, a
        add a, low (QUEUE_N + 1)
        ld l, a
        jr nc, .s
        inc h
.s:     ld a, (ARC_WORK)        ; ($E000 bit 0: the screen flipped)
        rra
        jr c, .fl
        ld a, $08
        sub d
        ld d, a
        ld a, e
        sub $08
        ld e, a
.st:    ld (hl), b
        inc hl
        ld (hl), d
        inc hl
        ld (hl), c
        inc hl
        ld (hl), e
        ld hl, QUEUE_N
        inc (hl)
        ld hl, ARC_WORK + 1     ; $E001 bit 7: new sprites to copy
        set 7, (hl)
        ret
.fl:    ld a, c
        xor $30
        ld c, a
        ld a, d
        add a, $08
        ld d, a
        ld a, $F8
        sub e
        ld e, a
        jr .st
