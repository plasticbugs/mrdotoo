; =============================================================================
; opt_fill.asm - the video fill's slow path (opt.asm's jump table entry +15);
; kept out of the block at OPT_BASE, which has little room before the stubs
; =============================================================================
; Video fill $046D (entered at $046C after `xor a`, or at $046D by $7076):
; C rows of B cells from DE (0 = 256): attribute A at DE, tile $29 at
; DE+$400. Through the video hooks each cell costs ~500 T; the coin-up screen
; clear (1024 + 768 cells) kept the arcade busy for 33 frames. Same loop, same
; pushes, same exit registers and flags; only the stores differ. A fill of
; 8x8+ cells inside video RAM stores directly and asks for a full redraw
; (what the dirty queue overflowing does anyway), holding the renderer off
; (q_busy) until the last row. Other fills, and any fill while a cutscene
; band is live (its cells go to scene_write), take the hooks.
fill_046c:
        push af
        call fill_fast
        jr nz, .hooked
        pop af
.row:   push bc
        push de
        ld hl, $0400
        add hl, de
.cell:  ld (de), a
        ld (hl), $29
        inc de
        inc hl
        djnz .cell
        pop de
        ld hl, redraw_all       ; a bulk repaint under way: redraw once it ends
        ld (hl), 1
        ld hl, q_busy
        ld (hl), $FF
        ld hl, $0020
        add hl, de
        ex de, hl
        pop bc
        dec c
        jr nz, .row
        ret
.hooked:
        pop af
.hrow:  push bc
        push de
        ld hl, $0400
        add hl, de
.hcell: rst $28                 ; ld (de),a
        rst $30                 ; ld (hl),$29
        db $29
        inc de
        inc hl
        djnz .hcell
        pop de
        ld hl, $0020
        add hl, de
        ex de, hl
        pop bc
        dec c
        jr nz, .hrow
        ret

; Z = fill_046c may store directly. Clobbers AF, HL.
fill_fast:
        ld a, (mode)
        cp MODE_SCREEN
        jr nz, .m
        ld a, b                 ; a screen being wiped whole (32 columns, 24+
        cp 32                   ; rows: the arcade clearing it for what comes
        jr nz, .band            ; next)? The display goes black until the next
        ld a, c                 ; tile set is up (render_body, go_black), so
        cp 24                   ; the band no longer matters
        jr c, .band
        ld a, 1
        ld (blank_req), a
        jr .m
.band:  ld a, (scn_pbank)
        or a
        ret nz
.m:     ld a, b                 ; 8+ columns and 8+ rows (0 = 256)
        dec a
        cp 7
        jr c, .no
        ld a, c
        dec a
        cp 7
        jr c, .no
        ld a, d                 ; starts in video RAM ($7000-)
        cp $70
        jr c, .no
        ld a, c                 ; last tile store = DE + $400 + (C-1)*32 + B-1
        dec a
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, b
        dec a
        add a, l
        ld l, a
        adc a, h
        sub l
        ld h, a
        add hl, de
        jr c, .no
        ld a, h                 ; ... <= $7FFF
        cp $7C
        jr nc, .no
        xor a
        ret
.no:    or 1
        ret
