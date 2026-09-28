; =============================================================================
; Mr. Do! (Universal 1982) - arcade-faithful ColecoVision + Super Game Module port
; =============================================================================
; Build : make            (sjasmplus -> build/mrdo.rom, 128KB MegaCart image)
; Run   : make run        (openMSX, machine ColecoVision_SGM, ColecoMegaCart)
;
; The arcade program runs unmodified at its original addresses in SGM RAM (see
; tools/patch_arcade.py for the few references that had to move). This driver:
;   * boots, checks for the SGM, loads the arcade image into RAM,
;   * turns every ColecoVision vblank (NMI) into the arcade's vblank IRQ,
;     holding it while the arcade has interrupts off, as the arcade's
;     level-triggered IRQ does,
;   * feeds the arcade's input ports from the controllers,
;   * draws the screen (phase 1: a debug view of the foreground text layer).
;
; Rules:
;   * The BIOS is gone after boot - nothing may call it.
;   * Once the display is on, VRAM is only touched from the NMI handler.
; =============================================================================

        include "hw.inc"

ARC_HI_BANK     equ 0           ; arcade $6000-$7FFF, mapped at $C000 while it runs
ARC_LO_BANK     equ 1           ; arcade $0000-$5FFF in 8KB pieces, banks 1-3
; Reading $FFC0-$FFFF switches MegaCart banks, so no bank may keep data in its
; last 64 bytes: the arcade image is stored 8KB per bank at $C000-$DFFF.

; --- driver variables (in the arcade ROM's unused padding, never cleared by it) ---
        org DRV_RAM
frame_cnt:      ds 2            ; +1 per vblank
irq_count:      ds 2            ; arcade vblank handler entries
deferred_cnt:   ds 2            ; vblanks held because the arcade had interrupts off
cur_bank:       ds 1            ; bank currently mapped at $C000
dbg_row:        ds 1            ; debug view: next screen row to draw
dbg_cam:        ds 1            ; debug view: first player-view row shown
key_prev:       ds 1            ; keypad value last frame
coin_hold:      ds 1            ; frames left to hold the coin line low
inp_override:   ds 1            ; test scripts: nonzero = use inp_p1/inp_p2 as-is
inp_p1:         ds 1            ; arcade $A000 value while overridden
inp_p2:         ds 1            ; arcade $A001 value while overridden
scratch_de:     ds 2            ; irq_after_ei
repend:         ds 1            ; a vblank arrived while one was being delivered
        assert $ <= DRV_RAM_END

        ifdef VALIDATE
        output "build/mrdo_validate.rom"
        else
        output "build/mrdo.rom"
        endif

; =============================================================================
; SWITCHABLE BANKS  ($C000-$FFFF). Each has its number at $E000 for the boot
; self-test (the arcade image never reaches $E000).
; =============================================================================
        org $C000                       ; bank 0: arcade $6000-$7FFF
        incbin "build/arc_hi.bin"
        org $E000
        db 0
        ds $10000-$, $FF

        ifdef VALIDATE
        define ARCIMG_FILE "build/arc_lo_validate.bin"
        else
        define ARCIMG_FILE "build/arc_lo.bin"
        endif
        dup 3, piece                    ; banks 1-3: arcade $0000-$5FFF, 8KB each
        org $C000
        incbin ARCIMG_FILE, piece*$2000, $2000
        db piece+1                      ; $E000: bank id
        ds $10000-$, $FF
        edup

        dup MC_FIXED-4, n               ; banks 4..: spare
        org $C000
        ds $2000, $FF
        db n+4
        ds $10000-$, $FF
        edup

; =============================================================================
; FIXED BANK  ($8000-$BFFF) - last 16KB of the image
; =============================================================================
        org $8000
        db $55, $AA             ; cart magic: skip the BIOS title screen
        dw 0, 0, 0, 0           ; sprite table, sprite order, work buffer, controller map
        dw start
        ; BIOS RST/IRQ/NMI trampolines ($800C-$8023) - only used until the BIOS is swapped out
        ret
        ds 2
        ret
        ds 2
        ret
        ds 2
        ret
        ds 2
        ret
        ds 2
        ret
        ds 2
        reti                    ; $801E: IRQ (unused on CV)
        ds 1
        jp nmi_bios             ; $8021: NMI while the BIOS is still mapped
        db "MR. DO!/ARCADE PORT/2026"

nmi_bios:
        push af
        in a, (VDP_CTRL)
        pop af
        retn

; -----------------------------------------------------------------------------
start:
        di
        ld sp, $73FF            ; native CV RAM until the SGM is up
        ld a, VDP_R1_OFF        ; no VDP interrupts while we remap $0000-$1FFF
        ld c, 1
        call vdp_reg
        in a, (VDP_CTRL)
        call sn_silence

        ld a, 1
        out (SGM_UPPER), a      ; 24KB RAM at $2000-$7FFF
        call sgm_present
        jp nz, no_sgm
        ld a, $0D
        out (SGM_LOWER), a      ; 8KB RAM over the BIOS at $0000-$1FFF
        ld sp, BOOT_STACK

        call ay_silence
        call vdp_init
        call load_arcade
        call install_hooks
        ld hl, ARC_VRAM         ; video RAM starts zeroed, as MAME powers it up
        ld de, ARC_VRAM+1       ; (the arcade clears its work RAM itself)
        ld bc, $0FFF
        ld (hl), 0
        ldir

        ld hl, DRV_RAM          ; driver variables start clean
        ld de, DRV_RAM+1
        ld bc, DRV_RAM_END-DRV_RAM-1
        ld (hl), 0
        ldir
        ld a, 4
        ld (dbg_cam), a
        call inputs_idle

        ld a, ARC_HI_BANK       ; the arcade's upper half stays mapped from now on
        call select_bank

        ld a, VDP_R1_ON
        ld c, 1
        call vdp_reg
        jp ARC_RESET            ; the arcade cold start: ld sp,$6B80 / jp $0068

; Copy the patched arcade image into RAM at $0000-$5FFF.
load_arcade:
        ld de, $0000
        ld a, ARC_LO_BANK
.piece: push af
        call select_bank
        ld hl, $C000
        ld bc, $2000
        ldir                    ; DE advances to the next 8KB
        pop af
        inc a
        cp ARC_LO_BANK+3
        jr nz, .piece
        ret

; Vectors in the (now RAM) arcade image. $0008-$0037 and $0066 are unused by the
; arcade ($0066 held a bare `retn`).
install_hooks:
        ld hl, ei_hook          ; $0008-$000E: see ei_hook
        ld de, $0008
        ld bc, ei_hook_len
        ldir
        ifdef VALIDATE
        ld hl, validate_hooks   ; $0010 and $0018, see validate_hooks
        ld de, $0010
        ld bc, 5
        ldir
        ld de, $0018
        ld bc, 4
        ldir
        endif
        ld hl, $0066
        ld (hl), $C3            ; $0066: jp nmi
        inc hl
        ld (hl), low nmi
        inc hl
        ld (hl), high nmi
        ret

        ifdef VALIDATE
; Validation mode: where the pathfinder finishes, drop the rst's return
; address and re-enable interrupts. The MAME reference
; (tools/diff/mame_record.lua) has the same bytes with a plain `ei`.
validate_hooks:
        db $33, $33, $CF, $18, $FE  ; $0010: inc sp / inc sp / ei (rst $08) / jr $
        db $33, $33, $CF, $C9       ; $0018: inc sp / inc sp / ei (rst $08) / ret
        endif

; $0008 hook, reached by rst $08 (every arcade `ei`). The byte at $0009 picks
; the path, so the NMI can switch it with one (atomic) write.
HOOK_SEL        equ $0009
HOOK_PENDING    equ $0C - $0A       ; jr offset to the jp take_irq
ei_hook:
        jr $+2                  ; $0008: offset byte at $0009 (0 = plain)
        ei                      ; $000A
        ret                     ; $000B
        jp take_irq             ; $000C
ei_hook_len     equ $ - ei_hook
        assert ei_hook_len <= 8

; -----------------------------------------------------------------------------
; VBLANK
;
; The arcade expects a vblank IRQ that stays asserted until taken: if it
; arrives while the handler is still running (interrupts off), it is taken
; the moment the handler re-enables interrupts. Every `ei` in the arcade code
; was patched to `rst $08` (the hook above). When a vblank has to wait, the
; NMI sets HOOK_SEL, so the next `ei` delivers it through take_irq.
; -----------------------------------------------------------------------------
nmi:
        push af
        push bc
        push de
        push hl
        in a, (VDP_CTRL)        ; ack
        ld hl, (frame_cnt)
        inc hl
        ld (frame_cnt), hl

        call dbg_render
        call read_inputs

        ld a, i                 ; P/V = IFF2 = the arcade's interrupt enable
        jp po, .hold
        ld hl, 8                ; interrupted between the hook's `ei` and
        add hl, sp              ; `ret` (PC $000B)? Then finish that `ret`
        ld a, (hl)              ; (and the arcade instruction after the
        cp $0B                  ; `ei`) before taking the vblank.
        jr nz, .direct
        inc hl
        ld a, (hl)
        or a
        jr nz, .direct
        pop hl
        pop de
        pop bc
        pop af
        di
        inc sp                  ; drop the NMI's return to $000B; (sp) = R
        inc sp
        xor a
        ld (HOOK_SEL), a        ; delivering now: nothing left pending
        jp irq_after_ei
.direct:
        xor a                   ; a vblank held earlier is delivered now
        ld (HOOK_SEL), a
        pop hl                  ; take it now: the interrupted PC is on the
        pop de                  ; stack, exactly where an IRQ would put it
        pop bc
        pop af
        di                      ; clears IFF2 too, like an IRQ acknowledge
        jp irq_enter

.hold:  ld hl, (deferred_cnt)
        inc hl
        ld (deferred_cnt), hl
        ld hl, 8                ; interrupted PC
        add hl, sp
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld de, -$0008           ; inside the hook ($0008-$000E), or in
        add hl, de              ; take_irq before it acknowledged? Then the
        ld de, 7                ; held vblank is being delivered right now:
        or a                    ; ask take_irq to hold this new one again.
        sbc hl, de
        jr c, .repend
        add hl, de
        ld de, $0008 - take_irq
        add hl, de
        ld de, take_irq.acked - take_irq
        or a
        sbc hl, de
        jr c, .repend
        ld a, HOOK_PENDING      ; one byte: the next `ei` takes the vblank
        ld (HOOK_SEL), a
        jr .held
.repend:
        ld a, 1
        ld (repend), a
.held:  pop hl
        pop de
        pop bc
        pop af
        retn

; Reached through the arcade's `ei` (rst $08) while a vblank is waiting.
; Interrupts are off; the return address on the stack is the instruction
; after the `ei`. An NMI landing in the hook or before `.acked` sets repend
; instead of HOOK_SEL, since the store below would erase it.
take_irq:
        push af
        xor a
        ld (HOOK_SEL), a        ; acknowledge: the next `ei` is plain again
.acked: ld a, (repend)          ; a vblank that arrived before the line
        or a                    ; above is held again, not lost (the
        jr z, .none             ; arcade's IRQ is level-triggered)
        xor a
        ld (repend), a
        ld a, HOOK_PENDING
        ld (HOOK_SEL), a
.none:  pop af
        ; fall through

; Take the vblank the way a Z80 would after `ei`: only once the NEXT
; instruction has run. On entry (sp) = R, the address of that instruction.
; In the arcade it is always one of: ret ($0136), call nn ($013B/$0144/$0150),
; or an idle jr ($00AB, validation hooks). All registers are preserved.
irq_after_ei:
        ex (sp), hl             ; HL = R, (sp) = caller's HL
        push af
        ld a, (hl)
        cp $C9                  ; ret: the IRQ returns to the ret's target
        jr z, .ret
        cp $CD                  ; call nn: push R+3, the IRQ returns into nn
        jr z, .call
        pop af                  ; anything else (the idle jr): return to R
        ex (sp), hl
        jr irq_enter
.ret:   pop af
        pop hl                  ; stack top is now the ret's target
        jr irq_enter
.call:  pop af
        ld (scratch_de), de
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)              ; DE = call target
        inc hl                  ; HL = R+3, the call's return address
        ex (sp), hl             ; (sp) = R+3, HL = caller's HL
        push de                 ; the IRQ returns into the called routine
        ld de, (scratch_de)
irq_enter:
        push hl
        ld hl, (irq_count)
        inc hl
        ld (irq_count), hl
        pop hl
        jp ARC_IRQ

; -----------------------------------------------------------------------------
; INPUTS -> arcade ports (active low)
; Joystick 1: directions + left fire. Keypad: * = coin, 1 = 1P start,
; 2 = 2P start. The coin line is held low for 4 frames per press.
; -----------------------------------------------------------------------------
inputs_idle:
        ld a, $FF
        ld (IO_IN0), a
        ld (IO_IN1), a
        ld a, DSW1_DEFAULT
        ld (IO_DSW1), a
        ld a, DSW2_DEFAULT
        ld (IO_DSW2), a
        ret

read_inputs:
        ld a, (inp_override)
        or a
        jr z, .pads
        ld a, (inp_p1)
        ld (IO_IN0), a
        ld a, (inp_p2)
        ld (IO_IN1), a
        jr .dsw
.pads:  out (CTL_SEL_JOY), a
        in a, (CTL_P1)          ; 0 up 1 right 2 down 3 left 6 fire, active low
        ld c, a
        ld b, $FF               ; build the arcade P1 byte, active low
        bit 0, c
        jr nz, .nu
        res 3, b
.nu:    bit 1, c
        jr nz, .nr
        res 2, b
.nr:    bit 2, c
        jr nz, .nd
        res 1, b
.nd:    bit 3, c
        jr nz, .nl
        res 0, b
.nl:    bit 6, c
        jr nz, .nf
        res 4, b
.nf:
        out (CTL_SEL_KEYPAD), a
        in a, (CTL_P1)
        and $0F                 ; keypad code
        ld hl, key_prev
        cp (hl)
        ld (hl), a
        jr z, .held             ; act on new presses only
        cp KEY_STAR
        jr nz, .nk1
        ld a, 4
        ld (coin_hold), a
.nk1:   ld a, (hl)
        cp KEY_HASH
        jr nz, .held
        ld a, (dbg_cam)         ; # cycles the debug view window
        add a, 4
        cp 12
        jr c, .cam
        xor a
.cam:   ld (dbg_cam), a
.held:  ld a, (hl)
        cp KEY_1
        jr nz, .n1
        res 5, b
.n1:    cp KEY_2
        jr nz, .n2
        res 6, b
.n2:    ld a, b
        ld (IO_IN0), a

        ld b, $FF               ; P2 port: coin 1 only
        ld a, (coin_hold)
        or a
        jr z, .nc
        dec a
        ld (coin_hold), a
        res 6, b
.nc:    ld a, b
        ld (IO_IN1), a
.dsw:   ld a, DSW1_DEFAULT
        ld (IO_DSW1), a
        ld a, DSW2_DEFAULT
        ld (IO_DSW2), a
        ret

; Keypad codes (low nibble of the port in keypad mode)
KEY_1           equ $0D
KEY_2           equ $07
KEY_STAR        equ $06
KEY_HASH        equ $09

; -----------------------------------------------------------------------------
; DEBUG VIEW: the arcade foreground tile layer, rotated to the player's view.
; Player-view row p, column x shows arcade fg tile (native row x+4, native
; column 31-p). Font tiles $00-$23 show as text; any other tile shows as a
; dot, blank ($29) as blank. Six screen rows per vblank (a full redraw every
; four frames).
; -----------------------------------------------------------------------------
dbg_render:
        ld b, 6
.row:   push bc
        ld a, (dbg_row)
        ld e, a                 ; E = screen row
        ld l, a                 ; name table address = $1800 + row*32
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, VR_PNT
        add hl, bc
        call vdp_set_write
        ld a, (dbg_cam)         ; native column = 31 - (row + cam)
        add a, e
        cpl
        and $1F
        ld l, a
        ld h, 0
        ld bc, ARC_FG_TILE + 4*32
        add hl, bc              ; HL = fg tile at native row 4, that column
        ld de, 32
        ld b, 24
.cell:  ld a, (hl)
        push hl
        ld hl, dbg_lut
        add a, l
        ld l, a
        jr nc, .nc
        inc h
.nc:    ld a, (hl)
        out (VDP_DATA), a
        pop hl
        add hl, de
        djnz .cell
        ld a, (dbg_row)
        inc a
        cp 24
        jr c, .next
        xor a
.next:  ld (dbg_row), a
        pop bc
        djnz .row
        ret

; arcade fg tile -> debug font tile
dbg_lut:
        dup 36, n
        db n                    ; $00-$23: 0-9, A-Z
        edup
        ds $29-36, T_DOT
        db T_BLANK              ; $29: blank
        ds $72-$2A, T_DOT
        ds 4, $17               ; $72-$75: monster nest -> N
        ds 1, T_DOT
        db T_BLANK              ; $77: solid dirt
        ds 4, $0C               ; $78-$7B: cherry quarters -> C
        ds 256-$7C, T_DOT

; -----------------------------------------------------------------------------
; A = bank number -> mapped at $C000-$FFFF. Clobbers HL.
select_bank:
        ld (cur_bank), a
        add a, low MC_HOTSPOT
        ld l, a
        ld h, high MC_HOTSPOT
        ld a, (hl)
        ret

sn_silence:
        ld a, $9F
        ld b, 4
.ch:    out (SN_PORT), a
        add a, $20
        djnz .ch
        ret

ay_silence:
        ld a, 7                 ; mixer: all tone and noise off
        out (SGM_AY_ADDR), a
        ld a, $3F
        out (SGM_AY_WRITE), a
        ld b, 3
        ld c, 8                 ; volumes 8-10 = 0
.v:     ld a, c
        out (SGM_AY_ADDR), a
        xor a
        out (SGM_AY_WRITE), a
        inc c
        djnz .v
        ret

; Is SGM RAM answering at $2000? (A stock ColecoVision has nothing there; its
; 1KB only mirrors across $6000-$7FFF, so the probe must stay below $6000.)
; Out: Z = present.
sgm_present:
        ld hl, $2000
        ld (hl), $55
        ld a, (hl)
        cp $55
        ret nz
        ld (hl), $AA
        ld a, (hl)
        cp $AA
        ret

; No Super Game Module: say so and stop. Runs with the BIOS still mapped and
; only the native 1KB of RAM.
no_sgm:
        call vdp_init
        ld hl, VR_PNT + 10*32 + 3
        ld de, s_nosgm1
        call print_vram
        ld hl, VR_PNT + 12*32 + 9
        ld de, s_nosgm2
        call print_vram
        ld a, VDP_R1_OFF | $40  ; display on, VDP interrupt still off
        ld c, 1
        call vdp_reg
.halt:  jr .halt

; -----------------------------------------------------------------------------
; VDP helpers. Safe only with the VDP interrupt off or from inside the NMI.

; A = value, C = register number.
vdp_reg:
        out (VDP_CTRL), a
        ld a, c
        or $80
        out (VDP_CTRL), a
        ret

; HL = VRAM address to write.
vdp_set_write:
        ld a, l
        out (VDP_CTRL), a
        ld a, h
        or $40
        out (VDP_CTRL), a
        ret

; HL = VRAM address, BC = count, A = fill byte.
vdp_fill:
        push af
        call vdp_set_write
        pop af
        ld d, a
.loop:  ld a, d
        out (VDP_DATA), a
        dec bc
        ld a, b
        or c
        jr nz, .loop
        ret

; HL = VRAM address, DE = source, BC = count.
vdp_copy:
        call vdp_set_write
.loop:  ld a, (de)
        out (VDP_DATA), a
        inc de
        dec bc
        ld a, b
        or c
        jr nz, .loop
        ret

vdp_init:
        ld hl, vdp_regs
        ld c, 0
.reg:   ld a, (hl)
        call vdp_reg
        inc hl
        inc c
        ld a, c
        cp 8
        jr nz, .reg

        ld hl, $0000            ; clear all 16KB
        ld bc, $4000
        xor a
        call vdp_fill

        ld b, 3                 ; font into every third of the pattern table
        ld hl, VR_PT
.third: push bc
        push hl
        ld de, font
        ld bc, font_len
        call vdp_copy
        pop hl
        ld bc, $800
        add hl, bc
        pop bc
        djnz .third

        ld hl, VR_CT            ; white on black everywhere
        ld bc, $1800
        ld a, $F1
        call vdp_fill

        ld hl, VR_PNT
        ld bc, 32*24
        ld a, T_BLANK
        call vdp_fill

        ld hl, VR_SAT
        call vdp_set_write
        ld a, SAT_END
        out (VDP_DATA), a
        ret

vdp_regs:
        db VDP_R0, VDP_R1_OFF, VDP_R2, VDP_R3, VDP_R4, VDP_R5, VDP_R6, VDP_R7

; -----------------------------------------------------------------------------
; Text. Tiles follow the arcade font: 0-9 = $00-$09, A-Z = $0A-$23, blank = $24,
; dot = $25.
T_BLANK equ $24
T_DOT   equ $25

; HL = VRAM address, DE = zero-terminated ASCII string (A-Z, 0-9, space).
; Init-time only.
print_vram:
        call vdp_set_write
.loop:  ld a, (de)
        or a
        ret z
        inc de
        cp ' '
        jr z, .blank
        cp 'A'
        jr c, .digit
        sub 'A'-10
        jr .put
.digit: sub '0'
        jr .put
.blank: ld a, T_BLANK
.put:   out (VDP_DATA), a
        jr .loop

s_nosgm1: db "SUPER GAME MODULE REQUIRED", 0
s_nosgm2: db "PLEASE CONNECT", 0

font:   incbin "build/font.bin"
        db $00, $00, $00, $18, $18, $00, $00, $00   ; T_DOT
font_len equ $-font

        ds $C000-$, $FF
        outend
