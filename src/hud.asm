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
HUD_STATIC      equ HUD_DATA + $B00
HUD_CELLS       equ HUD_DATA + $B40
HUD_BASE        equ 180             ; = tools/gen_hud.py HUD_BASE
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
        jr nz, hud_put
.blank: ld a, HUD_BASE
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
        pop hl
        jr .c
.done:  pop af
        jp select_bank

; Display blanked (upload_set): the glyphs into codes HUD_BASE.., the panel
; cleared in both name tables, then drawn. Clobbers everything.
hud_upload:
        ld a, HUD_BANK
        call select_bank
        ld hl, VR_PT + HUD_BASE*8
        ld de, HUD_PAT
        call .tbl
        ld hl, VR_CT + HUD_BASE*8
        ld de, HUD_COL
        call .tbl
        ld a, HUD_BASE
        call hud_clear
        jr hud_redraw
.tbl:   call vdp_set_write
        ex de, hl
        ld bc, HUD_N*8
.t:     ld a, (hl)
        out (VDP_DATA), a
        inc hl
        dec bc
        ld a, b
        or c
        jr nz, .t
        ret

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
