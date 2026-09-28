; =============================================================================
; opt.asm - slow paths of the arcade's hot loops rewritten in place
; =============================================================================
; tools/patch_arcade.py (speed_patches) rewrites hot arcade loops at their own
; addresses with faster code that has the same RAM effects; the rare paths
; call in here through this jump table (entry k at OPT_BASE + 3k). `make
; validate` compares the arcade work RAM with MAME's every frame.
; =============================================================================
OPT_BASE        equ $BD00       ; (tools/patch_arcade.py OPT_BASE)

opt_table:
        assert $ == OPT_BASE
        jp opt_snd_slot         ; +0 sound tick $5A90
        jp opt_spr_copy         ; +3 the handler's sprite RAM copy ($00C8)
        jp opt_next_98          ; +6 alpha_advance loop tail $420D
        jp snd_w1               ; +9 ld ($9801),a at $5AE7 (sound.asm)
        jp snd_w2               ; +12 ld ($9802),a at $5AEE
        jp fill_046c            ; +15 video fill $046D (attr A, tile $29)

; Sound tick: HL -> a request-flag byte with bit 0, 1 or 2 set, B = the
; loop count. The original three tests, in their order, with IX = the byte
; (the called routines use IX and B). Preserves HL, B.
opt_snd_slot:
        push hl
        push hl
        pop ix
        bit 2, (ix+0)
        call nz, $5AF6
        bit 0, (ix+0)
        call nz, $5B1D
        bit 1, (ix+0)
        call nz, $5AF6
        pop hl
        ret

; The handler's sprite RAM copy, and a flag for sprites_update: vblanks with
; no new sprite data keep the SAT as it is (an overrunning handler then gets
; the time back).
opt_spr_copy:
        call $026D
        push af
        ld a, 1
        ld (spr_new), a
        pop af
        ret

; Object-table scan loop tails (patched `add iy,de / djnz body`). Same two
; instructions first, so the loop exits exactly as before. Then objects that
; cannot match are passed over through HL (38-45 T instead of 66), and the
; original body takes the next candidate, or the last object in any case.
; IY -> object, B = objects left including it (the original's count), DE = 7.
; Preserves HL.
opt_next_98:                    ; alpha_advance ($41D6): state == $98
        add iy, de
        djnz .more
        jp $4211
.more:  push hl
        push iy
        pop hl
        dec b                   ; B-1 objects may be passed over
        jr z, .take
        ld a, $98
.l:     cp (hl)
        jr z, .take
        add hl, de
        djnz .l
.take:  inc b
        push hl
        pop iy
        pop hl
        jp $41EC

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
