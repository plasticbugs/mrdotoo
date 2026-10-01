; =============================================================================
; options.asm - the DIP switch options screen (keypad *, attract only)
; =============================================================================
; The MSX2 port's options screen, on the ColecoVision: four of the arcade's
; DSW1 settings (bit map from the disassembly, msx/mrdo_msx.asm):
;   LIVES       bits 7-6   $00 = 2, $C0 = 3, $80 = 4, $40 = 5
;   EXTRA       bit 4      1 = easy (alpha monster tables $43EC/$4428)
;   SPECIAL     bit 3      1 = easy (diamond odds $50D6)
;   DIFFICULTY  bits 1-0   $03 = 1 (average) .. $00 = 4 (hard)
; Other bits (cabinet, rack test) keep DSW1_DEFAULT. The arcade reads DSW1
; through IO_DSW1, which read_inputs refreshes every vblank from opt_dsw1:
; difficulty, EXTRA and SPECIAL apply at once, lives at the next game start.
;
; Keypad * opens it while the arcade is in attract mode (no game, no credit:
; $E000 bit 7 clear, $E006 = 0). While it is up the NMI draws only this
; screen and delivers no vblank to the arcade (it waits in its idle loop).
; Up / down pick a row, left / right change it, * or fire leaves: the
; renderer then forgets what it showed and rebuilds the attract screen.
; # inserts coins now (main.asm read_inputs).
; =============================================================================
opt_dsw1        equ $59CC           ; ROM $FF padding after snd_req (the load
opt_on          equ $59CD           ; copies $FF over it: opt_init after)
opt_sel         equ $59CE           ;   0 closed, 1 opening, 2 open; row 0-3
opt_prev        equ $59CF           ;   joystick bits last vblank (edges)
        assert opt_prev < DRV_RAM
OPT_BANK        equ MC_FIXED-3      ; options_b.asm (the free bank before the images)
OPT_ROWS        equ 4
OPT_ARROW       equ $26             ; the cursor glyph (after T_DOT)
        assert OPT_ARROW * 8 == font_len
OPT_CUR_X       equ 5               ; cursor column
OPT_LBL_X       equ 7               ; label column
OPT_VAL_X       equ 20              ; value column
OPT_ROW0        equ 8               ; screen row of LIVES (rows 2 apart)

opt_init:
        ld a, DSW1_DEFAULT
        ld (opt_dsw1), a
        xor a
        ld (opt_on), a
        ld (opt_sel), a
        ret

; From read_inputs: keypad * pressed. Opens the screen in attract mode.
opt_request:
        ld a, (ARC_WORK)
        and $80
        ret nz                  ; a game is on
        ld a, (ARC_WORK + 6)
        or a
        ret nz                  ; a credit is in
        ld a, (opt_on)
        or a
        ret nz
        inc a
        ld (opt_on), a
        ret

; From the NMI (A = opt_on, nonzero; the NMI's AF BC DE HL pushed): this
; vblank's work while the screen is up, then the NMI ends without the
; arcade's vblank.
opt_nmi:
        ld a, (cur_bank)        ; (the screen's code and texts: OPT_BANK,
        push af                 ; options_b.asm)
        ld a, OPT_BANK
        call select_bank
        ld a, (opt_on)
        cp 1
        call z, opt_open
        call opt_input
        pop af
        call select_bank
        xor a
        ld (in_nmi), a
        call late_ack
        pop hl
        pop de
        pop bc
        pop af
        retn

; Display blanked: font, cleared names, no sprites, the texts; then on.
