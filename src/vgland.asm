; =============================================================================
; vgland.asm - VERY GOOD: the romhack's picture once the characters land
; =============================================================================
; The VERY GOOD cutscene scrolls Mr. Do, the apple and the dinosaur in with
; the arcade's own tiles (scene.asm), whose colours clash on the TMS9918.
; When the scroll is back at 0 (they have landed, ~3.6 s before the scene
; ends) this puts the CV romhack's picture of the same three in their place
; (tools/gen_images.py vgland): its tiles in the slot bank that is not on
; screen, 14 x 5 names at (VGL_COL, VGL_ROW), and its 10 sprites (some black,
; covering tile pixels); two frames swapped every 8 vblanks. Band builds and
; the sprite pass pause meanwhile; leaving the screen gives the sprite cache
; back (vgl_leave, as leave_image).
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
; Variables: the driver's area is full; these sit after SCN_LIST in the
; same unused arcade padding (cleared by render_init).
vgl_on          equ SCN_LIST + SCN_SLOTS    ; the picture is up
vgl_armed       equ vgl_on + 1      ; the VERY GOOD band has scrolled
vgl_step        equ vgl_on + 2      ; upload step
vgl_done        equ vgl_on + 3      ; bytes of the step done (2)
vgl_base        equ vgl_on + 5      ; first tile code
vgl_phase       equ vgl_on + 6      ; frame
nmi_late        equ vgl_on + 7      ; main.asm: an overrunning NMI owes the VDP ack
        assert nmi_late < $2F00

; From scene_update (a screen with a band): NZ while the picture is up (no
; band builds then). Starts it once the VERY GOOD scroll has come back to 0
; and the band is idle with its scroll-0 build out. Clobbers AF, B.
vgl_check:
        ld a, (vgl_on)
        or a
        ret nz
        ld a, (scr)
        cp VG_SCR
        jr nz, .off
        ld a, (IO_SCROLL_Y)
        or a
        jr z, .zero
        ld a, 1                 ; scrolling: armed for the landing
        ld (vgl_armed), a
        xor a
        ret
.zero:  ld a, (vgl_armed)
        or a
        ret z
        ld a, (scn_brow)
        ld b, a
        ld a, (scn_ready)
        or b
        ld b, a
        ld a, (scn_flush2)
        or b
        ld b, a
        ld a, (scn_scroll)
        or b
        jr nz, .no              ; the landed band not out yet
        ld (vgl_armed), a
        ld (vgl_step), a
        ld (vgl_done), a
        ld (vgl_done+1), a
        ld a, (scn_bank)        ; the bank on screen: use the other one
        or a
        ld a, (scn_base)
        jr nz, .b
        add a, SCN_SLOTS
.b:     ld (vgl_base), a
        ld a, 1
        ld (vgl_on), a
        or a
        ret
.off:   xor a
        ld (vgl_armed), a
        ret
.no:    xor a
        ret

; From scene_vblank while the picture is up (VDP access allowed).
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
        jr nc, .names
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
.names: cp 5
        jr nc, .anim
        ld a, 5                 ; step 4: the picture, frame 1
        ld (vgl_step), a
        xor a
        ld (vgl_phase), a
        ld hl, VGL_FR1
        ld b, VGL_ROW
        ld c, 5
        call vgl_rows
        ld hl, VGL_SAT1
        jr vgl_sat
.anim:  ld a, (frame_cnt)       ; then the two frames, 8 vblanks each
        and 7
        ret nz
        ld a, (vgl_phase)
        xor 1
        ld (vgl_phase), a
        ld hl, VGL_FR2
        ld de, VGL_SAT2
        jr nz, .f
        ld hl, VGL_FR1 + 3*14
        ld de, VGL_SAT1
.f:     push de
        ld b, VGL_ROW + 3       ; rows 3-4 of the block change
        ld c, 2
        call vgl_rows
        pop hl
        ; fall through
; HL = 41 bytes of SAT (10 sprites + terminator).
vgl_sat:
        push hl
        ld hl, VR_SAT
        call vdp_set_write
        pop hl
        ld b, 41
.s:     ld a, (hl)
        out (VDP_DATA), a
        inc hl
        nop
        nop
        djnz .s
        ret

; HL = romhack names (14 per row), B = first screen row, C = rows: the rows'
; 24 band columns into both name tables (the block at VGL_COL, black around).
vgl_rows:
.row:   push bc
        push hl
        ld a, (pnt_front)
        call .one
        pop hl
        push hl
        ld a, (pnt_back)
        call .one
        pop hl
        ld de, 14
        add hl, de
        pop bc
        inc b
        dec c
        jr nz, .row
        ret
.one:   push hl                 ; A = table high byte, B = row
        ld l, b
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add a, h
        ld h, a
        call vdp_set_write
        pop hl
        ld c, 24
        ld e, 0                 ; column
.c:     ld a, e
        sub VGL_COL
        cp 14
        ld a, 0
        jr nc, .out             ; outside the block: black
        ld a, (hl)
        inc hl
        or a
        jr z, .out
        dec a
        ld d, a
        ld a, (vgl_base)
        add a, d
.out:   out (VDP_DATA), a
        inc e
        dec c
        jr nz, .c
        ret

; A new screen or the playfield takes over: if the picture was up, hide its
; sprites and give the sprite cache back. Preserves BC, DE, HL.
vgl_leave:
        xor a
        ld (vgl_armed), a
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
