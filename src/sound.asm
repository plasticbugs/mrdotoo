; =============================================================================
; sound.asm - the arcade's two SN76489s on the ColecoVision SN76489 + SGM AY
; =============================================================================
; The arcade's own sound engine runs unchanged; tools/patch_arcade.py routes
; its chip writes here (normal build only):
;   `ld (bc),a` at $5C3A/$5C3E/$5C45/$5C4C/$5C53 -> rst $10 (snd_rst_bc; BC is
;       the relocated $9801 / $9802 I/O cell)
;   `ld ($9801),a` at $5AE7 -> call snd_w1, `ld ($9802),a` at $5AEE -> snd_w2
; Chip 1 ($9801) plays on the CV's SN76489, chip 2 ($9802) on the AY: 6 tone
; channels and both noise channels, nothing dropped. The arcade chips run at
; 4.1 MHz (MAME), the CV SN at 3.58 MHz and the SGM AY at 1.79 MHz (AY
; periods count 16 clocks, SN periods 32): every tone period is scaled by 7/8
; (0.873 exactly) so pitches match. SN attenuation -> AY volume uses the MSX2 port's table (AtnToVol).
;
; SN76489 byte format: latch 1 cc t dddd (cc channel, t 0 tone / 1 volume,
; dddd low 4 bits), data 0 x dddddd (high 6 bits of the last latched tone).
; The arcade always writes a tone as latch then data.
; =============================================================================
SND_AY_MIX_BASE equ $38         ; AY R7: tones on, noise off, I/O ports input

snd_init:
        call sn_silence
        call ay_silence
        ld a, 7
        out (SGM_AY_ADDR), a
        ld a, SND_AY_MIX_BASE
        out (SGM_AY_WRITE), a
        ld (snd_mix), a
        xor a
        ld (snd_nvol2), a
        ld (snd_tvolc), a
        ld (snd_due), a
        ld (snd_busy), a
        inc a                   ; the first tick scans the request slots
        ld (snd_req), a         ; (opt.asm)
        xor a                   ; no channel record, none silenced
        ld (SND_VALID), a
        ld (SND_SIL), a
        ret

; The arcade's sound tick ($5A90, normally called by its vblank handler at
; $00D2, patched out) runs from our NMI instead: once per vblank, so music and
; effects keep time when the game logic falls behind (a heavy round, a long
; screen fill). snd_sched runs it at the start of every NMI, before the
; drawing, and also in a nested NMI when our drawing overran a frame (a tile
; set upload plus a full redraw at a round's start or a chomper session's):
; with the tick after the drawing those vblanks lost their tick and caught up
; in a burst (the round-start hitch). Safe against the interrupted arcade
; code: the game only posts requests ($02D9 / $02EA: one store each), and
; every chip write is inside the tick. Ticks owed are caught up (up to 3).
SND_TICK        equ $5A90
snd_sched:
        ld a, (cur_bank)        ; (a nested NMI may find another bank mapped)
        push af
        ld a, ARC_HI_BANK       ; the engine's data ($6000-$7FFF)
        call select_bank
        call snd_nmi_tick
        pop af
        jp select_bank

; Runs the owed ticks. Not re-entrant: an NMI arriving during one leaves its
; tick owed, and this loop takes it. Clobbers AF, BC, DE, HL.
snd_nmi_tick:
        ld a, (snd_busy)
        or a
        ret nz
        ld hl, (irq_count)      ; not before the arcade has initialised its
        ld a, h                 ; sound RAM (its first handler)
        or l
        jr nz, .go
        ld (snd_due), a
        ret
.go:    ld a, (snd_due)
        cp 4
        jr c, .n
        ld a, 3
        ld (snd_due), a
.n:     ld a, 1
        ld (snd_busy), a
        push ix
        push iy
        ex af, af'              ; the engine uses AF'
        push af
.loop:  ld hl, snd_due
        ld a, (hl)
        or a
        jr z, .done
        dec (hl)
        call SND_TICK
        jr .loop
.done:  pop af
        ex af, af'
        pop iy
        pop ix
        xor a
        ld (snd_busy), a
        ret

; The sound tick ($5A90) scans its 38 request slots only when a request was
; posted since (snd_req, in the ROM's $FF padding; tools/patch_arcade.py
; SND_REQ). The three places that set request bits also set it, with the
; same register and flag results as the originals.
snd_req         equ $59CB
opt_req0:
        set 0, b
        ld (hl), b
        jr opt_req
opt_req1:
        set 1, (hl)
        jr opt_req
opt_req2:
        set 2, (hl)
opt_req:
        push af
        ld a, 1
        ld (snd_req), a
        pop af
        ret

; The engine's per-channel output ($5C0F, patched): A = the channel's
; (iy+0) (bit 0 chip, bits 1-2 channel, bits 3-5 type), IY -> the channel,
; (iy+8) / (iy+9) its register bytes. The original writes 3 bytes (tone:
; latch | (iy+9) high nibble, (iy+8), volume | (iy+9) low nibble) or 2
; (other types: latch | (iy+8), volume | (iy+9)) every tick, all repeats;
; here only when the channel's bytes or type class changed since it was
; last written. The noise channels (3) always are: an SN76489 noise-control
; write restarts the noise, part of the arcade's sound. Registers after it
; are dead in the original (pop bc, ld de, add iy, djnz); nothing here
; touches RAM the arcade reads. Clobbers AF, BC, DE, HL.
; Records for the 6 tone channels (chip * 3 + channel), in the dead DIP-test
; code after unc_idx: (iy+8), (iy+9) each, then bitmasks.
SND_SHAD        equ $56F0           ; 6 x [(iy+8), (iy+9)]
SND_CLS         equ SND_SHAD + 12   ; bit n: channel n's type is "other"
SND_VALID       equ SND_SHAD + 13   ; bit n: its record holds what the chip has
SND_SIL         equ SND_SHAD + 14   ; bit n: silenced by the engine since
        assert unc_idx + 32 <= SND_SHAD && SND_SIL < dirty_q
snd_chout:
        ld c, a
        and 6
        cp 6
        jp z, .write            ; noise: always
        rrca                    ; channel 0-2
        ld e, a
        bit 0, c
        jr z, .c0
        add a, 3                ; chip 1: 3-5
.c0:    ld e, a                 ; E = record index
        add a, a
        add a, low SND_SHAD
        ld l, a
        ld h, high SND_SHAD
        ld a, e                 ; B = its bit
        ld b, 1
        or a
        jr z, .bit
.sh:    sla b
        dec a
        jr nz, .sh
.bit:   ld a, c                 ; class of this type: other ($20-$2F) or tone
        and $38
        cp $20
        ld d, 0
        jr c, .cl
        cp $30
        jr nc, .cl
        ld d, b                 ; D = B if "other"
.cl:    ld a, (SND_VALID)
        and b
        jr z, .new              ; no valid record
        ld a, (SND_CLS)
        and b
        xor d
        jr nz, .new             ; class changed
        ld a, (iy+8)
        cp (hl)
        jr nz, .new
        inc l
        ld a, (iy+9)
        cp (hl)
        ret z                   ; unchanged: nothing to write
        dec l
.new:   ld a, (iy+8)            ; record it
        ld (hl), a
        inc l
        ld a, (iy+9)
        ld (hl), a
        ld hl, SND_VALID
        ld a, (hl)
        or b
        ld (hl), a
        ld hl, SND_SIL          ; (written: no longer silent)
        ld a, b
        cpl
        and (hl)
        ld (hl), a
        ld hl, SND_CLS
        ld a, b
        cpl
        and (hl)
        or d
        ld (hl), a
.write: ld a, c                 ; D = latch base: 1cc0 0000
        and 6
        add a, a
        add a, a
        add a, a
        add a, a
        or $80
        ld d, a
        ld hl, snd_w1           ; the chip
        bit 0, c
        jr z, .chip
        ld hl, snd_w2
.chip:  ld a, c
        and $38
        cp $20
        jr c, .tone
        cp $30
        jr c, .other
.tone:  ld e, (iy+9)
        ld a, e
        and $F0
        rrca
        rrca
        rrca
        rrca
        or d
        call .out
        ld a, (iy+8)
        call .out
        ld a, e
        and $0F
        or d
        or $10
.out:   jp (hl)                 ; (snd_w1 / snd_w2 preserve everything)
.other: ld a, d
        or (iy+8)
        call .out
        ld a, d
        or (iy+9)
        or $10
        jr .out

; The engine's own silencing of unused channels ($5AE7 / $5AEE: every tick, a
; volume-off byte for each channel not playing): once is enough until the
; channel is written again (snd_chout clears the bit); its record is no
; longer what the chip holds. Noise channels pass every time. Preserves
; everything.
snd_sil1:
        push af
        push hl
        ld hl, snd_sbit1
        call snd_silchk
        pop hl
        jr z, .skip
        pop af
        jp snd_w1
.skip:  pop af
        ret
snd_sil2:
        push af
        push hl
        ld hl, snd_sbit2
        call snd_silchk
        pop hl
        jr z, .skip
        pop af
        jp snd_w2
.skip:  pop af
        ret
; A = the volume byte, HL -> the chip's record bits: Z if this silence is
; a repeat (skip it); else NZ and recorded (silenced, record no longer
; what the chip holds). Clobbers A, HL.
snd_silchk:
        and $60                 ; channel (bits 6-5) -> 0-3
        rlca
        rlca
        rlca
        add a, l
        ld l, a
        ld a, (hl)              ; its record bit (0: noise, always written)
        or a
        jr z, .nz
        ld l, a
        ld a, (SND_SIL)
        and l
        jr nz, .z               ; silenced already
        ld a, (SND_SIL)
        or l
        ld (SND_SIL), a
        ld a, l
        cpl
        ld l, a
        ld a, (SND_VALID)
        and l
        ld (SND_VALID), a
.nz:    or 1
        ret
.z:     xor a
        ret
snd_sbit1:      db 1, 2, 4, 0
snd_sbit2:      db 8, 16, 32, 0
        assert high snd_sbit1 == high (snd_sbit2 + 3)

; rst $10: the arcade's `ld (bc),a` into a sound chip. Every register and
; flag preserved (the store is kept too: the I/O cell).
snd_rst_bc:
        ld (bc), a
        push af
        ld a, c
        cp low (IO_CELLS + 2)
        jr z, .c2
        pop af
        jp snd_w1
.c2:    pop af
        ; fall through
; A = byte for arcade chip 2 -> AY. Preserves everything.
snd_w2:
        push af
        push bc
        push de
        push hl
        ld b, a
        bit 7, a
        jr z, .data
        rrca                    ; latch: channel in bits 6-5
        rrca
        rrca
        rrca
        rrca
        and 3
        ld c, a                 ; C = channel
        ld a, b
        ld (snd_lat2), a        ; remember for the data byte
        bit 4, a
        jr nz, .vol
        cp 3 << 5 | $80         ; noise control?
        jr c, .done             ; tone low nibble: wait for the data byte
        and 3                   ; noise rate 0-2 -> AY noise period; 3 (tone
        ld hl, noise_ay         ; channel 2's rate) -> the middle one
        add a, l
        ld l, a
        jr nc, .n1
        inc h
.n1:    ld a, 6
        out (SGM_AY_ADDR), a
        ld a, (hl)
        out (SGM_AY_WRITE), a
        jr .done
.vol:   ld a, b                 ; attenuation -> AY volume
        and $0F
        ld hl, AtnToVol
        add a, l
        ld l, a
        jr nc, .v1
        inc h
.v1:    ld e, (hl)              ; E = AY volume
        ld a, c
        cp 3
        jr z, .nvol
        cp 2
        jr nz, .setv
        ld a, e
        ld (snd_tvolc), a
        call ay_chan_c          ; channel C also carries the noise
        jr .done
.setv:  add a, 8
        out (SGM_AY_ADDR), a
        ld a, e
        out (SGM_AY_WRITE), a
        jr .done
.nvol:  ld a, e
        ld (snd_nvol2), a
        call ay_chan_c
        jr .done
.data:  ld a, (snd_lat2)        ; data: the latched tone's period
        call snd_period         ; HL = scaled period, C = channel
        ld a, c
        cp 3
        jr nc, .done
        add a, a                ; AY R(2c) fine, R(2c+1) coarse
        out (SGM_AY_ADDR), a
        ld e, a
        ld a, l
        out (SGM_AY_WRITE), a
        ld a, e
        inc a
        out (SGM_AY_ADDR), a
        ld a, h
        out (SGM_AY_WRITE), a
.done:  pop hl
        pop de
        pop bc
        pop af
        ret

; AY channel C: the louder of chip 2's tone 2 and its noise; noise mixed in
; while its volume is not 0.
ay_chan_c:
        ld a, (snd_nvol2)
        ld e, a
        ld a, (snd_tvolc)
        cp e
        jr nc, .v
        ld a, e
.v:     ld e, a
        ld a, 10
        out (SGM_AY_ADDR), a
        ld a, e
        out (SGM_AY_WRITE), a
        ld a, (snd_nvol2)
        or a
        ld a, SND_AY_MIX_BASE
        jr z, .m
        and ~$20                ; noise on channel C
.m:     ld e, a
        ld a, 7
        out (SGM_AY_ADDR), a
        ld a, e
        out (SGM_AY_WRITE), a
        ret

; A = byte for arcade chip 1 -> CV SN76489. Preserves everything.
snd_w1:
        push af
        push bc
        push de
        push hl
        ld b, a
        bit 7, a
        jr z, .data
        ld (snd_lat1), a
        bit 4, a
        jr nz, .out             ; volume: as is
        and $60
        cp $60
        ld a, b
        jr z, .out              ; noise control: as is
        jr .done                ; tone low nibble: wait for the data byte
.data:  ld a, (snd_lat1)
        call snd_period         ; HL = scaled period (10 bits)
        ld a, (snd_lat1)
        and $F0
        ld b, a
        ld a, l
        and $0F
        or b
        out (SN_PORT), a        ; latch with the new low 4 bits
        ld a, l                 ; data: bits 9-4
        srl h
        rra
        srl h
        rra
        srl h
        rra
        srl h
        rra
        and $3F
        ld b, a
.out:   ld a, b
        out (SN_PORT), a
.done:  pop hl
        pop de
        pop bc
        pop af
        ret

; A = the tone's latch byte, B = the data byte -> HL = the period scaled by
; 7/8 (clock ratio), C = channel.
snd_period:
        ld c, a
        rlca                    ; channel = bits 6-5
        rlca
        rlca
        and 3
        push af
        ld a, c
        and $0F
        ld l, a                 ; period = data << 4 | low nibble
        ld a, b
        and $3F
        ld h, 0
        add a, a
        rl h
        add a, a
        rl h
        add a, a
        rl h
        add a, a
        rl h
        or l
        ld l, a                 ; HL = period (10 bits)
        ld d, h                 ; * 7/8 = period - period / 8 (clock ratio
        ld e, l                 ; 3.58 / 4.1 = 0.873: 3 cents sharp)
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        or a
        sbc hl, de
        pop af
        ld c, a
        ret

noise_ay:       db 14, 28, 31, 20       ; SN noise rates N/512, /1024, /2048, tone 2
AtnToVol:       db 15, 14, 14, 13, 12, 12, 11, 10, 10, 9, 8, 8, 7, 6, 6, 0
