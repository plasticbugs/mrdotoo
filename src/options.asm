; =============================================================================
; options.asm - the DIP switch options screen (keypad *, attract only)
; =============================================================================
; The MSX2 port's options screen, on the ColecoVision: four of the arcade's
; DSW1 settings (bit map from the disassembly, msx/mrdo_msx.asm):
;   LIVES       bits 7-6   $00 = 2, $C0 = 3, $80 = 4, $40 = 5
;   EXTRA       bit 4      1 = easy (alpha monster tables $43EC/$4428)
;   SPECIAL     bit 3      1 = easy (diamond odds $50D6)
;   DIFFICULTY  bits 1-0   $03 = 1 (average) .. $00 = 4 (hard)
; Other bits (cabinet, rack test) keep DSW1_DEFAULT. The arcade reads DSW1
; through IO_DSW1, which read_inputs refreshes every vblank from opt_dsw1:
; difficulty, EXTRA and SPECIAL apply at once, lives at the next game start.
;
; Keypad * opens it while the arcade is in attract mode (no game, no credit:
; $E000 bit 7 clear, $E006 = 0). While it is up the NMI draws only this
; screen and delivers no vblank to the arcade (it waits in its idle loop).
; Up / down pick a row, left / right change it, * or fire leaves: the
; renderer then forgets what it showed and rebuilds the attract screen.
; # inserts coins now (main.asm read_inputs).
; =============================================================================
opt_dsw1        equ $59CC           ; ROM $FF padding after snd_req (the load
opt_on          equ $59CD           ; copies $FF over it: opt_init after)
opt_sel         equ $59CE           ;   0 closed, 1 opening, 2 open; row 0-3
opt_prev        equ $59CF           ;   joystick bits last vblank (edges)
        assert opt_prev < DRV_RAM
OPT_ROWS        equ 4
OPT_ARROW       equ $26             ; the cursor glyph (after T_DOT)
        assert OPT_ARROW * 8 == font_len
OPT_CUR_X       equ 5               ; cursor column
OPT_LBL_X       equ 7               ; label column
OPT_VAL_X       equ 20              ; value column
OPT_ROW0        equ 8               ; screen row of LIVES (rows 2 apart)

opt_init:
        ld a, DSW1_DEFAULT
        ld (opt_dsw1), a
        xor a
        ld (opt_on), a
        ld (opt_sel), a
        ret

; From read_inputs: keypad * pressed. Opens the screen in attract mode.
opt_request:
        ld a, (ARC_WORK)
        and $80
        ret nz                  ; a game is on
        ld a, (ARC_WORK + 6)
        or a
        ret nz                  ; a credit is in
        ld a, (opt_on)
        or a
        ret nz
        inc a
        ld (opt_on), a
        ret

; From the NMI (A = opt_on, nonzero; the NMI's AF BC DE HL pushed): this
; vblank's work while the screen is up, then the NMI ends without the
; arcade's vblank.
opt_nmi:
        cp 1
        call z, opt_open
        call opt_input
        xor a
        ld (in_nmi), a
        call late_ack
        pop hl
        pop de
        pop bc
        pop af
        retn

; Display blanked: font, cleared names, no sprites, the texts; then on.
opt_open:
        ld a, VDP_R1_ON & ~$40
        ld c, 1
        call vdp_reg
        ld a, VDP_R7
        ld c, 7
        call vdp_reg
        ld hl, VR_SAT
        call vdp_set_write
        ld a, SAT_END
        out (VDP_DATA), a
        ld hl, VR_PT            ; the font: 0-9 A-Z blank dot, the arrow
        ld de, font
        ld bc, font_len
        call vdp_copy
        ld hl, VR_PT + OPT_ARROW * 8    ; (vdp_copy leaves HL as it was)
        ld de, opt_arrow
        ld bc, 8
        call vdp_copy
        ld hl, VR_CT            ; white on black
        ld bc, (OPT_ARROW + 1) * 8
        ld a, $F1
        call vdp_fill
        ld hl, $1400            ; both name tables blank
        ld bc, $0300
        ld a, T_BLANK
        call vdp_fill
        ld hl, $1800
        ld bc, $0300
        ld a, T_BLANK
        call vdp_fill
        ld de, opt_texts
.t:     ld a, (de)              ; [row, column, text, 0] ... $FF
        cp $FF
        jr z, .tx
        ld h, a
        inc de
        ld a, (de)
        ld l, a
        inc de
        call opt_print
        jr .t
.tx:    xor a
        ld (opt_sel), a
        ld b, OPT_ROWS
.r:     push bc
        ld a, OPT_ROWS
        sub b
        call opt_value
        pop bc
        djnz .r
        call opt_cursor
        call opt_joy
        ld (opt_prev), a        ; keys already held are not presses
        ld a, 2
        ld (opt_on), a
        ld a, VDP_R1_ON
        ld c, 1
        jp vdp_reg

; Each vblank: the joystick's new presses, and the keypad's *.
opt_input:
        call opt_joy
        ld b, a
        ld a, (opt_prev)
        cpl
        or b
        cpl                     ; pressed now (0 bits), not before: 1 bits
        ld c, a
        ld a, b
        ld (opt_prev), a
        out (CTL_SEL_KEYPAD), a
        in a, (CTL_P1)
        and $0F
        ld hl, key_prev
        cp (hl)
        ld (hl), a
        jr z, .joy
        cp KEY_STAR
        jr z, opt_close
.joy:   bit 6, c                ; fire: leave
        jr nz, opt_close
        bit 0, c                ; up
        jr z, .nu
        ld a, (opt_sel)
        or a
        jr z, .nu
        dec a
        jr .sel
.nu:    bit 2, c                ; down
        jr z, .nd
        ld a, (opt_sel)
        cp OPT_ROWS - 1
        jr nc, .nd
        inc a
.sel:   push af
        call opt_uncursor
        pop af
        ld (opt_sel), a
        jp opt_cursor
.nd:    bit 3, c                ; left: the previous value
        ld e, -1
        jr nz, .chg
        bit 1, c                ; right: the next
        ret z
        ld e, 1
.chg:   ld a, (opt_sel)         ; the current value's index, +/- 1
        call opt_index
        add a, e
        ret m                   ; (no wrap: stops at the ends)
        ld b, a
        ld a, (opt_sel)
        call opt_row            ; HL -> [mask, count, values...]
        ld a, (hl)
        cpl
        ld c, a                 ; C = the other bits
        inc hl
        ld a, b
        cp (hl)
        ret nc
        inc hl
        ld a, l
        add a, b
        ld l, a
        jr nc, .n
        inc h
.n:     ld a, (opt_dsw1)
        and c
        or (hl)
        ld (opt_dsw1), a
        ld a, (opt_sel)
        jp opt_value

; Leave: the renderer rebuilds whatever the arcade shows, which runs again.
opt_close:
        xor a
        ld (opt_on), a
        ld (mode), a
        ld (hud_ok), a
        ld (cw_valid), a
        ld a, $FF
        ld (scr), a
        ld (cw), a
        ld (cw_attr), a
        ld (cw_tile), a
        ld (spr_cam), a
        ld a, 1
        ld (redraw_all), a
        ret

; A = joystick bits, active low: 0 up, 1 right, 2 down, 3 left, 6 fire.
opt_joy:
        out (CTL_SEL_JOY), a
        in a, (CTL_P1)
        or $B0                  ; (unused bits read as released)
        ret

; A = row: HL -> its entry in opt_rows. Preserves BC, DE.
opt_row:
        ld hl, opt_rows
        or a
        ret z
        push bc
        ld b, a
        push de
.r:     inc hl                  ; skip [mask, count, values x count, glyph
        ld e, (hl)              ; text x count]: 2 + 5 x count bytes
        inc hl
        ld d, 0
        add hl, de              ; the values
        add hl, de              ; value texts: 4 chars each (16-bit adds,
        add hl, de              ; the table may cross a page)
        add hl, de
        add hl, de
        djnz .r
        pop de
        pop bc
        ret

; A = row: A = the index of opt_dsw1's current value in it (0 if none
; matches). Preserves DE.
opt_index:
        call opt_row
        ld a, (opt_dsw1)
        and (hl)
        ld c, a
        inc hl
        ld b, (hl)
        inc hl
        ld d, 0
.f:     ld a, (hl)
        cp c
        jr z, .got
        inc hl
        inc d
        djnz .f
        ld d, 0
.got:   ld a, d
        ret

; A = row: its current value's text in the value column.
opt_value:
        push af
        call opt_index
        ld b, a                 ; B = index
        pop af
        push af
        call opt_row
        inc hl
        ld c, (hl)              ; C = count
        inc hl
        ld a, l                 ; past the values, then 4 chars per value
        add a, c
        ld l, a
        jr nc, .n
        inc h
.n:     ld a, b
        add a, a
        add a, a
        add a, l
        ld l, a
        jr nc, .n2
        inc h
.n2:    ex de, hl
        pop af
        call opt_rowaddr
        ld a, l
        add a, OPT_VAL_X
        ld l, a
        ld b, 4
        jr opt_putn

; A = row -> HL = the name table offset of its line (row OPT_ROW0 + 2A).
opt_rowaddr:
        add a, a
        add a, OPT_ROW0
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ret

opt_cursor:
        ld a, OPT_ARROW
        jr opt_curs
opt_uncursor:
        ld a, T_BLANK
opt_curs:
        push af
        ld a, (opt_sel)
        call opt_rowaddr
        ld a, l
        add a, OPT_CUR_X
        ld l, a
        pop af
        ld c, a
        ld b, 1
        ld de, $1400            ; both name tables
        push hl
        add hl, de
        call vdp_set_write
        ld a, c
        out (VDP_DATA), a
        pop hl
        ld de, $1800
        add hl, de
        call vdp_set_write
        ld a, c
        out (VDP_DATA), a
        ret

; H = screen row, L = column, DE -> 0-terminated text: into both name
; tables. DE ends past the 0.
opt_print:
        push de
        ld b, 0                 ; its length
.len:   ld a, (de)
        or a
        jr z, .l
        inc de
        inc b
        jr .len
.l:     pop de
        push bc
        ld a, h                 ; HL = row * 32 + column
        ld c, l
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, l
        or c
        ld l, a
        pop bc
        push bc
        call opt_putn
        pop bc
        ld a, e                 ; past the text and its 0
        add a, b
        ld e, a
        jr nc, .n
        inc d
.n:     inc de
        ret
; HL = name table offset, DE -> B characters: into both tables. Preserves DE.
opt_putn:
        push de
        push hl
        push bc
        ld bc, $1400
        add hl, bc
        pop bc
        push bc
        call .one
        pop bc
        pop hl
        pop de
        push de
        ld a, h
        add a, high $1800
        ld h, a
        call .one
        pop de
        ret
.one:   call vdp_set_write
.c:     ld a, (de)
        call opt_glyph
        out (VDP_DATA), a
        inc de
        djnz .c
        ret
; A = character -> its font tile. Preserves everything else.
opt_glyph:
        cp "A"
        jr c, .d
        sub "A" - $0A
        ret
.d:     cp "0"
        jr c, .s
        sub "0"
        ret
.s:     ld a, T_BLANK
        ret

opt_arrow:                      ; a right arrow: shaft and head
        db %00010000
        db %00011000
        db %11111100
        db %11111110
        db %11111100
        db %00011000
        db %00010000
        db %00000000
; Rows: DSW1 mask, value count, the values' bits, 4-character texts.
opt_rows:
        db $C0, 4, $00, $C0, $80, $40
        db "2   3   4   5   "
        db $10, 2, $10, $00
        db "EASYHARD"
        db $08, 2, $08, $00
        db "EASYHARD"
        db $03, 4, $03, $02, $01, $00
        db "1   2   3   4   "
opt_texts:
        db 4, 12, "OPTIONS", 0
        db OPT_ROW0, OPT_LBL_X, "LIVES", 0
        db OPT_ROW0 + 2, OPT_LBL_X, "EXTRA", 0
        db OPT_ROW0 + 4, OPT_LBL_X, "SPECIAL", 0
        db OPT_ROW0 + 6, OPT_LBL_X, "DIFFICULTY", 0
        db 18, 7, "PRESS FIRE TO EXIT", 0
        db $FF
