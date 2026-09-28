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
VGL_COL         equ 5               ; = tools/gen_images.py VG_COL, VG_ROW
VGL_ROW         equ 16
VGL_CHUNK       equ 192             ; bytes uploaded per vblank (spaced)
VG_SCR          equ 2               ; "verygood" in tools/gen_screens.py SCREENS
VGL_NONE        equ $80             ; vgl_x0: not placed yet

; Variables: the driver's area is full; these sit after SCN_LIST in the
; same unused arcade padding (cleared by render_init).
vgl_on          equ SCN_LIST + SCN_SLOTS    ; the VERY GOOD screen is up
vgl_step        equ vgl_on + 2      ; upload step (4 = done)
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
        ld hl, VR_SAT           ; step 0: no sprites while their patterns load
        call vdp_set_write
        ld a, SAT_END
        out (VDP_DATA), a
        ld a, 1
        ld (vgl_step), a
        ret
.up:    cp 4
        jr nc, .run
        ld hl, VR_SPT           ; step 1: sprite patterns
        ld de, VGL_SPT
        ld bc, 20*32
        dec a
        jr z, .job
        ld a, (vgl_base)        ; steps 2, 3: tile patterns, colours
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, VGL_PT
        ld bc, VGL_TILES*8
        ld a, (vgl_step)
        cp 2
        jr z, .job
        ld a, h
        add a, high VR_CT
        ld h, a
        ld de, VGL_CT
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
.run:   ld a, (frame_cnt)       ; the legs, every 8 vblanks
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
        ld hl, VR_SAT           ; the block is gone: so are they
        call vdp_set_write
        ld a, SAT_END
        out (VDP_DATA), a
        ret
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
        ld a, SAT_END
        out (VDP_DATA), a
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
