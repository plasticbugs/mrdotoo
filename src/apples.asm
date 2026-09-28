; =============================================================================
; apples.asm - resting apples as background tiles (playfield)
; =============================================================================
; A resting apple is a 16x16 sprite the arcade redraws every frame; on the
; TMS9918 each one takes a place in the 4-per-line budget, so on busy rows
; apples (and what shares their lines) flickered. An apple that sits on the
; 8-pixel grid over 2 x 2 cells of plain dirt is drawn with 4 background
; tiles instead (codes APPLE_BASE.., its own sprite pixels over the
; colourway's dirt: tools/gen_tiles.py), and left out of the sprite list.
; The moment it moves, wobbles or the dirt under it is dug, it is a sprite
; again; the sprite pass (sprites.asm) decides per frame, apple_sync redraws
; the cells that changed in the same vblank, so the handover shows no gap.
; Only drawing changes: the arcade still sees its apples as before.
;
; Lists (screen tile column, screen row + cam of the apple's top-left cell:
; the camera can move between the pass and the drawing) live in
; SCN_BUF, which only the cutscene band uses (screen mode); everything here
; runs in playfield mode only.
; =============================================================================
APPLE_BASE      equ 172         ; = tools/gen_tiles.py APPLE_BASE (TL TR BL BR)
APPLE_CODE      equ $5E         ; the resting apple (wobble $5D/$5F: sprites)
APPLE_LINE      equ 5
DIRT_FG         equ $77         ; = tools/gen_tiles.py DIRT_FG
APL_MAX         equ 6
apl_new_n       equ SCN_BUF         ; this pass's tiled apples
apl_new         equ SCN_BUF + 1     ;   (tx, ty) each
apl_cur_n       equ SCN_BUF + 16    ; the ones on screen
apl_cur         equ SCN_BUF + 17
apl_old_n       equ SCN_BUF + 32    ; (apple_sync scratch)
apl_old         equ SCN_BUF + 33
apl_sy          equ SCN_BUF + 48    ; screen row being drawn
apl_rowany      equ SCN_BUF + 49    ;   and whether an apple covers it
apl_inval       equ SCN_BUF + 50    ; a tiled apple's cell was drawn again
        assert apl_inval < SCN_BUF + SCN_BUF_MAX

; Entering the playfield: no apples tiled yet.
apple_reset:
        xor a
        ld (apl_new_n), a
        ld (apl_cur_n), a
        ld (apl_rowany), a
        inc a
        ld (apl_inval), a
        ret

; From the sprite pass (sprites.asm, .yok), for an apple-code sprite: A =
; the sprite's screen y (its top line), HL -> its Y in sprite RAM, DE -> its
; list slot (x stored at +1), B = early clock. Carry: a resting apple drawn
; as tiles (left out of the sprite list). Preserves DE, HL; clobbers BC.
; An apple tiled last pass at the same place and list index skips the dirt
; check unless one of the tiled apples' cells has been drawn since
; (apple_at sets apl_inval: the renderer redraws every cell the arcade
; writes, so a change under an apple always passes there).
        assert high apl_new == high (apl_cur + 2 * APL_MAX)
apple_try:
        push af
        ld a, (mode)
        cp MODE_PLAYFIELD
        jr nz, .no
        ld a, b
        or a
        jr nz, .no              ; (left of the screen)
        inc l
        ld a, (hl)              ; colour line 5, not flipped
        dec l
        and $3F
        cp APPLE_LINE
        jr nz, .no
        pop af
        push af
        ld c, a
        and 7
        jr nz, .no              ; not on the grid
        ld a, c
        cp 177
        jr nc, .no              ; (its lower cells below the playfield)
        rrca                    ; (low 3 bits clear: exactly y / 8)
        rrca
        rrca
        ld b, a
        ld a, (cam)             ; rows are kept camera-free (+ cam): a camera
        add a, b                ; move in the same vblank then cannot shift
        ld b, a                 ; a tiled apple by a row. B = list row
        inc e
        ld a, (de)              ; x
        dec e
        ld c, a
        and 7
        jr nz, .no
        ld a, c
        cp 177
        jr nc, .no
        rrca
        rrca
        rrca
        ld c, a                 ; C = tx
        push hl
        ld a, (apl_new_n)
        cp APL_MAX
        jr nc, .no2
        add a, a
        ld l, a                 ; L = entry offset
        ld a, (apl_inval)
        or a
        jr nz, .chk
        ld a, (apl_cur_n)
        add a, a
        cp l
        jr z, .chk              ; (no entry this far in last pass's list)
        jr c, .chk
        ld a, l
        add a, low apl_cur
        ld l, a
        ld h, high apl_cur
        ld a, (hl)
        cp c
        jr nz, .chk
        inc l
        ld a, (hl)
        cp b
        jr z, .add
.chk:   push de
        call apl_dirt4
        pop de
        jr nz, .no2
.add:   ld hl, apl_new_n
        ld a, (hl)
        inc (hl)
        add a, a
        add a, low apl_new
        ld l, a
        ld h, high apl_new
        ld (hl), c
        inc l
        ld (hl), b
        pop hl
        pop af
        scf
        ret
.no2:   pop hl
.no:    pop af
        or a
        ret

; B = list row (screen row + cam), C = tx: Z if the 4 cells are plain dirt
; (the colourway's dirt bg tile, nothing in front). Screen row + 1 is native column - 1 and screen
; column + 1 native row + 1, so the cells are HL, HL - 1, HL + 31, HL + 32
; (ty <= 22: no column wrap). Preserves BC.
apl_dirt4:
        push bc
        ld e, c
        ld a, (cam)
        neg
        add a, b                ; screen row
        call apl_cell           ; HL = the top-left cell
        ld de, ARC_VRAM + $400
        add hl, de
        ld a, (dirt_tile)
        ld c, a
        ld de, 32
        call .one
        jr nz, .out
        dec hl                  ; HL - 1
        call .one
        jr nz, .out
        add hl, de              ; HL + 31
        call .one
        jr nz, .out
        inc hl
        call .one
.out:   pop bc
        ret
; HL -> a cell's bg tile, C = the dirt tile: Z if plain dirt. Preserves
; HL, DE, C.
.one:   ld a, (hl)
        cp c
        ret nz
        ld a, h
        add a, 8                ; fg tile layer
        ld h, a
        ld b, (hl)
        sub 8
        ld h, a
        ld a, b
        cp DIRT_FG              ; (undug dirt's fg tile)
        ret z
        cp BLANK_BG             ; (or nothing in front)
        ret

; E = screen column, A = screen row -> HL = native cell (row * 32 + column).
; Preserves BC, DE.
apl_cell:
        push bc
        ld c, a
        ld a, (cam)
        add a, c
        cpl
        and $1F                 ; native column = 31 - (row + cam)
        ld c, a
        ld a, e
        add a, 4                ; native row = column + 4
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, l
        or c
        ld l, a
        pop bc
        ret

; A = screen column, apl_sy = screen row: carry and A = the apple tile code
; if a tiled apple covers that cell. Preserves BC, DE, HL.
apple_at:
        push bc
        push hl
        ld c, a
        ld a, (apl_cur_n)
        or a
        jr z, .no
        ld b, a
        ld hl, apl_cur
.l:     ld a, c                 ; dx = sx - tx in 0-1?
        sub (hl)
        cp 2
        jr nc, .n1
        push af
        inc hl
        ld a, (cam)             ; dy = (sy + cam) - row in 0-1?
        push bc
        ld b, a
        ld a, (apl_sy)
        add a, b
        pop bc
        sub (hl)
        dec hl
        cp 2
        jr nc, .n0
        add a, a                ; code = base + dy * 2 + dx
        ld c, a
        pop af
        add a, c
        add a, APPLE_BASE
        ld (apl_inval), a       ; (non-zero)
        pop hl
        pop bc
        scf
        ret
.n0:    pop af
.n1:    inc hl
        inc hl
        djnz .l
.no:    pop hl
        pop bc
        or a
        ret

; A = screen row: set apl_sy, and apl_rowany if a tiled apple covers it.
; Preserves BC, DE, HL.
apple_row:
        ld (apl_sy), a
        push bc
        push hl
        ld c, a
        ld a, (cam)             ; (list rows are + cam)
        add a, c
        ld c, a
        ld a, (apl_cur_n)
        ld b, a
        ld hl, apl_cur + 1
        or a
        jr z, .no
.l:     ld a, c
        sub (hl)
        cp 2
        jr c, .yes
        inc hl
        inc hl
        djnz .l
.no:    xor a
        jr .s
.yes:   ld a, 1
.s:     ld (apl_rowany), a
        pop hl
        pop bc
        ret

; Each vblank on the playfield, after the sprite pass, TBL_BANK mapped: the
; tiled apples changed? Their cells (the ones that became tiles and the ones
; that went back to sprites) are drawn again now, in the vblank the sprites
; change in. Clobbers everything.
apple_sync:
        ld a, (mode)
        cp MODE_PLAYFIELD
        ret nz
        xor a                   ; (redraws below set it again)
        ld (apl_inval), a
        ld hl, apl_new_n        ; same list as on screen? (the usual case)
        ld de, apl_cur_n
        ld a, (hl)
        add a, a
        inc a
        ld b, a
.cmp:   ld a, (de)
        cp (hl)
        jr nz, .diff
        inc hl
        inc de
        djnz .cmp
        ret
.diff:  ld hl, apl_cur_n        ; old = cur, cur = new
        ld de, apl_old_n
        ld bc, 1 + 2 * APL_MAX
        ldir
        ld hl, apl_new_n
        ld de, apl_cur_n
        ld bc, 1 + 2 * APL_MAX
        ldir
        ld hl, apl_old          ; apples gone from the tiles, and new ones
        ld a, (apl_old_n)
        ld de, apl_cur_n
        call .changed
        ld hl, apl_cur
        ld a, (apl_cur_n)
        ld de, apl_old_n
        ; fall through
; HL -> a list of A apples; DE -> the other list (count, entries): redraw the
; cells of every apple not in it.
.changed:
        or a
        ret z
        ld b, a
.e:     push bc
        push de
        push hl
        call .inlist
        jr z, .next
        ld c, (hl)              ; tx
        inc hl
        ld b, (hl)              ; ty
        call apl_redraw4
.next:  pop hl
        pop de
        pop bc
        inc hl
        inc hl
        djnz .e
        ret
; Z if the entry at HL is in the list at DE. Preserves HL.
.inlist:
        ld a, (de)
        or a
        jr z, .nz
        ld b, a
        inc de
.il:    ld a, (de)
        cp (hl)
        inc de
        jr nz, .in
        inc hl
        ld a, (de)
        cp (hl)
        dec hl                  ; (16-bit dec keeps Z)
        ret z
.in:    inc de
        djnz .il
.nz:    or 1
        ret

; B = ty, C = tx: draw its 4 cells again (draw_cell asks apple_at).
apl_redraw4:
        ld d, 0
.r:     ld e, 0
.c:     push bc
        push de
        ld a, c
        add a, e
        ld e, a
        ld a, (cam)             ; screen row = list row - cam + dy
        neg
        add a, b
        add a, d
        cp PF_ROWS
        jr nc, .skip
        call apl_cell
        ex de, hl
        call draw_cell
.skip:  pop de
        pop bc
        inc e
        ld a, e
        cp 2
        jr c, .c
        inc d
        ld a, d
        cp 2
        jr c, .r
        ret
