; =============================================================================
; live.asm - a playfield tile set changed with the display on
; =============================================================================
; Between two playfield sets (a level look <-> the chomper session, a dessert
; pickup) the classic path blanks the display for the upload (3.5 KB at full
; speed, ~1 frame of flat colour). The picture on screen uses only ~20-30 of
; the set's codes, so instead:
;   1. the new picture is drawn into the hidden name table as usual (the old
;      one stays on screen); when it is complete (and the queue drained into
;      it), live_try reads its playfield names back and marks the codes it
;      uses (LIVE_MAP);
;   2. at the start of the next NMI, inside the vertical blank, live_vblank
;      writes just those codes' patterns and colours back to back and flips
;      the name tables: the new picture appears at once;
;   3. the rest of the set goes up in the following vblanks (live_tick,
;      spaced: those codes are not on screen). A cell the arcade draws with
;      a code still pending gets it first (live_out, draw_cell); a full
;      redraw finishes the rest before it starts (live_finish).
; LIVE_MAP then means "written": a code is pending while its bit is clear.
; Codes 164-171 (the dessert score's half, the HUD glyphs) and 176-179 (the
; plate) are left alone: the HUD keeps its glyphs, and render reloads the
; plate / score tiles from the new set (plate_food / score_have).
; A picture with more than LIVE_MAX codes takes the blanked upload.
; =============================================================================
LIVE_MAP        equ SCN_BUF + SCN_BUF_MAX   ; 32 bytes: a bit per code, the arcade's
LIVE_MAX        equ 24                      ; stack area (never used, masked by
        assert LIVE_MAP + 32 <= $6B00       ; tools/diff/compare.py)
        assert high LIVE_MAP == high (LIVE_MAP + 31)
live_state      equ vgl_on + 45             ; 1: armed (the next NMI switches)
live_bpt        equ vgl_on + 46             ; (2) the set's patterns in ROM
live_bct        equ vgl_on + 48             ; (2) and colours
live_rem        equ vgl_on + 50             ; codes still pending (0: none)
live_cur        equ vgl_on + 51             ; live_tick's next code
live_va         equ vgl_on + 52             ; (2) draw_cell's VRAM address
        assert live_va + 1 < $2F00
LIVE_CHUNK      equ 40                      ; codes a vblank (live_tick)

; From render's .show with a set upload pending: carry if the switch was
; armed (the flip and the upload happen at the next vblank), else NC (do the
; blanked upload). Clobbers everything.
live_try:
        call live_finish        ; (a previous switch's rest, if any)
        ld a, (mode)
        cp MODE_PLAYFIELD
        jr nz, .no
        ld a, (up_black)        ; (from a screen or an image: the classic path)
        or a
        jr nz, .no
        ld a, (hud_ok)          ; (the HUD glyphs must be up)
        or a
        jr z, .no
        ld a, (cur_bank)        ; the new set's count (live_skip)
        push af
        ld a, (up_bank)
        call select_bank
        ld hl, (up_set)
        ld a, (hl)
        ld (up_len), a
        pop af
        call select_bank
        call live_scan          ; A = codes to write in the vertical blank
        cp LIVE_MAX + 1
        jr nc, .no
        ld a, 1
        ld (live_state), a
        scf
        ret
.no:    xor a
        ret

; The hidden name table's playfield cells (24 x 24) -> LIVE_MAP, without the
; codes the switch never writes; A = how many are marked. Spaced reads.
live_scan:
        ld hl, LIVE_MAP
        ld b, 32
.clr:   ld (hl), 0
        inc hl
        djnz .clr
        ld a, (pnt_back)
        ld h, a
        ld l, 0
        ld c, PF_ROWS
.row:   push hl
        ld a, l                 ; read address
        out (VDP_CTRL), a
        ld a, h
        and $3F
        out (VDP_CTRL), a
        ld b, 24
.cell:  in a, (VDP_DATA)        ; (>= 30 T apart)
        push bc
        call live_bit           ; HL -> the byte, B = the bit
        ld a, (hl)
        or b
        ld (hl), a
        pop bc
        djnz .cell
        pop hl
        ld de, 32
        add hl, de
        call late_ack
        dec c
        jr nz, .row
        ld e, 0
        ld d, 0
.cnt:   ld a, e
        call live_bit
        ld a, (hl)
        and b
        jr z, .cn
        ld a, e
        call live_skip
        jr z, .cx
        inc d
        jr .cn
.cx:    ld a, b                 ; (not written by the switch: unmarked)
        cpl
        and (hl)
        ld (hl), a
.cn:    inc e
        jr nz, .cnt
        ld a, d
        ret

; A = code -> HL -> its LIVE_MAP byte, B = its bit. Preserves C, DE.
live_bit:
        ld b, a
        and 7
        ld hl, live_bits
        add a, l
        ld l, a
        jr nc, .n
        inc h
.n:     ld a, (hl)
        ld l, b
        ld b, a
        ld a, l
        rrca
        rrca
        rrca
        and $1F
        add a, low LIVE_MAP
        ld l, a
        ld h, high LIVE_MAP
        ret
live_bits:      db 1, 2, 4, 8, 16, 32, 64, 128

; A = code: Z if the switch never writes it (past the set's count, the score
; half / HUD glyphs 164-171, the plate 176-179). Preserves BC, DE, HL.
live_skip:
        push hl
        ld hl, up_len
        cp (hl)
        pop hl
        jr nc, .z
        cp 164
        jr c, .nz
        cp 172
        jr c, .z
        cp 176
        jr c, .nz
        cp 180
        jr c, .z
.nz:    or 1
        ret
.z:     xor a
        ret

; First thing in a (not nested) NMI: an armed switch happens now. Clobbers
; AF, BC, DE, HL.
live_vblank:
        ld a, (live_state)
        or a
        ret z
        xor a
        ld (live_state), a
        ld a, (up_pending)      ; (still the same switch, its picture ready?)
        or a
        ret z
        ld a, (redraw_all)
        or a
        ret nz
        ld a, (rd_row)
        cp PF_ROWS
        ret c
        ld a, (cur_bank)
        push af
        ld a, (up_bank)
        call select_bank
        ld hl, (up_set)         ; the set's patterns and colours
        inc hl
        inc hl
        ld (live_bpt), hl
        ld de, SET_MAX*8
        add hl, de
        ld (live_bct), hl
        ld hl, LIVE_MAP         ; the picture's codes, back to back (the
        ld e, 0                 ; vertical blank: the map walked a byte at a
.p1:    ld a, (hl)              ; time, E = the byte's first code)
        or a
        jr z, .n1
        push hl
        ld d, a                 ; D = its bits
.b1:    srl d
        call c, live_fast       ; code E
        inc e
        ld a, e
        and 7
        jr nz, .b1
        pop hl
        jr .n1b
.n1:    ld a, e
        add a, 8
        ld e, a
.n1b:   inc l
        ld a, l
        cp low (LIVE_MAP + 32)
        jr nz, .p1
        call flip_pnt           ; the new picture
        ld a, 1                 ; the rest from now on (live_tick); the apple
        ld (live_rem), a        ; tiles first (apples.asm writes them as names
        xor a                   ; directly)
        ld (live_cur), a
        ld e, APPLE_BASE
.ap:    ld a, e
        call live_need
        inc e
        ld a, e
        cp APPLE_BASE + 4
        jr nz, .ap
        xor a
        ld (up_pending), a
        ld a, $FF               ; the plate and the score tile: from the new
        ld (plate_food), a      ; set (render reloads them)
        ld (score_have), a
        pop af
        call select_bank
        jp hud_redraw           ; (as after any full redraw: HUD cells written
                                ; during the arcade's bulk repaint were counted)

; Code E's 8 pattern and 8 colour bytes back to back (the vertical blank),
; from live_bpt / live_bct (the set's bank mapped). Preserves DE.
live_fast:
        ld l, e
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl              ; HL = code * 8
        ld c, VDP_CTRL
        out (c), l              ; pattern address
        ld a, h
        or $40
        out (c), a
        push de
        ex de, hl               ; DE = code * 8
        ld hl, (live_bpt)
        add hl, de
        ld c, VDP_DATA
        outi
        outi
        outi
        outi
        outi
        outi
        outi
        outi
        ld c, VDP_CTRL
        out (c), e              ; colour address: VR_CT + code * 8
        ld a, d
        or high VR_CT | $40
        out (c), a
        ld hl, (live_bct)
        add hl, de
        ld c, VDP_DATA
        outi
        outi
        outi
        outi
        outi
        outi
        outi
        outi
        pop de
        ret

; A = code: if the switch still owes it, write it now (spaced) and mark it.
; The set's bank must be mapped. Leaves the VDP address elsewhere.
; Preserves DE.
live_need:
        ld c, a
        call live_skip
        ret z
        ld a, c
        call live_bit
        ld a, (hl)
        and b
        ret nz                  ; written already
        ld a, (hl)
        or b
        ld (hl), a
        ld a, c
        ; fall through
; A = code: its 8 pattern and 8 colour bytes, spaced (>= 30 T a byte), from
; live_bpt / live_bct. Preserves DE.
live_slow:
        push de
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ex de, hl               ; DE = code * 8
        ld a, e
        out (VDP_CTRL), a
        ld a, d
        or $40
        out (VDP_CTRL), a
        ld hl, (live_bpt)
        add hl, de
        call .w8
        ld a, e
        out (VDP_CTRL), a
        ld a, d
        or high VR_CT | $40
        out (VDP_CTRL), a
        ld hl, (live_bct)
        add hl, de
        call .w8
        pop de
        ret
.w8:    ld c, VDP_DATA
        ld b, 8
.s:     outi
        nop
        nop
        nop
        jp nz, .s
        ret

; Each vblank from render while codes are pending: the next LIVE_CHUNK of
; them. Clobbers everything.
live_tick:
        ld a, (live_rem)
        or a
        ret z
        ld a, (cur_bank)
        push af
        ld a, (up_bank)
        call select_bank
        ld a, (live_cur)
        ld e, a
        ld d, LIVE_CHUNK
.c:     ld a, e
        call live_need
        call late_ack
        inc e
        jr z, .end              ; all 256 codes looked at
        dec d
        jr nz, .c
        ld a, e
        ld (live_cur), a
        jr .out
.end:   xor a
        ld (live_rem), a
.out:   pop af
        jp select_bank

; Every pending code now (a full redraw is about to start). Clobbers
; everything.
live_finish:
        ld a, (live_rem)
        or a
        ret z
        call live_tick
        jr live_finish

; draw_cell's playfield cell: A = its code, the VDP address set (also in
; live_va). A pending code is written first, then the address set again.
live_out:
        push af
        ld a, (live_rem)
        or a
        jr nz, .chk
        pop af
        out (VDP_DATA), a
        ret
.chk:   ld a, (cur_bank)        ; (draw_cell maps the code tables' bank)
        push af
        ld a, (up_bank)
        call select_bank
        pop bc                  ; B = the caller's bank
        pop af                  ; A = code
        push bc
        push af
        call live_need
        pop af
        pop bc
        push af
        ld a, b
        call select_bank
        ld hl, (live_va)
        call vdp_set_write
        pop af
        out (VDP_DATA), a
        ret
