; =============================================================================
; vgland.asm - VERY GOOD: the romhack's Mr. Do, apple and dinosaur
; =============================================================================
; The VERY GOOD cutscene scrolls its characters along a band of background
; tiles (scene.asm): first the letter monster, then the dinosaur, the apple
; and Mr. Do pushing it, all moving right one pixel per step of the arcade's
; scroll register until it reaches 0 (they have landed; ~3.6 s later the
; scene ends). The arcade's own tiles for the last three clash on the
; TMS9918, so they are drawn with the CV romhack's picture of the same three
; instead (tools/gen_images.py vgland): its 59 tiles in codes vgl_base.. (the
; band's slot banks are 2 x SCN_SLOTS codes, which leaves them free), 14 x 5
; names put into the band's names (SCN_BUF) at every build, at column
; VGL_COL - scroll / 8 rounded up (8-pixel steps; it lands at VGL_COL at
; scroll 0), and its 10 sprites (some black, covering tile pixels) moved with
; it. Its two frames (the legs) alternate every 8 vblanks. The band builder
; leaves out the arcade's art for them (native rows 7-22, vgl_filter), so
; only the letter monster is built from the arcade's tiles. The sprite pass
; pauses while this runs; leaving the screen gives the sprite cache back.
; =============================================================================
VGL_BANK        equ IMG_BANK_EXTRA  ; after the EXTRA image
VGL_DATA        equ $E000
VGL_PT          equ VGL_DATA
VGL_CT          equ VGL_DATA + $200
VGL_SPT         equ VGL_DATA + $400
VGL_SAT1        equ VGL_DATA + $700
VGL_SAT2        equ VGL_DATA + $730
VGL_FR1         equ VGL_DATA + $760
VGL_FR2         equ VGL_DATA + $7B0
VGL_TILES       equ 59
VGL_IPT         equ VGL_DATA + $800 ; the round-end icons' tiles (22, codes
VGL_ICT         equ VGL_DATA + $A00 ;   vgl_base - VGL_ICONS..: the top of
VGL_IMAP        equ VGL_DATA + $B00 ;   the band's second slot bank, which
VGL_IOV         equ VGL_DATA + $B18 ;   the letter monster (<= 20) never
VGL_ICONS       equ 22              ;   reaches), names, overlays
VGL_SPRS        equ 22              ; sprite patterns (20 + 2 icon overlays)
        assert VGL_ICT - VGL_IPT == VGL_CT - VGL_PT
        assert VGL_ICONS <= SCN_SLOTS - 20
VGL_COL         equ 5               ; = tools/gen_images.py VG_COL, VG_ROW
VGL_ROW         equ 16
VGL_CHUNK       equ 192             ; bytes uploaded per vblank (spaced)
VG_SCR          equ 3               ; "verygood" in tools/gen_screens.py SCREENS
VGL_NONE        equ $80             ; vgl_x0: not placed yet

; Variables: the driver's area is full; these sit after SCN_LIST in the
; same unused arcade padding (cleared by render_init).
vgl_on          equ SCN_LIST + SCN_SLOTS    ; the VERY GOOD screen is up
vgl_step        equ vgl_on + 2      ; upload step (6 = done; 4 = picture's tiles in)
vgl_done        equ vgl_on + 3      ; bytes of the step done (2)
vgl_base        equ vgl_on + 5      ; code of romhack tile 1
vgl_phase       equ vgl_on + 6      ; frame (the legs)
nmi_late        equ vgl_on + 7      ; main.asm: an overrunning NMI owes the VDP ack
img_d           equ vgl_on + 8      ; image.asm: EXTRA pan, tiles left to go
img_bd          equ vgl_on + 9      ;   the step being built
img_brow        equ vgl_on + 10     ;   next row of it ($FF: none)
up_black        equ vgl_on + 11     ; render.asm: the next upload's blank frame is black
vgl_xb          equ vgl_on + 12     ; block column of the build under way
vgl_x0          equ vgl_on + 13     ; block column on screen (VGL_NONE: none)
vgl_xs          equ vgl_on + 14     ; block column the sprites are at
blank_req       equ vgl_on + 15     ; opt.asm: the arcade is wiping a screen (go_black)
scr_hold        equ vgl_on + 16     ; render.asm: vblanks screens are not looked for
        assert scr_hold < $2F00

; From scene_update (a screen with a band): the VERY GOOD screen starts the
; romhack block. Returns Z (the band keeps building). Clobbers AF.
vgl_check:
        ld a, (vgl_on)
        or a
        jr nz, .z
        ld a, (scr)
        cp VG_SCR
        jr nz, .z
        xor a
        ld (vgl_step), a
        ld (vgl_done), a
        ld (vgl_done+1), a
        ld (vgl_phase), a
        ld a, VGL_NONE
        ld (vgl_x0), a
        ld (vgl_xs), a
        ld (vgl_xb), a
        ld a, (scn_base)
        add a, 2*SCN_SLOTS
        ld (vgl_base), a
        xor a                   ; no merged icon tiles loaded
        ld hl, vgl_mk
        ld b, 6
.mk:    ld (hl), a
        inc hl
        djnz .mk
        ld a, 1
        ld (vgl_on), a
.z:     xor a
        ret

; The band builder's art mask byte A (native rows E..E+7): the romhack
; block's rows left out. Clobbers C.
vgl_filter:
        ld c, a
        ld a, (vgl_on)
        or a
        ld a, c
        ret z
        push hl
        ld a, e
        rrca
        rrca
        rrca
        and 3
        ld hl, .f
        add a, l
        ld l, a
        jr nc, .n
        inc h
.n:     ld a, c
        and (hl)
        pop hl
        ret
.f:     db $7F, $00, $80, $FF   ; native rows 7-22 out

; After the builder filled band row scn_k (at scn_rowbuf) for scn_scroll:
; the block's names into it. Preserves BC.
vgl_patch:
        ld a, (vgl_on)
        or a
        ret z
        ld a, (vgl_step)
        cp 4
        ret c                   ; its tiles are not loaded yet
        ld a, (scn_scroll)      ; column = VGL_COL - (scroll + 7) / 8
        ld l, a
        ld h, 0
        ld de, 7
        add hl, de
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, (scn_k)           ; a build's first row: no column yet
        or a
        jr nz, .k0
        ld a, VGL_NONE
        ld (vgl_xb), a
.k0:    push hl                 ; the arcade still has their art in this band
        ld a, (scn_k)           ; row? (it erases it as the scene ends)
        add a, a
        add a, a
        ld e, a
        ld d, 0
        ld hl, scn_mask
        add hl, de
        ld a, (hl)              ; native rows 7-22
        and $80
        inc hl
        or (hl)
        inc hl
        ld e, a
        ld a, (hl)
        and $7F
        or e
        pop hl
        ret z
        ld a, VGL_COL
        sub h
        ld (vgl_xb), a
        push bc
        ld c, a                 ; C = column of block column 0 (signed)
        ld a, VGL_BANK
        call select_bank
        call vgl_src            ; HL = the row's romhack names
        ld de, (scn_rowbuf)
        ld b, 14
.j:     ld a, c
        cp 24
        jr nc, .skip            ; left of the band (negative) or right of it
        ld a, (hl)
        or a
        jr z, .skip             ; (nothing there in the picture)
        push de
        push hl
        ld l, c
        ld h, 0
        add hl, de
        ex de, hl
        ld hl, vgl_base
        add a, (hl)
        dec a
        ld (de), a
        pop hl
        pop de
.skip:  inc hl
        inc c
        djnz .j
        pop bc
        ld a, (scn_pbank)       ; the builder's bank back
        jp select_bank

; HL = romhack names of block row scn_k in the current frame. Preserves BC.
vgl_src:
        ld a, (scn_k)
        ld e, a
        ld hl, VGL_FR1
        ld a, (vgl_phase)
        or a
        jr z, .m
        ld a, e
        cp 3
        jr c, .m
        sub 3                   ; frame 2 changes rows 3-4
        ld e, a
        ld hl, VGL_FR2
.m:     ld a, e
        add a, a                ; * 14
        ld d, a
        add a, a
        add a, a
        add a, a
        sub d
        ld e, a
        ld d, 0
        add hl, de
        ret

; scene_flush has put a build's names on screen.
vgl_flushed:
        ld a, (vgl_on)
        or a
        ret z
        ld a, (vgl_xb)
        ld (vgl_x0), a
        ret

; Each vblank of the VERY GOOD screen, after the band's flush (VDP access
; allowed): the uploads, then the sprites and the legs.
vgl_tick:
        ld a, VGL_BANK
        call select_bank
        ld a, (vgl_step)
        or a
        jr nz, .up
        call vgl_hide           ; step 0: no sprites while their patterns load
        ld a, 1
        ld (vgl_step), a
        ret
.up:    cp 6
        jp nc, .run
        ld hl, VR_SPT           ; step 1: sprite patterns
        ld de, VGL_SPT
        ld bc, VGL_SPRS*32
        dec a
        jr z, .job
        cp 3                    ; steps 2, 3: the picture's tile patterns,
        ld a, (vgl_base)        ; colours; 4, 5: the icons'
        ld de, VGL_PT
        ld bc, VGL_TILES*8
        jr c, .t
        sub VGL_ICONS
        ld de, VGL_IPT
        ld bc, VGL_ICONS*8
.t:     ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, (vgl_step)
        rra
        jr nc, .job             ; (even steps: patterns)
        ld a, h
        add a, high VR_CT
        ld h, a
        ld a, d                 ; (colours $200 after the patterns)
        add a, 2
        ld d, a
.job:   push hl                 ; HL = VRAM, DE = source, BC = length
        ld hl, (vgl_done)
        add hl, de
        ex (sp), hl             ; (sp) = source + done
        ld de, (vgl_done)
        add hl, de
        push hl                 ; (sp) = VRAM + done
        ld h, b
        ld l, c
        or a
        sbc hl, de              ; left
        ld bc, VGL_CHUNK
        or a
        sbc hl, bc
        jr nc, .full
        add hl, bc              ; the rest of the job
        ld b, h
        ld c, l
        ld a, (vgl_step)
        inc a
        ld (vgl_step), a
        ld hl, 0
        ld (vgl_done), hl
        jr .go
.full:  ld hl, (vgl_done)
        add hl, bc
        ld (vgl_done), hl
.go:    pop hl
        ld a, b
        or c
        jr z, .skip             ; (the job ended on a chunk boundary)
        call vdp_set_write
        pop hl
.w:     ld a, (hl)              ; 43 T a byte
        out (VDP_DATA), a
        inc hl
        dec bc
        ld a, b
        or c
        jr nz, .w
        ret
.skip:  pop hl
        ret
.run:   call vgl_icons
        ld a, (frame_cnt)       ; the legs, every 8 vblanks
        and 7
        jr nz, .spr
        ld a, (vgl_phase)
        xor 1
        ld (vgl_phase), a
        ld a, (vgl_x0)
        cp VGL_NONE
        jr z, .spr
        ld b, VGL_ROW + 3       ; rows 3-4 of the block
        ld c, 3
        call vgl_rows
        ld b, VGL_ROW + 4
        ld c, 4
        call vgl_rows
        ld a, VGL_NONE          ; and its sprites' frame
        ld (vgl_xs), a
.spr:   ld a, (vgl_x0)          ; the sprites follow the block
        ld hl, vgl_xs
        cp (hl)
        ret z
        ld (hl), a
        cp VGL_NONE
        jr nz, vgl_sat
        jp vgl_hide             ; the block is gone: so are they
; The romhack's sprites for block column A (signed) and the current frame.
vgl_sat:
        sub VGL_COL             ; pixels to add: (column - VGL_COL) * 8
        ld l, a
        rla
        sbc a, a
        ld h, a
        add hl, hl
        add hl, hl
        add hl, hl
        ex de, hl               ; DE = offset
        ld hl, VR_SAT
        call vdp_set_write
        ld hl, VGL_SAT1
        ld a, (vgl_phase)
        or a
        jr z, .f
        ld hl, VGL_SAT2
.f:     ld b, 10
.e:     push bc
        ld c, (hl)              ; Y
        inc hl
        push hl
        ld a, (hl)              ; X + offset (16-bit)
        ld l, a
        ld h, 0
        add hl, de
        ld b, 0                 ; B = early clock ($80) or 0
        bit 7, h
        jr z, .pos
        ld a, l                 ; left of the screen: early clock, X + 32
        add a, 32
        ld l, a
        ld a, h
        adc a, 0
        ld h, a
        ld b, $80
        jr nz, .hide            ; more than 32 pixels left: hidden
        jr .x
.pos:   ld a, h
        or a
        jr z, .x
.hide:  ld c, $D1               ; off the screen (not the $D0 terminator)
.x:     ld a, c
        out (VDP_DATA), a
        ld a, l
        pop hl
        out (VDP_DATA), a
        inc hl
        ld a, (hl)              ; pattern
        inc hl
        nop
        out (VDP_DATA), a
        ld a, (hl)              ; colour
        inc hl
        or b
        out (VDP_DATA), a
        pop bc
        djnz .e
        ret                     ; (vgl_icons ends the SAT)

; SAT entries 0-9 (the picture's sprites) off the screen, 10 = the end.
vgl_hide:
        ld hl, VR_SAT
        call vdp_set_write
        ld b, 10
.e:     ld a, $D1               ; (not the $D0 terminator)
        out (VDP_DATA), a
        ld c, 3
        nop
        nop
.z:     xor a
        nop
        out (VDP_DATA), a
        dec c
        jr nz, .z
        djnz .e
        nop
        ld a, SAT_END
        out (VDP_DATA), a
        ret

; The arcade's round-end icons: one sprite per SCENE line, the reason the
; round ended ($2D creep, $6E cherries, $69 diamond, $51 letter monster).
; The romhack's 2 x 3 tile icon for it goes into both name tables at the
; sprite's place (col = x / 8 + 1, rows from (y + 4) / 8 - 1: centred on the
; line), and its black overlay sprite (cherries, creep) into SAT entries
; 10-12, then the end. The lines are 16 px apart, the icons 24 px tall: an
; icon's bottom tile row shares its cells with the next one's top row. Their
; pixels never share a line (tops use lines 4-7, bottoms 0-1), so such a cell
; gets a merged tile (patterns ORed, each line's colour from the tile that
; has pixels there) in codes scn_base + VGL_MRG.. (bank 0 slots the letter
; monster never reaches), uploaded when the pair changes. Every vblank: full
; redraws and flips may repaint the cells. Clobbers everything.
VGL_MRG         equ SCN_SLOTS - 6   ; 6 merged tiles: slot = upper icon * 2 + col
VGL_ZERO        equ VGL_DATA + $B20 ; 8 zero bytes (and colours at + $200)
vgl_ic          equ vgl_on + 32     ; icons this vblank: count, (row, col, reason) x 3
vgl_mk          equ vgl_on + 42     ; merged tile per slot: its key (0: none) x 6
vgl_ti          equ vgl_on + 48     ; the icon being drawn: index,
vgl_tr          equ vgl_on + 49     ;   top row,
vgl_tc          equ vgl_on + 50     ;   column,
vgl_tn          equ vgl_on + 51     ;   reason,
vgl_tk          equ vgl_on + 52     ;   tile row 0-2,
vgl_t0          equ vgl_on + 53     ;   its two codes
scr_xoff        equ vgl_on + 55     ; render.asm: a centred screen's x offset (tiles)
        assert scr_xoff < $2F00
        assert high vgl_ic == high (vgl_ic + 9) && high vgl_mk == high (vgl_mk + 5)
        assert high ARC_SPRITES == high (ARC_SPRITES + 127)
vgl_icons:
        xor a
        ld (vgl_ic), a
        ld hl, ARC_SPRITES
        ld b, 32
.c:     push bc
        push hl
        call vgl_icon           ; A = reason, D = row, E = col (carry: none)
        jr c, .cx
        ld c, a
        ld a, (vgl_ic)
        cp 3
        jr nc, .cx
        ld b, a
        inc a
        ld (vgl_ic), a
        ld a, b
        add a, a
        add a, b
        add a, low (vgl_ic + 1)
        ld l, a
        ld h, high vgl_ic
        ld (hl), d
        inc l
        ld (hl), e
        inc l
        ld (hl), c
.cx:    pop hl
        pop bc
        inc l                   ; (ARC_SPRITES + 128 stays in one page)
        inc l
        inc l
        inc l
        inc l                   ; Y of the entry = 0: the queue's end
        ld a, (hl)
        dec l
        or a
        jr z, .names
        djnz .c
.names: ld a, (vgl_ic)
        or a
        jr z, .sat
        ld b, a
        ld c, 0
        ld hl, vgl_ic + 1
.i:     push bc
        push hl
        call vgl_idraw
        pop hl
        pop bc
        inc l
        inc l
        inc l
        inc c
        djnz .i
.sat:   ld hl, VR_SAT + 40      ; the overlays
        call vdp_set_write
        ld a, (vgl_ic)
        or a
        jr z, .end
        ld b, a
        ld hl, vgl_ic + 1
.s:     push bc
        push hl
        ld d, (hl)              ; row
        inc l
        ld e, (hl)              ; col
        inc l
        ld a, (hl)              ; reason
        add a, a                ; VGL_IOV + reason * 2
        ld hl, VGL_IOV
        add a, l
        ld l, a
        ld a, (hl)              ; pattern (0: none)
        or a
        jr z, .sx
        ld c, a
        inc l
        ld a, d                 ; Y = row * 8 + dy
        add a, a
        add a, a
        add a, a
        add a, (hl)
        out (VDP_DATA), a
        ld a, e                 ; X = col * 8
        add a, a
        add a, a
        add a, a
        nop
        out (VDP_DATA), a
        ld a, c
        push hl
        pop hl
        out (VDP_DATA), a
        ld a, 1                 ; black
        push hl
        pop hl
        out (VDP_DATA), a
.sx:    pop hl
        pop bc
        inc l
        inc l
        inc l
        djnz .s
.end:   ld a, SAT_END
        out (VDP_DATA), a
        ret

; HL -> an icon list entry, C = its index: its 3 rows of 2 names into both
; name tables.
vgl_idraw:
        ld a, c
        ld (vgl_ti), a
        ld a, (hl)
        ld (vgl_tr), a
        inc l
        ld a, (hl)
        ld (vgl_tc), a
        inc l
        ld a, (hl)
        ld (vgl_tn), a
        xor a
.r:     ld (vgl_tk), a
        ld c, 0
        call vgl_icode
        ld (vgl_t0), a
        ld c, 1
        call vgl_icode
        ld (vgl_t0 + 1), a
        ld a, (pnt_front)
        call .tab
        ld a, (pnt_back)
        call .tab
        ld a, (vgl_tk)
        inc a
        cp 3
        jr c, .r
        ret
.tab:   ld c, a                 ; table + (row + k) * 32 + col
        ld a, (vgl_tr)
        ld hl, vgl_tk
        add a, (hl)
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, (vgl_tc)
        or l
        ld l, a
        ld a, h
        add a, c
        ld h, a
        call vdp_set_write
        ld hl, vgl_t0
        ld a, (hl)
        out (VDP_DATA), a
        inc hl
        push hl
        pop hl
        ld a, (hl)
        nop
        out (VDP_DATA), a
        ret

; C = column 0/1 of tile row vgl_tk of the icon being drawn: A = its code
; (a merged one where another icon's row shares the cell). Preserves C.
vgl_icode:
        ld a, (vgl_tk)
        cp 2
        jr z, .bot
        or a
        jr nz, .plain
        ld a, (vgl_tr)          ; top row: an icon 2 rows up in this column?
        sub 2
        call vgl_find           ; -> B = its index, A = its reason
        jr c, .plain
        ld d, a                 ; D = upper reason
        ld a, (vgl_tn)
        ld e, a                 ; E = lower reason
        jr .mrg
.bot:   ld a, (vgl_tr)          ; bottom row: an icon 2 rows down?
        add a, 2
        call vgl_find
        jr c, .plain
        ld e, a
        ld a, (vgl_tn)
        ld d, a
        ld a, (vgl_ti)
        ld b, a
.mrg:   ld a, b                 ; slot = upper icon * 2 + col
        add a, a
        add a, c
        jp vgl_merge
.plain: ld a, (vgl_tn)          ; VGL_IMAP + reason * 6 + row * 2 + col
        ld b, a
        add a, a
        add a, b
        add a, a
        ld b, a
        ld a, (vgl_tk)
        add a, a
        add a, b
        add a, c
        ld hl, VGL_IMAP
        add a, l
        ld l, a
        ld a, (hl)              ; icon tile index + 1 (0 = black)
        or a
        ret z
vgl_itile:                      ; icon tile index + 1 -> its code
        add a, low (-VGL_ICONS - 1)
        ld hl, vgl_base
        add a, (hl)
        ret

; A = row: the icon whose top row that is, in column vgl_tc: B = its index,
; A = its reason; carry if none. Preserves C.
vgl_find:
        ld d, a
        ld a, (vgl_tc)
        ld e, a
        ld a, (vgl_ic)
        or a
        scf
        ret z
        ld b, 0
        ld hl, vgl_ic + 1
.f:     ld a, (hl)
        cp d
        jr nz, .n
        inc l
        ld a, (hl)
        dec l
        cp e
        jr nz, .n
        inc l
        inc l
        ld a, (hl)
        or a
        ret
.n:     inc l
        inc l
        inc l
        inc b
        ld a, (vgl_ic)
        cp b
        jr nz, .f
        scf
        ret

; A = merged slot, D = upper icon's reason, E = lower's, C = column: A =
; the merged tile's code, uploaded if that slot held another pair.
; Preserves C.
vgl_merge:
        push bc
        ld b, a
        ld a, d                 ; key = upper * 8 + lower * 2 + col + 1
        add a, a
        add a, a
        add a, a
        ld l, a
        ld a, e
        add a, a
        add a, l
        add a, c
        inc a
        ld l, a
        ld a, b
        add a, low vgl_mk
        ld b, l
        ld l, a
        ld h, high vgl_mk
        ld a, b
        cp (hl)
        jr z, .have
        ld (hl), a
        ld a, l                 ; the slot again
        sub low vgl_mk
        push af
        ld a, d                 ; bottom row of the upper icon
        add a, a
        add a, d
        add a, a
        add a, 4
        add a, c
        call .src
        push hl
        ld a, e                 ; top row of the lower icon
        add a, a
        add a, e
        add a, a
        add a, c
        call .src
        pop de                  ; DE = upper's bottom tile, HL = lower's top
        pop af
        push af
        push hl
        call .code
        ld l, a                 ; VRAM = code * 8
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        call vdp_set_write
        pop bc
        pop hl
        push de
        push hl
        push bc
        ld b, 8
.p:     ld a, (de)              ; patterns ORed
        or (hl)
        out (VDP_DATA), a
        inc de
        inc hl
        djnz .p
        pop hl                  ; colours
        ld a, h
        add a, high VR_CT
        ld h, a
        call vdp_set_write
        pop hl
        pop de
        ld b, 8
.cl:    ld a, (de)              ; the line's colour: the tile with pixels
        or a
        jr z, .ct
        inc d
        inc d
        ld a, (de)
        dec d
        dec d
        jr .co
.ct:    inc h
        inc h
        ld a, (hl)
        dec h
        dec h
.co:    out (VDP_DATA), a
        inc de
        inc hl
        djnz .cl
        pop af
        jr .out
.have:  ld a, l
        sub low vgl_mk
.out:   call .code
        pop bc
        ret
.code:  add a, VGL_MRG          ; slot -> code
        ld hl, scn_base
        add a, (hl)
        ret
; A = VGL_IMAP offset: HL -> that tile's 8 pattern bytes (colours + $200).
.src:   ld hl, VGL_IMAP
        add a, l
        ld l, a
        ld a, (hl)
        or a
        ld hl, VGL_ZERO
        ret z
        dec a
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        push de
        ld de, VGL_IPT
        add hl, de
        pop de
        ret

; HL -> a sprite RAM entry (code, Y, colour, X): an icon? A = reason 0-3,
; D = top tile row, E = tile column; carry if not (or off the screen).
vgl_icon:
        ld a, (hl)              ; code
        and $7F
        ld c, 0
        cp $2D
        jr z, .k
        inc c
        cp $6E
        jr z, .k
        inc c
        cp $69
        jr z, .k
        inc c
        cp $51
        jr nz, .no
.k:     inc l
        ld a, (hl)              ; Y: screen x = 224 - Y
        or a
        jr z, .no
        cpl
        sub 31
        jr c, .no
        cp 232
        jr nc, .no              ; (cols +1, +2 must fit)
        rrca
        rrca
        rrca
        and $1F
        inc a                   ; one column right of the arcade's place (the
        ld e, a                 ; tiles are wider than its 16px sprite, user)
        inc l
        inc l
        ld a, (cam)             ; X: screen y = 240 - cam * 8 - X
        add a, a
        add a, a
        add a, a
        neg
        add a, 240
        sub (hl)
        jr c, .no
        add a, 4
        rrca
        rrca
        rrca
        and $1F
        dec a
        cp 22
        jr nc, .no              ; (3 rows must fit)
        ld d, a
        ld a, c
        or a
        ret
.no:    scf
        ret

; B = screen row, C = block row: that row of the current frame, clipped to
; the band, into both name tables at column vgl_x0.
vgl_rows:
        ld a, (scn_k)           ; (vgl_src reads scn_k)
        push af
        ld a, c
        ld (scn_k), a
        call vgl_src
        pop af
        ld (scn_k), a
        ld a, (pnt_front)
        call .one
        ld a, (pnt_back)
.one:   push hl                 ; A = table high byte, B = row, HL = names
        push bc
        ex de, hl
        ld l, b
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add a, h
        ld h, a
        ex de, hl               ; DE = row address, HL = names
        ld a, (vgl_x0)
        ld c, a
        ld b, 14
.j:     ld a, c
        cp 24
        jr nc, .n               ; outside the band
        push hl
        ld l, c
        ld h, 0
        add hl, de
        call vdp_set_write
        pop hl
        ld a, (hl)
        or a
        jr z, .o
        push hl
        ld hl, vgl_base
        add a, (hl)
        dec a
        pop hl
.o:     out (VDP_DATA), a
.n:     inc hl
        inc c
        djnz .j
        pop bc
        pop hl
        ret

; A new screen or the playfield takes over: if the block was up, hide its
; sprites and give the sprite cache back. Preserves BC, DE, HL.
vgl_leave:
        ld a, (vgl_on)
        or a
        ret z
        xor a
        ld (vgl_on), a
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
