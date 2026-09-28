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
clw_fr          equ vgl_on + 25 ; clown: diamond frame (0-2)
clw_step        equ vgl_on + 26 ;   upload step (6 = running)
clw_tcol        equ vgl_on + 27 ;   the token's colour
        assert clw_tcol < $2F00
CLW_TOKEN       equ $6D         ; the arcade's credit token (the coin that drops)
CLW_TPAT        equ 100         ; its pattern: after the romhack's 25 sprites

; The romhack clown and diamond over the diamond screen (index byte 14 = 2;
; tools/gen_screens.py romhack_clown): box screen rows CLW_R0-, columns
; CLW_C0- (13 x 8), its names per diamond frame, its sprites (10 for the
; clown, 5 sparkles per frame) in place of the sprite pass, a frame every 8
; vblanks.
CLW_R0          equ 4           ; = tools/gen_screens.py CLOWN_AT
CLW_C0          equ 1
CLW_H           equ 13
CLW_W           equ 8
CLOWN_NAMES     equ clown_data
CLOWN_SAT       equ clown_data + 3 * CLW_H * CLW_W
CLOWN_SPT       equ CLOWN_SAT + 3 * 61
CLW_CHUNK       equ 200     ; sprite pattern bytes a vblank (4 steps)

; A new screen (check_screens), A = its index byte 14.
logo_start:
        ld (logo_on), a
        xor a
        ld (clw_fr), a
        ld (clw_step), a
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
        cp 2
        jr z, clown_cell
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

; Same for the clown box.
clown_cell:
        ld a, (mode)
        cp MODE_SCREEN
        jr nz, .no
        ld a, d
        sub CLW_R0
        cp CLW_H
        jr nc, .no
        push hl
        push de
        add a, a                ; row * 8
        add a, a
        add a, a
        ld l, a
        ld a, e
        sub CLW_C0
        cp CLW_W
        jr nc, .nop
        add a, l
        ld l, a
        ld h, 0
        ld a, (clw_fr)          ; + frame * 104
        or a
        jr z, .f0
        ld de, CLW_H * CLW_W
.fm:    add hl, de
        dec a
        jr nz, .fm
.f0:    ld de, CLOWN_NAMES
        add hl, de
        ld a, (hl)
        pop de
        pop hl
        scf
        ret
.nop:   pop de
        pop hl
.no:    or a
        ret

; Each vblank in screen mode (VDP access allowed): the colour bars, or the
; clown's sprites and diamond.
logo_tick:
        ld a, (logo_on)
        or a
        ret z
        cp 2
        jp z, clown_tick
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

clown_tick:
        ld a, (up_pending)
        or a
        ret nz                  ; its tile set is not up yet
        ld a, (clw_step)
        or a
        jr nz, .s1
        ld hl, VR_SAT           ; step 0: no sprites while their patterns load
        call vdp_set_write
        ld a, SAT_END
        out (VDP_DATA), a
        ld a, 1
        ld (clw_step), a
        ret
.s1:    cp 5
        jr nc, .s5
        dec a                   ; steps 1-4: 200 bytes of sprite patterns each
        ld l, a
        ld h, 0
        ld de, CLW_CHUNK
        call clown_token.mul
        push hl
        ld de, VR_SPT
        add hl, de
        call vdp_set_write
        pop hl
        ld de, CLOWN_SPT
        add hl, de
        ld bc, CLW_CHUNK
.w:     ld a, (hl)              ; 43 T a byte
        out (VDP_DATA), a
        inc hl
        dec bc
        ld a, b
        or c
        jr nz, .w
        ld hl, clw_step
        inc (hl)
        ret
.s5:    jr nz, .run
        ld a, 6                 ; step 5: frame 0's sprites, and the arcade
        ld (clw_step), a        ; token's pattern (flip 0) and colour line
        ld a, SPR_BANK_B        ; 12 (tools/gen_sprites.py)
        call select_bank
        ld hl, VR_SPT + CLW_TPAT * 8
        call vdp_set_write
        ld hl, $C000 + (CLW_TOKEN - 64) * 128
        ld b, 32
.tp:    ld a, (hl)
        out (VDP_DATA), a
        inc hl
        nop
        djnz .tp
        ld a, SPR_BANK_A
        call select_bank
        ld a, (SPR_COLOURS + CLW_TOKEN * 16 + 12)
        ld (clw_tcol), a
        jr clown_sat
.run:   ld a, (frame_cnt)       ; then a frame every 8 vblanks
        and 7
        jp nz, clown_token
        ld a, (clw_fr)
        inc a
        cp 3
        jr c, .f
        xor a
.f:     ld (clw_fr), a
        ld a, (pnt_front)       ; the box's diamond rows
        call clown_token.rows
        ld a, (pnt_back)
        call clown_token.rows
        ; fall through
; The current frame's 15 sprites.
clown_sat:
        ld hl, VR_SAT + 4       ; entries 1-15 (0 is the token's: on top)
        call vdp_set_write
        ld a, (clw_fr)
        ld l, a
        ld h, 0
        ld de, 61
        call clown_token.mul
        ld de, CLOWN_SAT
        add hl, de
        ld b, 61
.s:     ld a, (hl)
        out (VDP_DATA), a
        inc hl
        nop
        nop
        djnz .s
        ; fall through
; SAT entry 0: the arcade's token (the credit coin dropping), wherever its
; sprite RAM has it, else hidden. First in the SAT so it is drawn over the
; romhack's sprites and never loses a line to the 4-sprites limit.
clown_token:
        ld hl, VR_SAT
        call vdp_set_write
        ld hl, ARC_SPRITES
        ld b, 64
.e:     inc hl
        ld a, (hl)              ; Y (0 = end)
        dec hl
        or a
        jr z, .none
        ld a, (hl)
        and $7F
        cp CLW_TOKEN
        jr z, .got
        inc hl
        inc hl
        inc hl
        inc hl
        djnz .e
.none:  ld a, $D1               ; hidden (below the screen, not the end)
        out (VDP_DATA), a
        ret
.got:   inc hl                  ; screen x = 224 - Y (sprites.asm)
        ld a, (hl)
        cpl
        sub 31
        ld c, 0
        jr nc, .x
        add a, 32               ; (left of the screen: early clock)
        ld c, $80
.x:     ld d, a
        inc hl
        inc hl
        ld a, (cam)             ; screen y = 240 - cam * 8 - X - 1
        add a, a
        add a, a
        add a, a
        neg
        add a, 239
        sub (hl)
        cp SAT_END
        jr nz, .y
        inc a
.y:     out (VDP_DATA), a
        ld a, d
        nop
        out (VDP_DATA), a
        ld a, CLW_TPAT
        nop
        out (VDP_DATA), a
        ld a, (clw_tcol)
        or c
        nop
        out (VDP_DATA), a
        ret
; HL = L * DE (L small).
.mul:   ld a, l
        ld hl, 0
        or a
        ret z
.m:     add hl, de
        dec a
        jr nz, .m
        ret
; A = name table high byte: box rows 10-12, columns 0-3 of the frame.
.rows:  ld b, 10
.r:     push af
        push bc
        ld l, b                 ; screen row CLW_R0 + b, column CLW_C0
        ld h, 0
        ld de, CLW_R0
        add hl, de
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, CLW_C0
        add hl, de
        add a, h
        ld h, a
        call vdp_set_write
        ld d, b
        ld e, CLW_C0
        ld a, CLW_R0
        add a, d
        ld d, a
        ld b, 4
.c:     call clown_cell         ; (the frame's name)
        out (VDP_DATA), a
        inc e
        djnz .c
        pop bc
        pop af
        inc b
        ld c, a
        ld a, b
        cp 13
        ld a, c
        jr c, .r
        ret

; Leaving the clown screen: hide its sprites, give the sprite cache back.
; Preserves BC, DE, HL.
clown_leave:
        ld a, (logo_on)
        cp 2
        ret nz
        xor a
        ld (logo_on), a
        push bc
        push de
        push hl
        ld hl, VR_SAT
        call vdp_set_write
        ld a, SAT_END
        out (VDP_DATA), a
        call sprites_init
        ld a, $FF
        ld (spr_cam), a
        pop hl
        pop de
        pop bc
        ret

clown_data:
        incbin "build/screens/clown.bin"

logo_data:
        incbin "build/screens/logo.bin"
