; =============================================================================
; logo.asm - the CV romhack's animated title logo (title and instruction)
; =============================================================================
; The title and instruction screens show the romhack's "Mr. Do!" logo in the
; arcade logo's place (screen rows LOGO_R0-, columns LOGO_C0-, 8 x 20
; tiles): their captures leave the arcade logo's cells out, and their tile
; sets carry the logo's tiles at codes LOGO_BASE.. (tools/gen_screens.py,
; index byte 14 = 1). Its colour bars: in the romhack a Graphics I colour
; table frame (a colour per group of 8 codes) every 4 vblanks, frames 0-5
; once, then 6-11 looping. Here each logo tile's 8 colour bytes are
; rewritten when its colour changes, 29 tiles a vblank.
; =============================================================================
LOGO_R0         equ 1           ; = tools/gen_screens.py LOGO_AT
LOGO_C0         equ 2
LOGO_W          equ 20
LOGO_H          equ 8
LOGO_NAMES      equ logo_data
LOGO_FRAMES     equ logo_data + LOGO_W * LOGO_H     ; 12 x LOGO_N colours
LOGO_STEP       equ 29          ; tiles checked per vblank (4 vblanks a frame)
        assert LOGO_STEP * 4 >= LOGO_N

logo_on         equ vgl_on + 17 ; the screen shows the logo
logo_fr         equ vgl_on + 18 ; frame shown (or being shown)
logo_old        equ vgl_on + 19 ; the frame before it
logo_i          equ vgl_on + 20 ; next tile to update ($FF: none)
logo_pn         equ vgl_on + 21 ; the frame's colour list (2)
logo_po         equ vgl_on + 23 ; the previous frame's (2)
        assert logo_po + 1 < $2F00

; A new screen (check_screens), A = its index byte 14.
logo_start:
        ld (logo_on), a
        xor a
        ld (logo_fr), a
        ld (logo_old), a
        ld a, $FF
        ld (logo_i), a
        ret

; D = screen row, E = column: carry and A = the logo's code if that cell is
; the logo's. Preserves BC, DE, HL.
logo_cell:
        ld a, (logo_on)
        or a
        ret z
        ld a, (mode)
        cp MODE_SCREEN
        jr nz, .no
        ld a, d
        sub LOGO_R0
        cp LOGO_H
        jr nc, .no
        push hl
        push de
        ld l, a                 ; row * 20
        ld h, 0
        add hl, hl
        add hl, hl
        ld d, h
        ld e, l
        add hl, hl
        add hl, hl
        add hl, de
        pop de
        ld a, e
        sub LOGO_C0
        cp LOGO_W
        jr nc, .nop
        add a, l
        ld l, a
        jr nc, .n
        inc h
.n:     push de
        ld de, LOGO_NAMES
        add hl, de
        pop de
        ld a, (hl)
        pop hl
        scf
        ret
.nop:   pop hl
.no:    or a
        ret

; Each vblank in screen mode (VDP access allowed): the colour bars.
logo_tick:
        ld a, (logo_on)
        or a
        ret z
        ld a, (up_pending)
        or a
        ret nz                  ; its tile set is not up yet
        ld a, (logo_i)
        cp $FF
        jr nz, .run
        ld a, (frame_cnt)       ; a new frame every 4 vblanks
        and 3
        ret nz
        ld a, (logo_fr)
        ld (logo_old), a
        inc a
        cp 12
        jr c, .f
        ld a, 6                 ; (6-11 loop)
.f:     ld (logo_fr), a
        xor a
        ld (logo_i), a
.run:   ld a, (logo_fr)         ; the two frames' colour lists
        call .base
        ld (logo_pn), hl
        ld a, (logo_old)
        call .base
        ld (logo_po), hl
        ld b, LOGO_STEP
.t:     push bc
        ld a, (logo_i)
        cp LOGO_N
        jr nc, .end
        ld e, a
        ld d, 0
        ld hl, (logo_pn)
        add hl, de
        ld c, (hl)              ; new colour
        ld hl, (logo_po)
        add hl, de
        ld a, (hl)
        cp c
        jr z, .same
        ld a, e                 ; its 8 colour bytes
        add a, LOGO_BASE
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
        add a, high VR_CT
        ld h, a
        call vdp_set_write
        ld b, 8
        ld a, c
.w:     out (VDP_DATA), a       ; (spaced: 29 T with the djnz)
        nop
        nop
        djnz .w
.same:  ld a, (logo_i)
        inc a
        ld (logo_i), a
        pop bc
        djnz .t
        ret
.end:   ld a, $FF
        ld (logo_i), a
        pop bc
        ret
; A = frame -> HL = its colour list.
.base:  ld hl, LOGO_FRAMES
        ld de, LOGO_N
        or a
        ret z
.b:     add hl, de
        dec a
        jr nz, .b
        ret

logo_data:
        incbin "build/screens/logo.bin"
