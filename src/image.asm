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
        ld h, a
        ld l, 0
        ld de, IMG_PNT
        ld bc, 768
        call image_copy
        ld a, (pnt_back)
        ld h, a
        ld l, 0
        ld de, IMG_PNT
        ld bc, 768
        call image_copy
        ld hl, VR_SPT
        ld de, IMG_SPT
        ld bc, 22*32
        call image_copy
        ld hl, VR_SAT
        ld de, IMG_SAT
        ld bc, 128
        call image_copy
        xor a
        ld (img_phase), a
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
        ld a, (frame_cnt)
        and 7
        ret nz
        ld a, (img_bank)
        call select_bank
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

; Called where a new screen or playfield takes over: if an image was up,
; clear both name tables and the sprites.
leave_image:
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
        ld a, VDP_R1_ON
        ld c, 1
        call vdp_reg
        pop hl
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
