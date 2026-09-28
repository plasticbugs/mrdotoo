; =============================================================================
; scene.asm - the cutscenes' scrolling band
; =============================================================================
; The arcade scrolls its whole background layer (register $F800, pixels along
; the player-view x axis) under the fixed foreground (text) layer. In the
; cutscenes only a few rows hold background art (the characters), with no
; foreground over them. tools/gen_screens.py pre-shifts every (left, right)
; bg cell pair a scene uses to phases 0, 2, 4, 6; a pair hash gives its id.
;
; The scroll only changes WHICH pair a screen cell shows; what pair sits at a
; native row only changes when the arcade rewrites a tile. So per band row
; this keeps:
;   scn_mask  a 32-bit mask of the native rows holding art;
;   IDC       (VRAM) the pair id + 1 at each native row r: for phase 0 (r
;             alone) and for the other phases (r and r + 1); 0 = nothing.
; Both are filled when a scene starts (a few vblanks, before the first build)
; and patched from the arcade's band writes (scene_write, scene_apply).
;
; A build (two vblanks, half of the band's rows each) gives every cell with
; art the next tile slot of the slot bank that is NOT on screen, notes the
; pair in SCN_LIST and the slot in SCN_BUF. At the next vblank, before the
; sprites, scene_flush writes the listed tiles (the slots are consecutive: one
; pass for patterns, one for colours) and then the band's names, switching
; the band to the new bank at once. The scroll is taken in 2-pixel steps (the
; arcade moves 1 pixel a frame: same speed, 30 steps a second), and nothing is
; rebuilt while the scroll and the band's cells stay put. The ordinary screen
; renderer draws the band rows black and leaves them to this code.
; =============================================================================
SCN_BUF         equ $6A50       ; band names, 24 per row. Arcade stack area the
SCN_BUF_MAX     equ 6 * 24      ; arcade never uses ($EA50-$EB4B); ours stays
        assert SCN_BUF + SCN_BUF_MAX <= $6B00   ; above $6B30 in every replay
SCN_LIST        equ $2E96       ; pair id per slot: unused padding in the arcade
SCN_SLOTS       equ 50          ; image ($2E96-$2EFF, never executed or read)
        assert SCN_LIST + SCN_SLOTS <= $2F00
IDC             equ $0800       ; VRAM, free with the shared pattern table:
                                ; (band row * 32 + native row) * 2 + (phase != 0)
BLANK_BG        equ $29         ; the arcade's empty background tile
PAIR_KEYS       equ $C000       ; pair bank (tools/gen_screens.py): 512 keys,
PAIR_ID         equ $C800       ;   ids, and each pair's tiles at phases 0, 2,
PAIR_DATA       equ $D000       ;   4, 6 at PAIR_DATA + id * 64
FILL_DONE       equ 2           ; scn_fill: 0 masks, 1 IDC, 2 done
ROWS_LIGHT      equ 6           ; band rows built per vblank: all of them. A build
ROWS_HEAVY      equ 6           ; split over vblanks mixed rows from different
                                ; frames (the arcade animates legs by rewriting
                                ; tiles): torn characters
HEAVY_TILES     equ 24          ; tiles in a build that make it heavy

; Called by render_body in screen mode, before the static cells are drawn.
; A build runs over a few vblanks, ROWS_LIGHT or ROWS_HEAVY band rows each
; (heavy: the last build had more than HEAVY_TILES tiles); scn_brow is the
; next row, 0 when no build is under way.
scene_update:
        ld a, (scn_pbank)
        or a
        ret z                   ; this screen has no band
        call vgl_check          ; VERY GOOD: the romhack's characters
                                ; (vgland.asm)
        ld a, (up_pending)
        or a
        ret nz                  ; its tile set is not loaded yet
        ld a, (scn_fill)
        cp FILL_DONE
        jp c, scene_fill_step   ; the caches first
        ld a, (scn_brow)
        or a
        jr nz, .rows
        ld a, (scn_ready)       ; the last build not fully out yet?
        ld b, a
        ld a, (scn_flush2)
        or b
        ret nz
        ld a, (IO_SCROLL_Y)     ; a new build? Only if the scroll step or a
        and $FE                 ; band cell changed (scn_dirty: scene_write)
        ld b, a
        ld a, (scn_dirty)
        or a
        jr nz, .start
        ld a, (scn_scroll)
        cp b
        ret z
.start: ld a, (arc_idle)        ; only between arcade frames: inside its
        or a                    ; handler a character may be half redrawn
        ret z
        ld a, b                 ; this scroll step, the other slot bank
        ld (scn_scroll), a
        call scene_apply
        xor a
        ld (scn_dirty), a
        ld a, (scn_n)
        ld (scn_lastn), a
        xor a
        ld (scn_n), a
        ld a, (scn_bank)
        xor 1
        ld (scn_bank), a
        xor a
.rows:  ld c, a                 ; C = first row, B = rows this vblank
        ld a, (scn_lastn)
        cp HEAVY_TILES + 1
        ld b, ROWS_LIGHT
        jr c, .light
        ld b, ROWS_HEAVY
.light: ld a, (scn_rows)
        sub c
        cp b
        jr nc, .some
        ld b, a                 ; (the last rows)
.some:  ld a, c
        add a, b
        ld (scn_brow), a
        call scene_build
        ld a, (scn_rows)
        ld b, a
        ld a, (scn_brow)
        cp b
        ret c
        xor a                   ; all rows built
        ld (scn_brow), a
        inc a
        ld (scn_ready), a
        ret

; Called first in the vblank: a finished build's tiles and names (a heavy
; build's patterns now, its colours and names at the next vblank).
scene_vblank:
        ld a, (mode)
        cp MODE_SCREEN
        ret nz
        ld a, (scn_pbank)
        or a
        ret z
        ld a, (up_pending)
        or a
        ret nz
        call .flush
        ld a, (vgl_on)          ; then the romhack characters (vgland.asm)
        or a
        ret z
        jp vgl_tick
.flush: ld a, (scn_flush2)
        or a
        jp nz, scene_flush.second
        ld a, (scn_ready)
        or a
        ret z
        jp scene_flush

; First slot code of the bank being built / just built.
scene_slot0:
        ld a, (scn_bank)
        or a
        ld a, (scn_base)
        ret z
        add a, SCN_SLOTS
        ret

; -----------------------------------------------------------------------------
; A new scene: the art masks (one vblank), then every IDC entry unknown ($FF,
; looked up by the first build that needs it). A = scn_fill.
scene_fill_step:
        or a
        jr nz, .idc
        ld hl, SCN_WRITES       ; the fill reads the arcade's latest
        ld de, SCN_WRITES + 1
        ld bc, 23
        ld (hl), 0
        ldir
        ld a, (scn_rows)
        ld b, a
        ld c, 0
.m:     push bc
        call scene_mask_row
        pop bc
        inc c
        djnz .m
        ld a, 1
        ld (scn_fill), a
        ret
.idc:   ld hl, IDC
        call vdp_set_write
        ld a, (scn_rows)        ; rows * 64 entries
        ld c, a
        ld a, $FF
.row:   ld b, 64
.w:     out (VDP_DATA), a       ; (30 T-states a byte)
        nop
        nop
        djnz .w
        dec c
        jr nz, .row
        ld a, FILL_DONE
        ld (scn_fill), a
        ld a, 1
        ld (scn_dirty), a       ; build now
        ret

; C = band row, B = native row -> HL = its IDC entries (VRAM).
scene_idc_addr:
        ld l, c
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, l
        add a, b
        ld l, a
        add hl, hl
        ld a, h
        add a, high IDC
        ld h, a
        ret

; C = band row -> HL = arcade bg tile layer at native row 0 of its column,
; A = the column.
scene_col:
        ld a, (scn_row0)        ; native column = 31 - (screen row + cam)
        add a, c
        ld l, a
        ld a, (cam)
        add a, l
        cpl
        and $1F
        ld l, a
        ld h, high (ARC_VRAM + $400)
        ret

; C = band row: its art mask from the arcade's bg layer.
scene_mask_row:
        ld a, c
        add a, a
        add a, a
        ld e, a
        ld d, 0
        ld hl, scn_mask
        add hl, de
        ex de, hl               ; DE -> the mask
        call scene_col
        ld c, 4
.byte:  ld b, 8
        xor a
.bit:   push bc
        ld c, a
        ld a, (hl)
        cp BLANK_BG
        ld a, c
        scf
        jr nz, .shift
        or a
.shift: rra                     ; eight shifts: native row 8j in bit 0
        ld bc, 32
        add hl, bc
        pop bc
        djnz .bit
        ld (de), a
        inc de
        dec c
        jr nz, .byte
        ret

; C = band row, B = native row, D = 0 (the row alone) or 1 (the row and the
; next). Returns A = pair id + 1, or 0 if both are empty or the pair is
; unknown. The pair bank is mapped. Clobbers everything but IX, IY.
scene_id:
        push bc
        call scene_col
        pop bc
        ld a, b                 ; HL -> the left cell's bg tile
        rrca
        rrca
        rrca
        ld e, a
        and $E0
        or l
        ld l, a
        ld a, e
        and 3
        add a, h
        ld h, a
        ld a, (hl)
        ld (scn_key+1), a       ; left tile
        ld c, a
        ld a, h                 ; (attributes are $400 below the tiles)
        sub 4
        ld h, a
        ld a, (hl)
        ld (scn_key), a         ; left attribute
        ld a, d
        or a
        jr nz, .right
        ld a, $FF               ; the left cell alone
        ld (scn_key+2), a
        ld (scn_key+3), a
        ld a, c
        cp BLANK_BG
        jr nz, scene_lookup
        xor a
        ret
.right: ld a, l                 ; the right cell: the next native row
        add a, 32
        ld l, a
        jr nc, .r1
        inc h
        ld a, h
        cp high (ARC_VRAM + $400)
        jr c, .r1
        ld h, high ARC_VRAM
.r1:    ld a, (hl)
        ld (scn_key+2), a       ; right attribute
        ld a, h
        add a, 4
        ld h, a
        ld a, (hl)
        ld (scn_key+3), a       ; right tile
        cp BLANK_BG
        jr nz, scene_lookup
        ld a, c
        cp BLANK_BG
        jr nz, scene_lookup
        xor a
        ret

; scn_key -> A = pair id + 1 (0 = unknown). The pair bank is mapped.
scene_lookup:
        ld a, (scn_key+3)       ; h = (left tile ^ rlc3(right tile)) * 2
        rlca                    ;   + bit 2 of (left attr ^ right attr)
        rlca                    ; (tools/gen_screens.py pkey)
        rlca
        ld hl, scn_key+1
        xor (hl)
        ld l, a
        ld h, 0
        add hl, hl
        ld a, (scn_key)
        ld de, scn_key+2
        ex de, hl
        xor (hl)
        ex de, hl
        and 4
        jr z, .probe
        inc l
.probe: push hl
        add hl, hl
        add hl, hl
        ld a, h
        add a, high PAIR_KEYS
        ld h, a
        ld de, scn_key
        ld b, 4
.cmp:   ld a, (de)
        cp (hl)
        jr nz, .miss
        inc de
        inc hl
        djnz .cmp
        pop hl                  ; found: its id
        ld a, h
        add a, high PAIR_ID
        ld h, a
        ld a, (hl)
        inc a
        ret
.miss:  pop hl                  ; an empty entry ($FF key) ends the probe
        push hl
        add hl, hl
        add hl, hl
        ld a, h
        add a, high PAIR_KEYS
        ld h, a
        ld a, (hl)
        inc hl
        and (hl)
        inc a
        pop hl
        jr z, .none             ; (the capture never saw this pair)
        inc hl
        ld a, h
        and 1
        ld h, a
        jr .probe
.none:  xor a
        ret

; The arcade's video store (queue_cell, arcade context). HL = video address
; ($7000-$7FFF). A cell of a band row: its bit in SCN_WRITES, a rebuild, and
; carry (queue_cell drops it). Otherwise no carry. Preserves BC, DE, HL.
SCN_WRITES      equ $5F94       ; 6 band rows x 32 native rows, a bit each:
        assert SCN_WRITES + 24 <= $6000   ; unused padding in the arcade image
scene_write:
        push bc
        ld a, l                 ; screen row = 31 - column - cam
        and $1F
        cpl
        and $1F
        ld c, a
        ld a, (cam)
        ld b, a
        ld a, c
        sub b
        call in_band
        jr nc, .no
        ld b, a
        ld a, (scn_row0)
        ld c, a
        ld a, b
        sub c                   ; band row
        add a, a
        add a, a
        ld c, a                 ; C = band row * 4
        ld a, h                 ; native row = cell >> 5: byte (row / 8),
        and 3                   ; bit (row & 7) = bits 7-5 of L
        add a, c
        push hl
        ld c, a
        ld a, l
        rlca
        rlca
        rlca
        and 7
        ld b, a
        ld a, 1
        jr z, .b
.sh:    add a, a
        djnz .sh
.b:     ld b, 0
        ld hl, SCN_WRITES
        add hl, bc
        or (hl)
        ld (hl), a
        pop hl
        ld a, 1
        ld (scn_dirty), a
        pop bc
        scf
        ret
.no:    pop bc
        or a
        ret

; Before a build: every band cell the arcade wrote since the last one gets its
; art bit and its IDC entries (rows r - 1 and r, both phases) marked unknown.
; The arcade is paused during the NMI, so the build sees one frame.
scene_apply:
        ld hl, SCN_WRITES
        ld c, 0                 ; C = band row
.row:   ld a, (scn_rows)
        cp c
        ret z
        ld b, 0                 ; B = native row of bit 0 of the byte
.byte:  ld a, (hl)
        or a
        jr z, .nb
        ld (hl), 0
        push hl
        ld e, a
.bit:   srl e
        jr nc, .nobit
        push bc
        push de
        call .cell
        pop de
        pop bc
.nobit: inc b
        ld a, b
        and 7
        jr nz, .bit
        pop hl
        jr .next
.nb:    ld a, b
        add a, 8
        ld b, a
.next:  inc hl
        ld a, b
        cp 32
        jr c, .byte
        inc c
        jr .row
; C = band row, B = native row.
.cell:  push bc
        call scene_bit
        pop bc
        ld a, b
        or a
        jr nz, .inrow
        call scene_idc_addr     ; r = 0: entries of row 0, then of row 31
        call vdp_set_write
        call .unk2
        ld b, 31
        call scene_idc_addr
        call vdp_set_write
        jr .unk2
.inrow: dec b                   ; rows r - 1 and r: 4 consecutive entries
        call scene_idc_addr
        call vdp_set_write
        call .unk2
.unk2:  ld a, $FF
        out (VDP_DATA), a
        nop                     ; (30 T-states between writes)
        nop
        nop
        nop
        push af
        pop af
        out (VDP_DATA), a
        ret

; C = band row, B = native row: set or clear its art bit from the arcade's
; bg layer.
scene_bit:
        push bc
        call scene_col
        pop bc
        ld a, b                 ; HL -> the cell's bg tile
        rrca
        rrca
        rrca
        ld e, a
        and $E0
        or l
        ld l, a
        ld a, e
        and 3
        add a, h
        ld h, a
        ld a, (hl)
        cp BLANK_BG
        push af                 ; Z: blank
        ld a, c                 ; mask byte: scn_mask + row * 4 + r / 8
        add a, a
        add a, a
        ld e, a
        ld a, b
        rrca
        rrca
        rrca
        and 3
        add a, e
        ld e, a
        ld d, 0
        ld hl, scn_mask
        add hl, de
        ld a, b
        and 7
        ld b, a
        ld a, 1
        jr z, .b
.sh:    add a, a
        djnz .sh
.b:     ld b, a
        pop af
        ld a, b
        jr z, .clr
        or (hl)
        ld (hl), a
        ret
.clr:   cpl
        and (hl)
        ld (hl), a
        ret

; -----------------------------------------------------------------------------
; Build rows C .. C+B-1 of the band into SCN_BUF. A row's names start black;
; then each native row r with art gives the cells showing it: sx = r - r0
; (as the left tile) and, if the phase is not 0, sx - 1 (as the right tile).
scene_build:
        ld a, (scn_pbank)       ; (lookups of unknown entries)
        call select_bank
        ld a, (scn_scroll)
        and 7
        ld (scn_ph), a
        ld a, (scn_scroll)      ; r0 = native row of the cell at sx = 0:
        rrca                    ; 4 + scroll / 8
        rrca
        rrca
        and $1F
        add a, 4
        and $1F
        ld (scn_r0), a
.row:   push bc
        ld a, c
        ld (scn_k), a
        add a, a                ; this row's names: SCN_BUF + row * 24
        add a, a
        add a, a
        ld l, a
        add a, a
        add a, l
        ld l, a
        ld h, 0
        ld de, SCN_BUF
        add hl, de
        ld (scn_rowbuf), hl
        ld d, h
        ld e, l
        inc de
        ld (hl), 0
        push bc
        ld bc, 23
        ldir
        pop bc
        ld a, c                 ; its mask: scn_mask + row * 4
        add a, a
        add a, a
        ld l, a
        ld h, 0
        ld de, scn_mask
        add hl, de
        ld e, 0                 ; E = native row of bit 0 of the byte
.byte:  ld a, (hl)
        call vgl_filter         ; (VERY GOOD: not the romhack's characters)
        or a
        jr z, .next
        push hl
        ld d, 8
.bit:   rrca
        jr nc, .nobit
        push af
        push de
        call scene_art
        pop de
        pop af
.nobit: inc e
        dec d
        jr nz, .bit
        pop hl
        jr .nb
.next:  ld a, e
        add a, 8
        ld e, a
.nb:    inc hl
        ld a, e
        cp 32
        jr c, .byte
        call vgl_patch          ; the romhack block's names in this row
        pop bc
        inc c
        djnz .row
        ret

; E = a native row with art.
scene_art:
        ld a, (scn_ph)
        or a
        ld a, e
        ld d, 0                 ; phase 0: its cell, entry (r, alone)
        jr z, scene_do
        inc d                   ; else its cell, entry (r, r + 1), and the cell
        push de                 ; before, entry (r - 1, r)
        call scene_do
        pop de
        ld a, e
        dec a
        and $1F
        ; fall through
; A = native row r (the cell's left tile), D = phase entry. The cell at
; sx = r - r0, unless off screen or already done.
scene_do:
        ld b, a
        ld hl, scn_r0
        sub (hl)
        and $1F
        cp 24
        ret nc
        ld e, a
        push de
        ld d, 0
        ld hl, (scn_rowbuf)
        add hl, de
        pop de
        ld a, (hl)
        or a
        ret nz
        push hl
        ld a, (scn_k)           ; its IDC entry
        ld c, a
        push de
        call scene_idc_addr
        pop de
        ld a, l
        or d
        out (VDP_CTRL), a       ; VDP read address, then >= 29 T-states
        ld a, h                 ; before the data
        out (VDP_CTRL), a
        pop hl                  ; (30 T-states before the read)
        ld a, (scn_n)
        cp SCN_SLOTS
        in a, (VDP_DATA)
        ret nc                  ; out of slots: stays black
        cp $FF
        call z, .look           ; unknown: look it up now
        or a
        ret z                   ; nothing there
        dec a
        ld c, a                 ; C = pair id
        ld a, (scn_n)
        ld e, a
        inc a
        ld (scn_n), a
        ld d, 0
        push hl
        ld hl, SCN_LIST
        add hl, de
        ld (hl), c
        pop hl
        call scene_slot0
        add a, e
        ld (hl), a
        ret
; The entry at (scn_k, B, D) was unknown: look the pair up and store it.
; Returns A = pair id + 1 or 0. Preserves HL, DE.
.look:  push hl
        push de
        push bc
        ld a, (scn_k)
        ld c, a
        call scene_id
        pop bc
        pop de
        push de
        push af
        ld a, (scn_k)
        ld c, a
        call scene_idc_addr
        ld a, l
        or d
        ld l, a
        call vdp_set_write
        pop af
        out (VDP_DATA), a
        pop de
        pop hl
        ret

; -----------------------------------------------------------------------------
; The built bank's tiles, then the band's names into the name table on
; screen. Every write is spaced >= 30 T-states: writing back to back from the
; start of the NMI (assumed inside the vertical blank) corrupted tiles
; whenever the NMI ran late (openMSX enforces the VDP's access slots too).
; FLUSH_FAST = 8-byte groups allowed back to back (0: none).
FLUSH_FAST      equ 0
scene_flush:
        ld a, FLUSH_FAST / 8
        ld (scn_fast), a
        xor a
        ld (scn_ready), a
        ld a, (scn_n)
        or a
        jr z, .names
        ld a, (scn_pbank)
        call select_bank
        call scene_slot0        ; patterns: slot0 * 8 onward
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        call vdp_set_write
        ld e, 0                 ; E = offset in a tile: 0 patterns, 8 colours
        call .pass
        ld a, (scn_n)
        cp HEAVY_TILES + 1
        jr c, .colours
        ld a, 1                 ; heavy: the rest at the next vblank
        ld (scn_flush2), a
        ret
.second:
        xor a
        ld (scn_flush2), a
        ld a, FLUSH_FAST / 8
        ld (scn_fast), a
        ld a, (scn_pbank)
        call select_bank
.colours:
        call scene_slot0        ; colours: $2000 + slot0 * 8 onward
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
        add a, high VR_CT
        ld h, a
        call vdp_set_write
        ld e, 8
        call .pass
.names: ld a, (pnt_front)       ; HL = name table + row0 * 32
        ld e, a
        ld a, (scn_row0)
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
        add a, e
        ld h, a
        ld de, SCN_BUF
        ld a, (scn_rows)
        ld b, a
.row:   push bc
        call vdp_set_write
        ex de, hl
        ld bc, 24 * 256 + VDP_DATA
.out:   outi                    ; 30 T-states a byte
        nop
        jp nz, .out
        ex de, hl
        ld bc, 32
        add hl, bc
        pop bc
        djnz .row
        jp vgl_flushed
; 8 bytes (at offset E) of each listed pair's tile at the built phase. The
; pair bank is mapped.
.pass:  ld a, (scn_scroll)      ; E += phase / 2 * 16
        and 6
        rlca
        rlca
        rlca
        or e
        ld e, a
        ld hl, SCN_LIST
        ld a, (scn_n)
        ld d, a
        ld c, VDP_DATA
.tile:  ld a, (hl)              ; pair id -> PAIR_DATA + id * 64 + E
        inc hl
        push hl
        rrca
        rrca
        ld l, a
        and $3F
        add a, high PAIR_DATA
        ld h, a
        ld a, l
        and $C0
        or e
        ld l, a
        ld a, (scn_fast)
        or a
        jr z, .slow
        dec a
        ld (scn_fast), a
        outi                    ; inside the vertical blank: back to back
        outi
        outi
        outi
        outi
        outi
        outi
        outi
        jr .next
.slow:  ld b, 8
.o:     outi                    ; 30 T-states a byte
        nop
        jp nz, .o
.next:  pop hl
        dec d
        jr nz, .tile
        ret
