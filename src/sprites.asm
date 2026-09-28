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

; Write the SAT straight from arcade sprite RAM. Runs first in the NMI,
; inside vblank. The arcade copies its queue to the front of sprite RAM and
; zeroes Y in every slot after it, so the scan stops at the first empty slot.
;
; ent_cache remembers, for each of the first 32 sprite RAM entries, the code
; and attribute it last had and the SAT name and colour they resolved to, so
; a sprite that only moved costs no pattern or colour lookup.
; Maps SPR_BANK_A; the caller restores the arcade's bank.
ENT_CACHE_N     equ 32
sprites_update:
        ld a, SPR_BANK_A
        call select_bank
        ld a, (cam)             ; screen y = (240 - cam*8) - X
        add a, a
        add a, a
        add a, a
        neg
        add a, 240
        ld (spr_ybase), a
        xor a
        ld (spr_out), a
        ld hl, VR_SAT
        call vdp_set_write
        ld hl, ARC_SPRITES
.next:  inc l                   ; -> Y (entries are 4-aligned: no carry)
        ld a, (hl)
        or a
        jp z, .end              ; Y = 0: end of the queue
        ld c, a
        ld a, 224               ; screen x = 224 - Y
        sub c
        ld b, 0                 ; B = early-clock bit
        jr nc, .xok
        cp -31
        jp c, .skip             ; entirely off the left
        add a, 32
        ld b, $80
        jr .xin
.xok:   cp 192
        jp nc, .skip            ; right of the playfield
.xin:   ld c, a                 ; C = x
        inc l
        inc l                   ; -> X
        ld a, (spr_ybase)
        sub (hl)
        dec l
        dec l                   ; -> Y
        jr c, .yneg
        cp 192
        jp nc, .skip
        jr .ypos
.yneg:  cp -15
        jp c, .skip
.ypos:  dec a                   ; the TMS9918 draws one line below Y
        cp SAT_END
        jp z, .skip
        ld (spr_y), a
        dec l                   ; -> code
        ; cache entry for this sprite RAM entry: ent_cache + (entry index * 4)
        ld a, l
        sub low ARC_SPRITES
        ld e, a
        ld a, h
        sbc a, high ARC_SPRITES
        jr nz, .nocache         ; entry 64+ bytes in: past the cache
        ld a, e
        cp ENT_CACHE_N*4
        jr nc, .nocache
        ld d, high ent_cache
        ld a, (de)              ; same code and attribute as last time?
        cp (hl)
        jr nz, .miss
        inc e
        inc l
        inc l
        ld a, (de)
        xor (hl)                ; zero if the attribute matches
        dec l                   ; (dec changes Z: test A again after)
        dec l
        dec e
        or a
        jr z, .hit
.miss:  call sprite_resolve     ; fills the cache entry at DE
        jr .hit
.nocache:
        ld de, spr_tmp          ; resolve into a scratch entry
        call sprite_resolve
.hit:   ld a, (spr_y)           ; out: y, x, name, colour | early clock
        out (VDP_DATA), a
        ld a, c
        out (VDP_DATA), a
        inc e
        inc e
        ld a, (de)
        out (VDP_DATA), a
        inc e
        ld a, (de)
        or b
        out (VDP_DATA), a
        ld a, (spr_out)
        inc a
        ld (spr_out), a
        cp 32
        jr z, .full             ; 32 hardware sprites
.skip:  ld a, l                 ; next entry (HL anywhere inside this one)
        or 3
        inc a
        ld l, a
        jr nz, .same
        inc h
.same:  cp low (ARC_SPRITES + 256)
        jp nz, .next
        ld a, h
        cp high (ARC_SPRITES + 256)
        jp nz, .next            ; all 64 entries done
.end:   ld a, SAT_END
        out (VDP_DATA), a
.full:  ret

; HL -> sprite entry (code), DE -> 4-byte cache entry. Resolves the pattern
; slot and colour into [code, attribute, name, colour]. Preserves BC, DE, HL;
; restores the VDP write address to the next SAT entry.
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
        ld (de), a              ; colour
        push hl
        ld a, (spr_out)         ; the VDP write address: SAT + out*4
        add a, a
        add a, a
        ld l, a
        ld h, high VR_SAT
        call vdp_set_write
        pop hl
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
