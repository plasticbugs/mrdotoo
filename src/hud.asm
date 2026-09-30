; =============================================================================
; hud.asm - the HUD panel (screen columns 24-31) and the dessert plate tiles
; =============================================================================
; The arcade draws its HUD (score, EXTRA, lives, SCENE, TOP) into video RAM
; strips outside our 24x24 playfield: native columns 29-31 and 0-2. In
; playfield mode each of those cells is mirrored into the right-hand panel,
; MSX2-port layout, as a glyph chosen by its (fg attribute, fg tile)
; (tools/gen_hud.py). Glyphs use codes HUD_BASE-255, which playfield tile
; sets leave alone; upload_set reloads them after every playfield set. The
; panel is written to both name tables, so it survives the redraw flips.
;
; Dessert plates: only one dessert is on the playfield at a time, so its four
; tiles are loaded into codes PLATE_CODE..+3 when it first shows (the set in
; ROM keeps all 48); that freed the codes the HUD uses.
; =============================================================================
HUD_BANK        equ SPR_BANK_W      ; bank 30, after Mr. Do's white overlays
HUD_DATA        equ $E100
HUD_PAT         equ HUD_DATA
HUD_COL         equ HUD_DATA + $300
HUD_CLS         equ HUD_DATA + $600
HUD_MAP         equ HUD_DATA + $700
HUD_GLYPH       equ HUD_DATA + $800
HUD_STATIC      equ HUD_DATA + $B80
HUD_CELLS       equ HUD_DATA + $BC0
HUD_BASE        equ 180             ; = tools/gen_hud.py HUD_BASE
HUD_N0          equ 256 - HUD_BASE  ; glyphs at HUD_BASE.. (then HUD_EXTRA0..)
PLATE_CODE      equ DESSERT_BASE    ; the current dessert's 4 tiles

; DE = a cell in a HUD strip, playfield mode: its glyph into both name
; tables. Clobbers AF, BC, HL; preserves DE and the mapped bank.
hud_cell:
        ld a, (cur_bank)
        push af
        ld a, HUD_BANK
        call select_bank
        call hud_cell_m
        pop af
        jp select_bank

; Same, HUD_BANK mapped.
hud_cell_m:
        ld a, e                 ; strip column: native 0-2 -> 0-2, 29-31 -> 3-5
        and $1F
        cp 3
        jr c, .s
        sub 26
.s:     rrca                    ; * 32
        rrca
        rrca
        ld c, a
        ld a, e                 ; native row = cell >> 5
        and $E0
        or d
        rlca
        rlca
        rlca
        or c
        ld l, a
        ld h, high HUD_MAP
        ld a, (hl)
        cp $FF
        ret z                   ; not shown in the panel
        ld (hud_p), a
        ld hl, ARC_VRAM + $800  ; fg attribute
        add hl, de
        ld b, (hl)
        ld a, h
        add a, 4
        ld h, a
        ld c, (hl)              ; fg tile
        ld a, b
        cp 64
        jr nc, .blank
        ld l, a
        ld h, high HUD_CLS
        ld a, (hl)              ; class 1-6
        or a
        jr z, .blank
        dec a
        ld b, a
        ld a, c
        cp $60
        jr nc, .blank
        ld l, a
        ld a, b                 ; + (class-1) * 128
        rrca
        and $80
        or l
        ld l, a
        ld a, b
        srl a
        add a, high HUD_GLYPH
        ld h, a
        ld a, (hl)
        or a
        jr nz, .mark
.blank: ld a, HUD_BASE
.mark:  ld b, a                 ; the next EXTRA letter: the marker glyph
        ld a, (hud_next)
        cp 5
        jr nc, .put
        add a, HUD_LETTER0
        ld c, a
        ld a, (hud_p)
        cp c
        jr nz, .put
        sub HUD_LETTER0         ; letter i: collected (its glyph is the
        ld c, a                 ; collected one) -> green on blue, else
        add a, a                ; white on blue
        add a, HUD_LIT0
        cp b
        ld a, c
        jr z, .lit
        add a, HUD_MARK
        jr hud_put
.lit:   add a, HUD_MARK2
        jr hud_put
.put:   ld a, b
        ; fall through
; A = code, (hud_p) = panel cell (row*8 + x): write it into both name tables.
; Clobbers AF, BC, HL.
hud_put:
        ld b, a
        ld a, (hud_p)
        and $F8                 ; row*8 -> row*32
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        ld a, (hud_p)
        and 7
        add a, 24
        or l
        ld l, a
        ld a, h
        add a, high VR_PNT
        ld h, a
        call vdp_set_write
        ld a, b
        out (VDP_DATA), a
        ex (sp), hl             ; let the write land before the address
        ex (sp), hl             ; changes (active display: ~30 T a slot)
        ld a, h
        sub high VR_PNT - high VR_PNT2
        ld h, a
        call vdp_set_write
        ld a, b
        out (VDP_DATA), a
        ex (sp), hl
        ex (sp), hl
        ret

; The whole panel: the box frame and every mirrored cell. Playfield mode.
; Clobbers AF, BC, DE, HL; preserves the mapped bank.
hud_redraw:
        ld a, (cur_bank)
        push af
        ld a, HUD_BANK
        call select_bank
        ld hl, HUD_STATIC
.st:    ld a, (hl)
        cp $FF
        jr z, .cells
        ld (hud_p), a
        inc hl
        ld a, (hl)
        inc hl
        push hl
        call hud_put
        pop hl
        jr .st
.cells: ld hl, HUD_CELLS
.c:     ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld a, d
        inc a
        jr z, .done
        push hl
        call hud_cell_m
        call late_ack
        pop hl
        jr .c
.done:  pop af
        jp select_bank

; Display blanked (upload_set): the glyphs into codes HUD_BASE.., the panel
; cleared in both name tables, then drawn. Clobbers everything.
hud_upload:
        ld a, HUD_BANK
        call select_bank
        ld hl, VR_PT + HUD_BASE*8   ; glyphs 0-75 at HUD_BASE.., the rest at
        ld de, HUD_PAT              ; HUD_EXTRA0.. (also free in every
        ld bc, HUD_N0*8             ; playfield set)
        call .tbl
        ld hl, VR_CT + HUD_BASE*8
        ld de, HUD_COL
        ld bc, HUD_N0*8
        call .tbl
        if HUD_N > HUD_N0
        ld hl, VR_PT + HUD_EXTRA0*8
        ld de, HUD_PAT + HUD_N0*8
        ld bc, (HUD_N - HUD_N0)*8
        call .tbl
        ld hl, VR_CT + HUD_EXTRA0*8
        ld de, HUD_COL + HUD_N0*8
        ld bc, (HUD_N - HUD_N0)*8
        call .tbl
        endif
        ld a, 1
        ld (hud_ok), a
        ld a, HUD_BASE
        call hud_clear
        jr hud_redraw
.tbl:   call vdp_set_write
        ex de, hl
.t:     ld a, (hl)
        out (VDP_DATA), a
        inc hl
        dec bc
        ld a, b
        or c
        jr nz, .t
        ret

; A playfield set just went up over another playfield set (display blanked):
; the glyphs at HUD_BASE.. and the panel's names are still there; only the
; ones at HUD_EXTRA0.. (inside the set's range) need writing again.
hud_extra:
        if HUD_N > HUD_N0
        ld a, HUD_BANK
        call select_bank
        ld hl, VR_PT + HUD_EXTRA0*8
        ld de, HUD_PAT + HUD_N0*8
        ld bc, (HUD_N - HUD_N0)*8
        call hud_upload.tbl
        ld hl, VR_CT + HUD_EXTRA0*8
        ld de, HUD_COL + HUD_N0*8
        ld bc, (HUD_N - HUD_N0)*8
        jp hud_upload.tbl
        else
        ret
        endif

; Display blanked: columns 24-31 of both name tables to code A (a screen's
; tile set leaves them to code 0, as before the HUD existed). Clobbers
; everything but A.
hud_clear:
        ld hl, VR_PNT + 24
        call .t
        ld hl, VR_PNT2 + 24
.t:     ld c, 24
.row:   push af
        call vdp_set_write
        pop af
        ld b, 8
.x:     out (VDP_DATA), a
        djnz .x
        ld de, 32
        add hl, de
        dec c
        jr nz, .row
        ret

; The dessert (plate_want = food) into codes PLATE_CODE..+3 from the current
; set in ROM. Spaced writes (the display may be on). Clobbers everything.
plate_load:
        ld a, (plate_want)
        ld (plate_food), a
        add a, a                ; food*4 tiles * 8 bytes = food * 32
        add a, a
        add a, a
        add a, a
        add a, a
        ld e, a
        ld d, 0
        ld hl, 2 + PLATE_CODE*8
        add hl, de
        ex de, hl               ; DE = offset of its patterns in the set
        ld a, (cur_bank)
        push af
        ld a, (up_bank)
        call select_bank
        push de
        ld hl, VR_PT + PLATE_CODE*8
        call .copy
        pop de
        ld hl, SET_MAX*8
        add hl, de
        ex de, hl
        ld hl, VR_CT + PLATE_CODE*8
        call .copy
        pop af
        jp select_bank
.copy:  call vdp_set_write
        ld hl, (up_set)
        add hl, de
        ld b, 32
.b:     ld a, (hl)              ; 37 T a byte
        out (VDP_DATA), a
        inc hl
        djnz .b
        ret

; The next EXTRA letter: the arcade marks it with a letter-monster sprite on
; the box (sprite queue X = $E9, colour 4, Y = $A0 - 12 * letter), which is
; off our playfield. Each vblank: find it, and when the marked letter
; changes, redraw the old and the new letter. Playfield mode.
; Clobbers everything.
hud_scan:
        ld a, (hud_mk)          ; the marker's Y, found by the sprite pass
        or a                    ; (sprites.asm; scanning the queue here cost
        jr z, .none             ; ~1.5k T a vblank)
        ld d, a                 ; letter = ($A0 - Y) / 12
        ld c, $A0
        ld e, 0
.l:     cp c
        jr z, .got
        ld d, a
        ld a, c
        sub 12
        ld c, a
        ld a, d
        inc e
        bit 3, e                ; (never more than 5 steps: stop at 8)
        jr z, .l
.none:  ld e, $FF
.got:   ld a, (hud_next)
        cp e
        ret z
        ld d, a
        ld a, e
        ld (hud_next), a
        ld a, d                 ; old letter, then the new one
        call .cell
        ld a, (hud_next)
.cell:  cp 5
        ret nc
        ld hl, .rows
        add a, l
        ld l, a
        jr nc, .r
        inc h
.r:     ld a, (hl)              ; cell = row * 32 + 29
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, 29
        add hl, de
        ex de, hl
        jp hud_cell
.rows:  db 12, 14, 15, 17, 18   ; the box tile sampled per letter (gen_hud.py)

; The dessert's score (render.asm not_dirt): "00" has code SCORE_BASE, the
; other half (tile score_want, "10"-"80") is loaded into SCORE_BASE + 1 from
; score_tiles (tools/gen_tiles.py score.bin: the same over every colourway).
; Spaced writes. Clobbers everything.
score_load:
        ld a, (score_want)
        ld (score_have), a
        sub $16                 ; tile $16-$21 -> 0-11: 16 bytes each
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, score_tiles
        add hl, de
        push hl
        ld hl, VR_PT + (SCORE_BASE + 1) * 8
        call vdp_set_write
        pop hl
        call .b8
        push hl
        ld hl, VR_CT + (SCORE_BASE + 1) * 8
        call vdp_set_write
        pop hl
.b8:    ld b, 8
.b:     ld a, (hl)
        out (VDP_DATA), a
        inc hl
        nop
        djnz .b
        ret

score_tiles:
        incbin "build/tiles/score.bin"
