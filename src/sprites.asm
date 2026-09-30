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
SPR_BANK_W      equ MC_FIXED-1  ; Mr. Do's white overlays: pseudo codes $80-$BF
SPR_WHITE       equ $E880       ; in SPR_BANK_A: 64 x (1 = the code has white)
WHITE_TMS       equ 15
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
;    bands, then the crowded ones rotated three places per frame, in
;    reverse order every other pass, so every sprite on a busy row gets its
;    turn (tools/flicker_sim.py) and none drops out for several frames.
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
SPR_HALF        equ 1           ; while the arcade lags, rebuild on every other
                                ; new frame of sprite data (0: every one)

sprites_update:
        ld a, (cam)             ; nothing new since the last pass (no sprite
        ld hl, spr_cam          ; RAM copy, same camera)? The SAT stands.
        cp (hl)
        jr nz, .new
        ld a, (spr_new)
        or a
        if SPR_HALF
        jr nz, .data
        else
        jr nz, .new
        endif
.lag:   ld a, (crowd_last)      ; a crowded screen rotates every vblank even
        or a                    ; when the arcade lags (else a sprite on a
        ret z                   ; hidden turn stayed hidden for the stall);
        ld a, SPR_BANK_A        ; the list and its split stand: only the
        call select_bank        ; output (a fraction of a full pass; chomper
        jp spr_emit             ; sessions lag most)
.data:  ld hl, spr_lastf         ; new sprite data. Two or more vblanks since the
        ld a, (frame_cnt)       ; last (the arcade is lagging: a chomper session,
        ld b, (hl)              ; a crowded round)? Then every other one is
        ld (hl), a              ; left out: the sprite list is ~16% of the CPU
        sub b                   ; there, and the arcade gets the time back.
        cp 2                    ; The screen keeps the last list (rotating
        jr c, .new              ; when crowded).
        ld hl, spr_tog
        ld a, (hl)
        xor 1
        ld (hl), a
        jr z, .new
        xor a
        ld (spr_new), a
        jr .lag
.new:   ld a, (cam)
        ld (spr_cam), a
        xor a
        ld (spr_new), a
        ld (hud_mk), a
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
        ld a, (mode)            ; this pass's tiled apples (apples.asm)
        cp MODE_PLAYFIELD
        jr nz, .na
        xor a
        ld (apl_new_n), a
.na:    ld hl, ARC_SPRITES + 1  ; -> Y of entry 0
        ld de, spr_list
.next:  ld a, (hl)              ; Y (0 = end of the queue)
        or a
        jp z, .done
        dec l                   ; ball / ball fragment? (code $70): draw one
        ld a, (hl)              ; in four, so the 20-fragment burst and re-form
        inc l                   ; cost a quarter; a lone ball is always the
        cp BALL_CODE            ; first (kept)
        jr nz, .nb
        ld a, (frag_cnt)
        inc a
        ld (frag_cnt), a
        and 3
        dec a
        jp nz, .skip
.nb:    dec l                   ; a resting apple drawn as tiles? (apples.asm;
        ld a, (hl)              ; checked from the raw entry, before the
        inc l                   ; position work: ~35% of entries in a
        and $7F                 ; chomper session are apples)
        cp APPLE_CODE
        jr nz, .nap             ; (cp leaves carry for codes below it)
        call apple_try
        jp c, .skip
.nap:   ld a, (hl)              ; Y
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
        jp c, .top
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
        and $4F                 ; (pinned stays in bit 6: the TMS9918
                                ; ignores bits 4-6 of the SAT colour byte)
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
        jp nc, .crowded
        inc l
        djnz .cr
        xor a
        ld (crowd_last), a
        call sat_begin          ; no: Mr. Do's overlays, then the list as is
        ld a, (sat_n)           ; (at most 32 entries in all)
        neg
        add a, 32
        add a, a
        add a, a
        ld b, a                 ; B = room in bytes
        ld a, (spr_out)
        cp b
        jr c, .fit
        ld a, b
.fit:   or a
        jr z, spr_term
        ld b, a
        rrca
        rrca
        ld hl, sat_n
        add a, (hl)
        ld (hl), a
        ld c, VDP_DATA
        ld hl, spr_list
.out:   outi                    ; 32 T per byte: safe outside vblank too (the
        nop                     ; TMS9918 needs ~29 T between accesses during
        jr nz, .out             ; active display)
spr_term:
        ld a, (sat_n)
        cp 32
        ret nc
        ld a, SAT_END
        out (VDP_DATA), a
        ret

; Above the window: the HUD's EXTRA marker (X $E9, colour line 4; always
; above: y = 240 - cam * 8 - $E9 < -15)? Its Y for hud_scan. HL -> Y.
sprites_update.top:
        inc l
        inc l
        ld a, (hl)              ; X
        dec l
        cp $E9
        jr nz, .no
        ld a, (hl)              ; colour line
        and $0F
        cp 4
        jr nz, .no
        dec l
        ld a, (hl)              ; Y
        ld (hud_mk), a
        jp sprites_update.skip
.no:    dec l
        jp sprites_update.skip

; SAT write address, count 0, then an overlay sprite with Mr. Do's white
; pixels in front of (before) each pinned Mr. Do entry that has any. The
; overlay slots are resolved first: a lookup moves the VDP address.
sat_begin:
        ld a, (pin_n)
        or a
        jr z, .sat
        ld b, a
        ld c, 0                 ; C = pin index
.res:   push bc
        ld hl, pin_code
        ld a, l
        add a, c
        ld l, a
        ld a, (hl)              ; code: Mr. Do's are $00-$26
        ld d, $FF               ; (no overlay)
        cp $40
        jr nc, .put
        ld e, a
        push de
        ld d, 0
        ld hl, SPR_WHITE
        add hl, de
        ld a, (hl)
        pop de
        or a
        jr z, .put
        ld hl, pin_attr
        ld a, l
        add a, c
        ld l, a
        ld c, (hl)              ; attribute (flips in bits 4-5)
        ld a, e
        call overlay_slot       ; A = slot
        add a, a
        add a, a
        ld d, a                 ; D = name
.put:   pop bc
        push bc
        ld hl, pin_ovname
        ld a, l
        add a, c
        ld l, a
        ld (hl), d
        pop bc
        inc c
        djnz .res
.sat:   ld hl, VR_SAT
        call vdp_set_write
        xor a
        ld (sat_n), a
        ld a, (pin_n)
        or a
        ret z
        ld b, a
        ld c, 0
.ov:    ld hl, pin_ovname
        ld a, l
        add a, c
        ld l, a
        ld d, (hl)
        ld a, d
        cp $FF
        jr z, .next
        ld hl, pin_list
        ld a, l
        add a, c
        ld l, a
        ld l, (hl)
        ld h, high spr_list     ; HL -> Mr. Do's list entry
        ld a, (hl)              ; y
        out (VDP_DATA), a
        inc l
        nop
        ld a, (hl)              ; x
        out (VDP_DATA), a
        inc l
        inc l
        ld a, d                 ; name
        out (VDP_DATA), a
        ld a, (hl)              ; early clock bit of Mr. Do's colour byte
        and $80
        or WHITE_TMS
        out (VDP_DATA), a
        ld hl, sat_n
        inc (hl)
.next:  inc c
        djnz .ov
        ret

; A = arcade code ($00-$3F), C = its attribute. The cache slot of its white
; overlay pattern (pseudo code $80 + code, SPR_BANK_W). SPR_BANK_A is mapped
; on entry and exit.
overlay_slot:
        add a, $80
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
        ld l, a                 ; HL = key $200-$2FF
        jp sprite_slot.key

; A = colour | pinned, DE -> the colour byte of this list entry, HL -> the
; arcade entry (code). Records the entry's offset in pin_list and its code
; and attribute. Preserves AF, BC, DE, HL.
spr_pin:
        push af
        push bc
        push hl
        ld a, (pin_n)
        cp SPR_PIN_MAX
        jr nc, .full
        inc a
        ld (pin_n), a
        dec a
        ld b, (hl)              ; HL -> the arcade entry's code
        inc l
        inc l
        ld c, (hl)              ;   and attribute
        add a, low pin_list
        ld l, a
        ld h, high pin_list
        ld a, e
        sub 3                   ; start of the entry
        ld (hl), a
        ld a, l
        add a, pin_code - pin_list
        ld l, a
        ld (hl), b
        add a, pin_attr - pin_code
        ld l, a
        ld (hl), c
.full:  pop hl
        pop bc
        pop af
        ret

sprites_update.crowded:
        ld a, 1
        ld (crowd_last), a
        ; fall through
; A crowded frame: the list split into uncrowded and crowded (kept for the
; vblanks until the arcade's next sprite data), then spr_emit.
sprites_prio:
        xor a
        ld (crowd_n), a
        ld (unc_n), a
        ld hl, spr_list
.ent:   ld a, (spr_end)
        cp l
        jr z, spr_emit
        inc l                   ; pinned (colour bit 6): goes out first
        inc l
        inc l
        ld a, (hl)
        dec l
        dec l
        dec l
        and $40                 ; (after the decs: they change Z)
        jr nz, .nx
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
.unc:   ld a, (unc_n)           ; uncrowded
        ld e, a
        inc a
        ld (unc_n), a
        ld a, e
        add a, low unc_idx
        ld e, a
        ld d, high unc_idx
        ld a, l
        ld (de), a
        jr .nx
.crowd: ld a, (crowd_n)
        cp CROWD_MAX
        jr nc, .unc             ; list full: this one just goes out in order
        ld e, a
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

; Mr. Do's overlays, the pinned, the uncrowded, then the crowded ones
; rotated three places per call.
spr_emit:
        call sat_begin
        ld a, (pin_n)
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
.p2:    ld a, (unc_n)
        or a
        jr z, .p3
        ld b, a
        ld de, unc_idx
.un:    ld a, (de)
        ld l, a
        ld h, high spr_list
        call spr_out4
        inc e
        djnz .un
.p3:    ld a, (crowd_n)         ; crowded, rotated three places per frame
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
        ld a, (crowd_dir)       ; every other pass the other way round: with
        xor 1                   ; only rotation, a count that is a multiple
        ld (crowd_dir), a       ; of 3 kept a sprite in the same places for
        jr z, .rot              ; a while (an apple gone for several frames);
.bk:    ld a, c                 ; reversed, whatever came last comes first
        or a
        jr nz, .bd
        ld a, (crowd_n)
.bd:    dec a
        ld c, a
        add a, low crowd_idx
        ld l, a
        ld h, high crowd_idx
        ld l, (hl)
        ld h, high spr_list
        call spr_out4
        djnz .bk
        jp spr_term
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

; HL -> spr_list entry: write its four SAT bytes >= 30 T apart (safe outside
; vblank). Preserves HL.
spr_out4:
        ld a, (sat_n)           ; 32 entries at most (overlays count too)
        cp 32
        ret nc
        inc a
        ld (sat_n), a
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
.key:   ld (spr_key), hl
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
        ld a, b                 ; key high byte: 0 bank A, 1 bank B,
        or a                    ; 2 Mr. Do's white overlays
        ld a, SPR_BANK_A
        jr z, .bank
        dec b
        ld a, SPR_BANK_B
        jr z, .bank
        ld a, SPR_BANK_W
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
