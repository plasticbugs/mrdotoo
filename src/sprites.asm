; =============================================================================
; sprites.asm - arcade sprite RAM -> TMS9918 sprites (runs inside the NMI)
; =============================================================================
; The arcade copies its sprite queue to sprite RAM ($9000, our ARC_SPRITES)
; every frame: 64 x [code, Y (0 = unused), colour line | flipx $10 | flipy $20,
; X]. The monitor is rotated; in the player's view a sprite's top-left is
;   screen x = 256 - Y - 32  (the playfield starts at arcade row 4)
;   screen y = 240 - X - cam*8
; Patterns (tools/gen_sprites.py) are pre-rotated for every code and flip:
; key = code*4 + flipy*2 + flipx. A 64-slot cache in the sprite pattern table
; holds the ones in use; VRAM $1C00-$1DFF maps key -> slot+1.
; =============================================================================

SPR_BANK_A      equ 13          ; patterns for codes 0-63, and the colour table
SPR_BANK_B      equ 14          ; patterns for codes 64-127
SPR_COLOURS     equ $E000       ; in SPR_BANK_A: 128 codes x 16 colour lines
SPR_PIN         equ $E800       ; in SPR_BANK_A: 128 x (SPR_PINNED or 0)
VR_SPRMAP       equ $1C00       ; key -> slot+1 (0 = not cached)
SPR_SLOTS       equ 64

sprites_init:
        ld hl, ent_cache        ; no cached entries (code $FF never matches)
        ld de, ent_cache+1
        ld bc, ENT_CACHE_N*4-1
        ld (hl), $FF
        ldir
        ld hl, slot_key         ; all slots empty ($FF,$FF)
        ld de, slot_key+1
        ld bc, SPR_SLOTS*2-1
        ld (hl), $FF
        ldir
        xor a
        ld (evict_ptr), a
        ret

; One pass over arcade sprite RAM at the start of the NMI builds spr_list,
; already in SAT byte order [y, x, name, colour | early clock], counting each
; sprite into the three 8-line bands it can touch. Then:
;  * no band holds five or more: the list goes out as is (order is
;    irrelevant when no line overflows);
;  * otherwise pinned sprites (Mr. Do) first, then the ones in uncrowded
;    bands, then the crowded ones rotated three places per frame so every
;    sprite on a busy row gets its turn (tools/flicker_sim.py).
; The arcade copies its queue to the front of sprite RAM and zeroes Y in every
; slot after it, so the scan stops at the first empty slot.
;
; ent_cache remembers, for the first 32 sprite RAM entries, the code and
; attribute each last had and the name and colour | pinned they resolved to,
; so a sprite that only moved costs no lookup. Maps SPR_BANK_A; the caller
; restores the arcade's bank. Uses the alternate registers (saved).
ENT_CACHE_N     equ 32
BANDS           equ 30          ; 8-line bands of (screen y + 16)
SPR_PINNED      equ $40
SPR_PIN_MAX     equ 4
BALL_CODE       equ $70         ; the power ball and its burst fragments

sprites_update:
        ld a, SPR_BANK_A
        call select_bank
        exx                     ; the arcade uses the alternate set too
        push bc
        push de
        push hl
        ld h, high band_cnt     ; HL' -> band counters
        exx
        ld hl, band_cnt
        ld de, band_cnt + 1
        ld bc, BANDS - 1
        ld (hl), 0
        ldir
        ld a, (cam)             ; y base = 240 - cam*8: screen y = base - X
        add a, a
        add a, a
        add a, a
        neg
        add a, 240
        ld (spr_ybase), a
        xor a
        ld (frag_cnt), a
        ld (pin_n), a
        ld hl, ARC_SPRITES + 1  ; -> Y of entry 0
        ld de, spr_list
.next:  ld a, (hl)              ; Y (0 = end of the queue)
        or a
        jp z, .done
        dec l                   ; ball / ball fragment? (code $70): draw every
        ld a, (hl)              ; other one, so the 20-fragment burst costs
        inc l                   ; half; a lone ball is always the first (kept)
        cp BALL_CODE
        jr nz, .nb
        ld a, (frag_cnt)
        inc a
        ld (frag_cnt), a
        and 1
        jp z, .skip
.nb:    ld a, (hl)              ; Y
        cpl
        sub 31                  ; screen x = 224 - Y
        jr c, .ec
        cp 192
        jp nc, .skip            ; right of the playfield
        ld b, 0
        jr .xok
.ec:    cp -31
        jp c, .skip             ; entirely off the left
        add a, 32               ; early clock: the TMS9918 shifts it 32 left
        ld b, $80
.xok:   inc e
        ld (de), a              ; x
        dec e
        ld a, b
        ld (spr_ec), a
        ld a, (spr_ybase)
        inc l
        inc l
        sub (hl)                ; screen y (carry: above the window)
        dec l                   ; (dec keeps carry)
        dec l
        jr c, .yneg
        cp 192
        jp nc, .skip
        jr .yok
.yneg:  cp -15
        jp c, .skip
.yok:   dec a                   ; the TMS9918 draws one line below Y
        cp SAT_END
        jp z, .skip
        ld (de), a              ; y
        exx                     ; count the three bands it can touch
        add a, 17               ; (screen top + 16 is 1-207, never negative)
        rrca
        rrca
        rrca
        and $1F
        add a, low band_cnt
        ld l, a
        inc (hl)
        inc l
        inc (hl)
        inc l
        inc (hl)
        exx
        dec l                   ; -> code
        ld a, h                 ; cache entry: entries 0-31 only
        cp high ARC_SPRITES
        jr nz, .nocache
        ld a, l
        sub low ARC_SPRITES
        cp ENT_CACHE_N*4
        jr nc, .nocache
        ld c, a
        ld b, high ent_cache
        ld a, (bc)              ; same code and attribute as last time?
        cp (hl)
        jr nz, .miss
        inc c
        inc l
        inc l
        ld a, (bc)
        xor (hl)
        dec l                   ; (dec changes Z: test A again after)
        dec l
        dec c
        or a
        jr z, .hit
.miss:  push de                 ; resolve fills the cache entry at BC
        ld d, b
        ld e, c
        call sprite_resolve
        pop de
        jr .hit
.nocache:
        ld bc, spr_tmp
        push de
        ld de, spr_tmp
        call sprite_resolve
        pop de
.hit:   inc c                   ; name, colour from the cache entry
        inc c
        inc e
        inc e
        ld a, (bc)
        ld (de), a              ; name
        inc c
        inc e
        ld a, (bc)              ; colour | pinned
        bit 6, a
        call nz, spr_pin        ; remember pinned entries (Mr. Do)
        and $0F
        ld b, a
        ld a, (spr_ec)
        or b
        ld (de), a              ; colour | early clock
        inc e                   ; next list slot
        inc l                   ; -> Y, as at .next
        ld a, e
        cp low (spr_list + 32*4)
        jr z, .done             ; 32 hardware sprites
.skip:  ld a, l                 ; next entry: HL -> its Y
        add a, 4
        ld l, a
        jr nc, .same
        inc h
.same:  cp low (ARC_SPRITES + 256 + 1)
        jp nz, .next
        ld a, h
        cp high (ARC_SPRITES + 256)
        jp nz, .next
.done:  exx
        pop hl
        pop de
        pop bc
        exx
        ld a, e
        sub low spr_list
        ld (spr_out), a         ; bytes in the list (entries * 4)
        add a, low spr_list
        ld (spr_end), a         ; low byte just past the list
        ld hl, band_cnt         ; does any band hold five or more?
        ld b, BANDS
.cr:    ld a, (hl)
        cp 5
        jp nc, sprites_prio
        inc l
        djnz .cr
        ld hl, VR_SAT           ; no: straight out
        call vdp_set_write
        ld a, (spr_out)
        or a
        jr z, spr_term
        ld b, a
        ld c, VDP_DATA
        ld hl, spr_list
.out:   outi                    ; 32 T per byte: safe outside vblank too (the
        nop                     ; TMS9918 needs ~29 T between accesses during
        jr nz, .out             ; active display)
spr_term:
        ld a, (spr_out)
        cp 32*4
        ret z
        ld a, SAT_END
        out (VDP_DATA), a
        ret

; A = colour | pinned, DE -> the colour byte of this list entry. Records the
; entry's offset in pin_list. Preserves AF, BC, DE, HL.
spr_pin:
        push af
        push hl
        ld a, (pin_n)
        cp SPR_PIN_MAX
        jr nc, .full
        inc a
        ld (pin_n), a
        dec a
        add a, low pin_list
        ld l, a
        ld h, high pin_list
        ld a, e
        sub 3                   ; start of the entry
        ld (hl), a
.full:  pop hl
        pop af
        ret

; A crowded frame: pinned first, uncrowded next, the crowded ones rotated.
sprites_prio:
        ld hl, VR_SAT
        call vdp_set_write
        ld a, (pin_n)           ; 1: pinned
        or a
        jr z, .p2
        ld b, a
        ld de, pin_list
.pin:   ld a, (de)
        ld l, a
        ld h, high spr_list
        call spr_out4
        inc e
        djnz .pin
.p2:    xor a                   ; 2: uncrowded out, crowded collected
        ld (crowd_n), a
        ld hl, spr_list
.ent:   ld a, (spr_end)
        cp l
        jr z, .p3
        call spr_is_pinned
        jr z, .nx               ; already out
        ld a, (hl)              ; crowded if one of its bands holds 5+
        add a, 17
        rrca
        rrca
        rrca
        and $1F
        add a, low band_cnt
        ld e, a
        ld d, high band_cnt
        ld a, (de)
        cp 5
        jr nc, .crowd
        inc e
        ld a, (de)
        cp 5
        jr nc, .crowd
        inc e
        ld a, (de)
        cp 5
        jr nc, .crowd
        call spr_out4
        jr .nx
.crowd: ld a, (crowd_n)
        cp CROWD_MAX
        jr c, .keep
        call spr_out4           ; list full: this one just goes out in order
        jr .nx
.keep:  ld e, a
        inc a
        ld (crowd_n), a
        ld a, e
        add a, low crowd_idx
        ld e, a
        ld d, high crowd_idx
        ld a, l
        ld (de), a
.nx:    ld a, l
        add a, 4
        ld l, a
        jr .ent
.p3:    ld a, (crowd_n)         ; 3: crowded, rotated three places per frame
        or a
        jp z, spr_term
        ld b, a
        ld a, (crowd_rot)
        add a, 3
.mod:   cp b
        jr c, .rok
        sub b
        jr .mod
.rok:   ld (crowd_rot), a
        ld c, a
.rot:   ld a, c
        add a, low crowd_idx
        ld l, a
        ld h, high crowd_idx
        ld l, (hl)
        ld h, high spr_list
        call spr_out4
        inc c
        ld a, (crowd_n)
        cp c
        jr nz, .rnx
        ld c, 0
.rnx:   djnz .rot
        jp spr_term

; HL -> spr_list entry. Z = it is in pin_list. Preserves BC, DE, HL.
spr_is_pinned:
        ld a, (pin_n)
        or a
        jr z, .no
        push bc
        push de
        ld b, a
        ld de, pin_list
.c:     ld a, (de)
        cp l
        jr z, .yes
        inc e
        djnz .c
        pop de
        pop bc
.no:    or 1                    ; NZ
        ret
.yes:   pop de
        pop bc
        xor a                   ; Z
        ret

; HL -> spr_list entry: write its four SAT bytes >= 30 T apart (safe outside
; vblank). Preserves HL.
spr_out4:
        ld a, (hl)
        out (VDP_DATA), a
        inc l
        nop
        nop
        ld a, (hl)
        out (VDP_DATA), a
        inc l
        nop
        nop
        ld a, (hl)
        out (VDP_DATA), a
        inc l
        nop
        nop
        ld a, (hl)
        out (VDP_DATA), a
        dec l
        dec l
        dec l
        ret

; HL -> sprite entry (code), DE -> 4-byte cache entry. Resolves the pattern
; slot and colour into [code, attribute, name, colour]. Preserves BC, DE, HL.
sprite_resolve:
        push bc
        push de
        push hl
        ld a, (hl)
        ld (de), a              ; code
        inc e
        inc l
        inc l
        ld a, (hl)
        ld (de), a              ; attribute (colour line | flips)
        dec l
        dec l
        call sprite_slot        ; A = slot (HL -> entry)
        pop hl
        pop de
        push de
        inc e
        inc e
        add a, a
        add a, a
        ld (de), a              ; SAT name
        inc e
        ld a, (hl)              ; colour = table[code*16 + line]
        and $7F
        rrca
        rrca
        rrca
        rrca
        ld c, a
        and $0F
        add a, high SPR_COLOURS
        ld b, a
        ld a, c
        and $F0
        ld c, a
        inc l
        inc l
        ld a, (hl)
        dec l
        dec l
        and $0F
        or c
        ld c, a
        ld a, (bc)
        ld c, a
        ld a, (hl)              ; pinned code? (table after the colours)
        and $7F
        add a, low SPR_PIN
        ld b, a
        push hl
        ld l, b
        ld h, high SPR_PIN
        ld a, (hl)
        pop hl
        or c
        ld (de), a              ; colour | pinned
        pop de
        pop bc
        ret

; HL -> arcade sprite entry. Returns A = cache slot holding its pattern,
; loading it if needed. SPR_BANK_A is mapped on entry and exit.
sprite_slot:
        ld a, (hl)              ; key = code*4 + flips
        inc l
        inc l
        ld c, (hl)              ; colour line | flipx $10 | flipy $20
        and $7F
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        ld a, c
        rrca
        rrca
        rrca
        rrca
        and 3
        or l
        ld l, a                 ; HL = key 0-511
        ld (spr_key), hl
        ld de, VR_SPRMAP        ; slot+1 from the VRAM map
        add hl, de
        ld a, l
        out (VDP_CTRL), a
        ld a, h
        out (VDP_CTRL), a       ; read address
        ld a, (spr_key)         ; (time for the VDP to fetch)
        in a, (VDP_DATA)
        or a
        jr z, .miss
        dec a
        ld c, a                 ; verify: the slot still holds this key
        add a, a
        ld l, a
        ld h, high slot_key
        ld de, (spr_key)
        ld a, (hl)
        cp e
        jr nz, .miss
        inc l
        ld a, (hl)
        cp d
        jr nz, .miss
        ld a, c
        jr .used
.miss:  call sprite_load
.used:  ld c, a                 ; mark the slot used this frame
        ld hl, slot_frame
        add a, l
        ld l, a
        ld a, (frame_cnt)
        ld (hl), a
        ld a, c
        ret

; Pick a slot not used this frame, point the map at it, copy the pattern.
; Returns A = slot.
sprite_load:
        ld a, (frame_cnt)
        ld c, a
        ld a, (evict_ptr)
        ld b, SPR_SLOTS
.find:  and SPR_SLOTS-1
        ld e, a
        ld hl, slot_frame
        add a, l
        ld l, a
        ld a, (hl)
        cp c
        jr nz, .got
        ld a, e
        inc a
        djnz .find
        ld e, 0                 ; all 64 in use this frame: reuse slot 0
.got:   ld a, e
        inc a
        ld (evict_ptr), a
        ld a, e                 ; forget cached entries that name this slot
        add a, a
        add a, a
        ld c, a
        ld hl, ent_cache + 2
        ld b, ENT_CACHE_N
.inv:   ld a, (hl)
        cp c
        jr nz, .keep
        dec l
        dec l
        ld (hl), $FF            ; code $FF never matches (codes are 0-127)
        inc l
        inc l
.keep:  ld a, l
        add a, 4
        ld l, a
        djnz .inv
        ld a, e
        add a, a                ; unmap the key this slot held
        ld l, a
        ld h, high slot_key
        ld c, (hl)
        inc l
        ld b, (hl)
        ld a, b
        cp $FF
        jr z, .fresh
        push hl
        ld hl, VR_SPRMAP
        add hl, bc
        call vdp_set_write
        xor a
        out (VDP_DATA), a
        pop hl
.fresh: ld bc, (spr_key)        ; record the new key, map it
        ld (hl), b
        dec l
        ld (hl), c
        push bc
        ld hl, VR_SPRMAP
        add hl, bc
        call vdp_set_write
        ld a, e
        inc a
        out (VDP_DATA), a
        pop bc
        ; pattern: bank A (codes 0-63) or B, at $C000 + (key & $FF) * 32
        ld a, b
        or a
        ld a, SPR_BANK_A
        jr z, .bank
        ld a, SPR_BANK_B
.bank:  push de
        call select_bank
        pop de
        ld l, c
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, $C000
        add hl, bc
        push hl
        ld l, e                 ; SPT + slot*32
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, VR_SPT
        add hl, bc
        call vdp_set_write
        pop hl
        ld b, 32
.copy:  ld a, (hl)
        out (VDP_DATA), a
        inc hl
        djnz .copy
        ld a, SPR_BANK_A
        push de
        call select_bank
        pop de
        ld a, e
        ret
