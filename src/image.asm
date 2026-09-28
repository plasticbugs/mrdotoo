; =============================================================================
; image.asm - full-screen images from the CV romhack (tools/gen_images.py)
; =============================================================================
; A screen whose scr_index entry names an image bank (byte 13) is shown as that
; image instead of through the tile renderer: patterns, colours, both name
; tables, the image's own sprites; the sprite pass and the cell drawing pause
; (the arcade keeps running, its video RAM is simply not shown). EXTRA: the
; flag animation swaps two 4x5 name blocks every 8 vblanks and shows / hides
; sprite 0. Leaving clears both name tables (the HUD columns would keep image
; tiles) and the sprite cache (the image's sprites used its slots).
; =============================================================================
MODE_IMAGE      equ 3
IMG_BANK_EXTRA  equ MC_FIXED-2
IMG_PT          equ $C000
IMG_CT          equ $C800
IMG_PNT         equ $D000
IMG_SPT         equ $D300
IMG_SAT         equ $D600
IMG_FR1         equ $D680
IMG_FR2         equ $D694
FLAG_COL        equ 13
FLAG_ROW        equ 17

; A = image bank.
image_show:
        ld (img_bank), a
        call select_bank
        ld a, VDP_R1_ON & ~$40  ; blanked: writes may come back to back
        ld c, 1
        call vdp_reg
        ld hl, VR_PT
        ld de, IMG_PT
        ld bc, $800
        call image_copy
        ld hl, VR_CT
        ld de, IMG_CT
        ld bc, $800
        call image_copy
        ld a, (pnt_front)
        call img_names
        ld a, (pnt_back)
        call img_names
        ld hl, VR_SPT
        ld de, IMG_SPT
        ld bc, 22*32
        call image_copy
        ld a, (img_d)
        call img_sat
        xor a
        ld (img_phase), a
        ld a, $FF
        ld (img_brow), a
        ld a, MODE_IMAGE
        ld (mode), a
        ld a, VDP_R7
        ld c, 7
        call vdp_reg
        ld a, VDP_R1_ON
        ld c, 1
        jp vdp_reg

; HL = VRAM address, DE = source, BC = count (display blanked).
image_copy:
        call vdp_set_write
        ex de, hl
.l:     ld a, (hl)
        out (VDP_DATA), a
        inc hl
        dec bc
        ld a, b
        or c
        jr nz, .l
        ret

; Each vblank in image mode: the flag, every 8 vblanks.
image_tick:
        ld a, (img_bank)
        call select_bank
        ld a, (img_d)
        or a
        jp nz, img_pan
        ld a, (frame_cnt)
        and 7
        ret nz
        ld a, (img_phase)
        xor 1
        ld (img_phase), a
        ld de, IMG_FR1
        ld b, 2 + FLAG_ROW*8    ; sprite 0 shown
        jr nz, .fr
        ld de, IMG_FR2
        ld b, $D1               ; hidden (below the screen)
.fr:    push bc
        ld a, (pnt_front)       ; 5 rows of 4 names at (FLAG_COL, FLAG_ROW)
        ld h, a
        ld l, 0
        ld bc, FLAG_ROW*32 + FLAG_COL
        add hl, bc
        ld c, 5
.row:   call vdp_set_write
        ld b, 4
.n:     ld a, (de)              ; (spaced: the display is on)
        out (VDP_DATA), a
        inc de
        nop
        nop
        djnz .n
        push de
        ld de, 32
        add hl, de
        pop de
        dec c
        jr nz, .row
        ld hl, VR_SAT
        call vdp_set_write
        pop bc
        ld a, b
        out (VDP_DATA), a
        ret

; -----------------------------------------------------------------------------
; EXTRA's pan. The arcade opens the scene by setting its background scroll to
; 224, then scrolls 64 pixels (to 32) at half a pixel a frame, bringing the
; dinosaur in from the right under the fixed text. The romhack's picture is
; shown from that first frame (extra_check) with its landscape rows shifted
; right by img_d tiles (8, each row's leftmost picture column repeated in the
; gap), and follows the scroll in tile steps: each step is written into the
; hidden name table a few rows a vblank, then shown by flipping R2. The flag
; waves once the pan is over.
IMG_PAN_ROW0    equ 6           ; rows below the text
IMG_COL0        equ 5           ; the picture's columns (black frame around)
IMG_COL1        equ 26
IMG_PAN         equ 8           ; tiles
EXTRA_SCROLL0   equ 224
WHY_EXTRA       equ 4           ; arcade $E0C7: why the round ended

; From render_body: the arcade has just started the EXTRA scene?
extra_check:
        ld a, (mode)
        cp MODE_IMAGE
        ret z
        ld a, (ARC_WORK + $0C7)
        cp WHY_EXTRA
        ret nz
        ld a, (IO_SCROLL_Y)
        cp EXTRA_SCROLL0
        ret nz
        call leave_image        ; (a VERY GOOD picture, if any)
        ld a, IMG_PAN
        ld (img_d), a
        ld a, IMG_BANK_EXTRA
        jp image_show

; A = name table high byte: all 24 rows, the landscape shifted by img_d.
img_names:
        ld h, a
        ld l, 0
        ld de, IMG_PNT
        ld b, 24
.r:     push bc
        ld a, 24
        sub b                   ; row
        cp IMG_PAN_ROW0
        ld c, 0
        jr c, .s
        ld a, (img_d)
        ld c, a
.s:     call img_row
        ld bc, 32
        add hl, bc
        ex de, hl
        add hl, bc
        ex de, hl
        pop bc
        djnz .r
        ret

; HL = VRAM row, DE = picture row, C = shift: 32 names (spaced). Preserves
; BC, DE, HL.
img_row:
        push bc
        push hl
        call vdp_set_write
        ld b, 0
.c:     ld a, b
        cp IMG_COL0
        jr c, .as
        cp IMG_COL1 + 1
        jr nc, .as
        sub c
        jr c, .fill
        cp IMG_COL0
        jr nc, .src
.fill:  ld a, IMG_COL0
.src:   ld l, a
        jr .get
.as:    ld l, b
.get:   ld h, 0
        add hl, de
        ld a, (hl)
        out (VDP_DATA), a
        inc b
        ld a, b
        cp 32
        jr nz, .c
        pop hl
        pop bc
        ret

; A = shift: the picture's 22 sprites moved with the landscape (those pushed
; past the picture's right edge hidden); sprite 0 (the flag) stays hidden
; until the flag waves.
img_sat:
        add a, a
        add a, a
        add a, a
        ld c, a                 ; pixels
        ld hl, VR_SAT
        call vdp_set_write
        ld hl, IMG_SAT
        ld b, 22
.e:     ld a, (hl)              ; Y
        inc hl
        ld e, a
        ld a, b
        cp 22
        jr nz, .y
        ld e, $D1               ; sprite 0: hidden (not the $D0 terminator)
.y:     ld a, (hl)              ; X
        inc hl
        add a, c
        jr c, .hide
        cp (IMG_COL1 + 1) * 8 - 8
        jr c, .x
.hide:  ld e, $D1
.x:     ld d, a
        ld a, e
        out (VDP_DATA), a
        ld a, d
        nop
        out (VDP_DATA), a
        ld a, (hl)
        inc hl
        nop
        out (VDP_DATA), a
        ld a, (hl)
        inc hl
        nop
        out (VDP_DATA), a
        djnz .e
        ld a, SAT_END
        out (VDP_DATA), a
        ret

; Each vblank while the pan runs (image bank mapped).
img_pan:
        ld a, (img_brow)
        cp $FF
        jr nz, .build
        ld a, (img_d)           ; start the next step in the hidden table
        dec a
        ld (img_bd), a
        ld a, IMG_PAN_ROW0
        ld (img_brow), a
.build: cp 24
        jr nc, .ready
        ld b, 3                 ; 3 rows a vblank
.row:   push bc
        ld a, (img_brow)
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        push hl
        ld de, IMG_PNT
        add hl, de
        ex de, hl
        pop hl
        ld a, (pnt_back)
        add a, h
        ld h, a
        ld a, (img_bd)
        ld c, a
        call img_row
        ld a, (img_brow)
        inc a
        ld (img_brow), a
        pop bc
        cp 24
        ret nc
        djnz .row
        ret
.ready: ld a, (IO_SCROLL_Y)     ; shown when the arcade's scroll gets there:
        sub EXTRA_SCROLL0       ; step = (71 - (scroll - 224)) / 8
        cp IMG_PAN * 8 + 1
        jr c, .p
        ld a, IMG_PAN * 8
.p:     ld b, a
        ld a, IMG_PAN * 8 + 7   ; (rounded up: a step never runs ahead)
        sub b
        rrca
        rrca
        rrca
        and $1F
        ld b, a                 ; the step the scroll is at
        ld a, (img_bd)
        cp b
        ret c                   ; not yet
        ld (img_d), a
        ld a, (pnt_back)        ; show it
        ld b, a
        ld a, (pnt_front)
        ld (pnt_back), a
        ld a, b
        ld (pnt_front), a
        rrca
        rrca
        and $3F
        ld c, 2
        call vdp_reg
        ld a, (img_d)
        call img_sat
        ld a, $FF
        ld (img_brow), a
        ld a, (img_d)           ; the last step: both tables must match for
        or a                    ; the flag animation (it writes the front)
        ret nz
        ld a, (pnt_back)
        jp img_names

; Called where a new screen or playfield takes over: if an image was up,
; clear both name tables and the sprites, and leave the display blanked.
leave_image:
        call vgl_leave
        ld a, (mode)
        cp MODE_IMAGE
        ret nz
        push bc
        push de
        push hl
        ld a, VDP_R1_ON & ~$40
        ld c, 1
        call vdp_reg
        ld a, (pnt_front)
        ld h, a
        ld l, 0
        call .clear
        ld a, (pnt_back)
        ld h, a
        ld l, 0
        call .clear
        ld hl, VR_SAT
        call vdp_set_write
        ld a, SAT_END
        out (VDP_DATA), a
        call sprites_init
        ld a, $FF
        ld (spr_cam), a         ; the next sprite pass runs
        ld a, VDP_R7            ; stays blanked, black, until the next tile
        ld c, 7                 ; set is up (upload_set turns it back on):
        call vdp_reg            ; the cleared names would show the image's
        pop hl                  ; tile 0 (its grass)
        pop de
        pop bc
        ret
.clear: call vdp_set_write
        ld bc, 768
.c:     xor a
        out (VDP_DATA), a
        dec bc
        ld a, b
        or c
        jr nz, .c
        ret
