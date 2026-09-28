; =============================================================================
; Mr. Do! (Universal 1982) - arcade-faithful ColecoVision + Super Game Module port
; =============================================================================
; Build : make            (sjasmplus -> build/mrdo.rom, 128KB MegaCart image)
; Run   : make run        (openMSX, machine ColecoVision_SGM, ColecoMegaCart)
;
; Phase 0 skeleton: boot through the Coleco BIOS, bring up the SGM (upper 24KB
; plus the lower 8KB swapped in over the BIOS), install our own vectors, check
; RAM and every MegaCart bank, and run a vblank-driven test screen.
;
; Rules that hold from here on:
;   * The BIOS is gone after boot - nothing may call it.
;   * Once the display is on, VRAM is only touched from the NMI handler.
;     The main loop works in RAM and the NMI flushes it.
; =============================================================================

        include "hw.inc"

; --- driver variables ------------------------------------------------------------
        org DRV_RAM
frame_cnt:      ds 2            ; +1 per vblank
frame_flag:     ds 1            ; set by NMI, cleared by the main loop
ram_ok:         ds 1            ; 1 = every SGM RAM probe passed
bank_ok:        ds 1            ; 1 = every switchable bank read back its id
cur_bank:       ds 1            ; bank currently mapped at $C000
joy1:           ds 1            ; P1 joystick, active high after the read
text_line:      ds 32           ; NMI copies this to name-table row 12

        output "build/mrdo.rom"

; =============================================================================
; SWITCHABLE BANKS 0..MC_FIXED-1  ($C000-$FFFF)
; Each starts with its bank number so boot can prove the mapper works.
; =============================================================================
        dup MC_FIXED, bank_no
        org $C000
        db bank_no
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
        ld a, VDP_R1_OFF        ; stop VDP interrupts before remapping $0000-$1FFF
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
        ld sp, STACK_TOP

        call ram_test
        call install_vectors
        call clear_ram
        ld (ram_ok), a          ; ram_test's verdict survives clear_ram in A
        call bank_test
        ld (bank_ok), a

        call vdp_init
        call draw_test_screen
        ld hl, text_line        ; the status line starts blank
        ld de, text_line+1
        ld bc, 31
        ld (hl), T_BLANK
        ldir

        ld a, VDP_R1_ON
        ld c, 1
        call vdp_reg

; --- main loop: one iteration per vblank --------------------------------------------
main_loop:
        ld hl, frame_flag
.wait:  ld a, (hl)
        or a
        jr z, .wait
        ld (hl), 0

        call read_joy1
        call build_status_line
        jr main_loop

; -----------------------------------------------------------------------------
; NMI (vblank). Save everything - it can land anywhere in the main loop.
nmi:
        push af
        push bc
        push de
        push hl
        in a, (VDP_CTRL)        ; ack
        ld hl, (frame_cnt)
        inc hl
        ld (frame_cnt), hl

        ld hl, VR_PNT + 12*32   ; flush the status line
        call vdp_set_write
        ld hl, text_line
        ld bc, 32*256 + VDP_DATA
        otir

        ld a, 1
        ld (frame_flag), a
        pop hl
        pop de
        pop bc
        pop af
        retn

irq:
        ei
        reti

; -----------------------------------------------------------------------------
; Vectors in the SGM RAM that now sits at $0000.
install_vectors:
        ld hl, $0000
        ld (hl), $C3            ; $0000: JP start (a hard reset maps the BIOS back anyway)
        inc hl
        ld (hl), low start
        inc hl
        ld (hl), high start
        ld hl, $0038
        ld (hl), $C3
        inc hl
        ld (hl), low irq
        inc hl
        ld (hl), high irq
        ld hl, $0066
        ld (hl), $C3
        inc hl
        ld (hl), low nmi
        inc hl
        ld (hl), high nmi
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
; only the native 1KB of RAM (DRV_RAM mirrors onto it).
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

; Probe the start and end of each SGM RAM region plus the old native-RAM window.
; Out: A = 1 if every probe held $55 and $AA, else 0.
ram_test:
        ld hl, ram_probes
        ld b, ram_probes_n
.next:  ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld a, $55
        ld (de), a
        ld a, (de)
        cp $55
        jr nz, .fail
        ld a, $AA
        ld (de), a
        ld a, (de)
        cp $AA
        jr nz, .fail
        djnz .next
        ld a, 1
        ret
.fail:  xor a
        ret

ram_probes:
        dw $0100, $1FFF, $2000, $5FFF, $6000, $6FFF, $7000, $73FF, $7400, $7BFF
ram_probes_n equ ($-ram_probes)/2

; Zero $0100-$7EFF (vectors and the stack page are left alone). Preserves A.
clear_ram:
        push af
        ld hl, $0100
        ld de, $0101
        ld bc, $7F00-$0101
        ld (hl), 0
        ldir
        pop af
        ret

; Map each switchable bank and check its id byte. Out: A = 1 if all matched.
bank_test:
        ld b, 0
.next:  ld a, b
        call select_bank
        ld a, ($C000)
        cp b
        jr nz, .fail
        inc b
        ld a, b
        cp MC_FIXED
        jr nz, .next
        ld a, 1
        ret
.fail:  xor a
        ret

; A = bank number -> mapped at $C000-$FFFF. Clobbers HL.
select_bank:
        ld (cur_bank), a
        add a, low MC_HOTSPOT
        ld l, a
        ld h, high MC_HOTSPOT
        ld a, (hl)
        ret

; -----------------------------------------------------------------------------
sn_silence:
        ld a, $9F
        ld b, 4
.ch:    out (SN_PORT), a
        add a, $20
        djnz .ch
        ret

; Joystick 1 -> joy1, active high (bit0 up, 1 right, 2 down, 3 left, 6 fire).
read_joy1:
        out (CTL_SEL_JOY), a
        in a, (CTL_P1)
        cpl
        and $4F
        ld (joy1), a
        ret

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
; Text. Tiles follow the arcade font: 0-9 = $00-$09, A-Z = $0A-$23, blank = $24.
T_BLANK equ $24

; HL = zero-terminated ASCII string, DE = destination buffer. Returns DE past it.
ascii_to_tiles:
.loop:  ld a, (hl)
        or a
        ret z
        inc hl
        cp ' '
        jr z, .blank
        cp 'A'
        jr c, .digit
        sub 'A'-10
        jr .put
.digit: sub '0'
        jr .put
.blank: ld a, T_BLANK
.put:   ld (de), a
        inc de
        jr .loop

; HL = VRAM address, DE = ASCII string. Init-time only.
print_vram:
        push de
        ld de, text_line
        ex (sp), hl             ; HL = string, stack = VRAM address
        call ascii_to_tiles
        ld hl, text_line
        ex de, hl
        or a
        sbc hl, de              ; HL = tile count
        ld b, h
        ld c, l
        pop hl
        ld de, text_line
        jp vdp_copy

; Status labels: (row, string) pairs, then the per-check verdicts.
draw_test_screen:
        ld hl, VR_PNT + 2*32 + 2
        ld de, s_title
        call print_vram
        ld hl, VR_PNT + 4*32 + 2
        ld de, s_ram
        call print_vram
        ld hl, VR_PNT + 4*32 + 16
        ld de, s_ok
        ld a, (ram_ok)
        or a
        jr nz, .r
        ld de, s_fail
.r:     call print_vram
        ld hl, VR_PNT + 6*32 + 2
        ld de, s_bank
        call print_vram
        ld hl, VR_PNT + 6*32 + 16
        ld de, s_ok
        ld a, (bank_ok)
        or a
        jr nz, .b
        ld de, s_fail
.b:     call print_vram
        ret

; text_line = "FRAME hhhh  JOY hh" for the NMI to flush.
build_status_line:
        ld hl, s_frame
        ld de, text_line + 2
        call ascii_to_tiles
        ld a, (frame_cnt+1)
        call hex_byte
        ld a, (frame_cnt)
        call hex_byte
        ld hl, s_joy
        call ascii_to_tiles
        ld a, (joy1)
        call hex_byte
        ld a, T_BLANK
        ld (text_line), a
        ld (text_line+1), a
        ret

; A -> two hex tiles at DE (font tiles $00-$0F are 0-9A-F).
hex_byte:
        push af
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld (de), a
        inc de
        pop af
        and $0F
        ld (de), a
        inc de
        ret

s_title: db "MR DO ARCADE PORT  PHASE 0", 0
s_ram:   db "SGM RAM", 0
s_bank:  db "MEGACART", 0
s_ok:    db "OK", 0
s_fail:  db "FAIL", 0
s_frame: db "FRAME ", 0
s_joy:   db "  JOY ", 0
s_nosgm1: db "SUPER GAME MODULE REQUIRED", 0
s_nosgm2: db "PLEASE CONNECT", 0

font:   incbin "build/font.bin"
font_len equ $-font

        ds $C000-$, $FF
        outend
