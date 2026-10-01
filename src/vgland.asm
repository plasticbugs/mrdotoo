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
VGL_IPT         equ VGL_DATA + $800 ; the arcade's round-end icons: 3 sprite
VGL_ICOL        equ VGL_DATA + $B00 ;   layers per reason, and their colours
VGL_ILAY        equ 12              ;   (tools/gen_images.py ARC_ICONS)
VGL_SPRS        equ 22              ; sprite patterns (the romhack's 20 + 2
                                    ; unused); the icon layers follow
VGL_COL         equ 5               ; = tools/gen_images.py VG_COL, VG_ROW
VGL_ROW         equ 16
VGL_CHUNK       equ 192             ; bytes uploaded per vblank (spaced)
WONDER_SCR      equ 2               ; "wonderful" in tools/gen_screens.py SCREENS
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
        jr nc, .ic              ; colours; 4: the icons' sprite layers
        ld a, (vgl_base)
        ld de, VGL_PT
        ld bc, VGL_TILES*8
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
        jr .job
.ic:    ld hl, VR_SPT + VGL_SPRS*32
        ld de, VGL_IPT
        ld bc, VGL_ILAY*32
        cp 3
        jr z, .job
        ld bc, 0                ; (step 5: nothing left)
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
; Each is drawn as the arcade draws it, in its colours: one one-colour sprite
; per arcade pen (up to 3, stacked at its place; the lines are 16 px apart,
; so at most 3 sprites share a line). VERY GOOD: SAT entries 10.. after the
; picture's 10; WONDERFUL (ico_tick): from entry 0. Then the end.
ico_on          equ vgl_on + 42     ; WONDERFUL: icons up (the sprite pass waits)
ico_step        equ vgl_on + 43     ;   0 = layers not uploaded yet
scr_xoff        equ vgl_on + 55     ; render.asm: a centred screen's x offset (tiles)
        assert scr_xoff < $2F00
        assert high ARC_SPRITES == high (ARC_SPRITES + 127)
vgl_icons:
        ld hl, VR_SAT + 40
; HL = VRAM of the first SAT entry to use; VGL_BANK mapped. Clobbers all.
icons_out:
        call vdp_set_write
        ld hl, ARC_SPRITES
        ld b, 32
.c:     push bc
        push hl
        call vgl_icon           ; A = reason, D = SAT y, E = x (carry: none)
        call nc, .emit
        pop hl
        pop bc
        inc l                   ; (ARC_SPRITES + 128 stays in one page)
        inc l
        inc l
        inc l
        inc l                   ; Y of the entry = 0: the queue's end
        ld a, (hl)
        dec l
        or a
        jr z, .end
        djnz .c
.end:   ld a, SAT_END
        out (VDP_DATA), a
        ret
.emit:  ld c, a                 ; C = reason * 3 = its first layer
        add a, a
        add a, c
        ld c, a
        ld b, 3
.l:     ld a, c
        add a, low VGL_ICOL
        ld l, a
        ld h, high VGL_ICOL
        ld a, (hl)              ; colour (0: no such layer)
        or a
        jr z, .nx
        ld h, a
        ld a, d                 ; (writes >= 30 T apart: the display is on)
        out (VDP_DATA), a
        ld a, e
        push hl
        pop hl
        out (VDP_DATA), a
        ld a, c                 ; name = (VGL_SPRS + layer) * 4
        add a, VGL_SPRS
        add a, a
        add a, a
        nop
        out (VDP_DATA), a
        ld a, h
        push hl
        pop hl
        out (VDP_DATA), a
.nx:    inc c
        djnz .l
        ret

; HL -> a sprite RAM entry (code, Y, colour, X): an icon? A = reason 0-3,
; D = its SAT y, E = its x; carry if not (or off the screen).
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
        ld b, a
        ld a, (scr_xoff)        ; (a centred screen: 4 tiles right, 256 - Y)
        or a
        ld a, b
        jr z, .x0
        neg
        jr .xk
.x0:    cpl
        sub 31
        jr c, .no
.xk:    add a, 8                ; a column of space after the stats (user)
        jr c, .no
        ld e, a
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
        dec a                   ; the TMS9918 draws one line below Y
        cp SAT_END
        jr nz, .y
        inc a
.y:     ld d, a
        ld a, c
        or a
        ret
.no:    scf
        ret

; From check_screens: WONDERFUL (its SCENE line's icon) starts.
ico_check:
        ld a, (scr)
        cp WONDER_SCR
        ret nz
        ld a, 1
        ld (ico_on), a
        xor a
        ld (ico_step), a
        ret

; Each vblank while WONDERFUL is up, in the sprite pass's place: the layers
; into the sprite patterns once (the SAT emptied first), then the icons.
ico_tick:
        ld a, VGL_BANK
        call select_bank
        ld a, (ico_step)
        or a
        jr nz, .run
        ld hl, VR_SAT
        call vdp_set_write
        ld a, SAT_END
        out (VDP_DATA), a
        ld hl, VR_SPT + VGL_SPRS*32
        call vdp_set_write
        ld hl, VGL_IPT
        ld bc, VGL_ILAY*32
.w:     ld a, (hl)              ; 43 T a byte
        out (VDP_DATA), a
        inc hl
        dec bc
        ld a, b
        or c
        jr nz, .w
        ld a, 1
        ld (ico_step), a
        ret
.run:   ld hl, VR_SAT
        jp icons_out

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
        push hl
        ld hl, vgl_on
        ld a, (ico_on)          ; (or WONDERFUL's icons)
        or (hl)
        pop hl
        ret z
        xor a
        ld (vgl_on), a
        ld (ico_on), a
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
