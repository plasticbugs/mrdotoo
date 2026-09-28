; =============================================================================
; hw.inc - ColecoVision + Super Game Module + MegaCart hardware definitions
; =============================================================================

; --- TMS9918A VDP -------------------------------------------------------------
VDP_DATA        equ $BE
VDP_CTRL        equ $BF         ; write: address/register, read: status (acks NMI)

; VRAM layout (Screen 2 / Graphics II, full 6KB colour table)
VR_PT           equ $0000       ; pattern table, 3 thirds x 256 x 8
VR_PNT          equ $1800       ; name table, 32 x 24
VR_PNT2         equ $1400       ; second name table (full redraws; free with shared thirds)
VR_SAT          equ $1B00       ; sprite attribute table, 32 x 4
VR_CT           equ $2000       ; colour table, 3 thirds x 256 x 8
VR_SPT          equ $3800       ; sprite pattern table, 64 x 32 (16x16 sprites)

; Register values for the layout above
VDP_R0          equ $02         ; M3 = Graphics II
VDP_R1_OFF      equ $82         ; 16K, display blanked, VDP interrupt off, 16x16 sprites
VDP_R1_ON       equ $E2         ; 16K, display on, VDP interrupt (NMI) on, 16x16 sprites
VDP_R2          equ VR_PNT/$400
VDP_R3          equ $9F         ; colour table at $2000, one 2KB table for all thirds
VDP_R4          equ $00         ; pattern table at $0000, one 2KB table for all thirds
VDP_R5          equ VR_SAT/$80
VDP_R6          equ VR_SPT/$800
VDP_R7          equ $01         ; border black

SAT_END         equ $D0         ; Y value that terminates the sprite list

; --- SN76489 (ColecoVision sound) ---------------------------------------------
SN_PORT         equ $FF

; --- Controllers ----------------------------------------------------------------
CTL_SEL_KEYPAD  equ $80         ; any write selects keypad mode
CTL_SEL_JOY     equ $C0         ; any write selects joystick mode
CTL_P1          equ $FC         ; read, active low
CTL_P2          equ $FF
; joystick-mode bits (active low): 0 up, 1 right, 2 down, 3 left, 6 left fire

; --- Super Game Module ------------------------------------------------------------
SGM_AY_ADDR     equ $50
SGM_AY_WRITE    equ $51
SGM_AY_READ     equ $52
SGM_UPPER       equ $53         ; bit0 = 1: 24KB RAM at $2000-$7FFF
SGM_LOWER       equ $7F         ; $0F: BIOS at $0000-$1FFF, $0D: 8KB RAM there

; --- MegaCart -----------------------------------------------------------------------
; The LAST 16KB bank of the image is fixed at $8000-$BFFF. Reading $FFC0+n maps
; bank n into $C000-$FFFF. Switching code must live in the fixed bank or in RAM.
MC_HOTSPOT      equ $FFC0
MC_BANKS        equ 32          ; 512KB image
MC_FIXED        equ MC_BANKS-1

; --- Memory map at run time (see tools/patch_arcade.py) -----------------------------
; $0000-$5FFF  RAM: arcade code + tables at their ORIGINAL addresses (patched copy)
;              $0008 = pending-vblank hook (the arcade's `ei`s became `rst $08`)
;              $0066 = our NMI vector (arcade had `retn` there)
;              $56AF-$59BF = driver RAM: the arcade's DIP-switch test code, never
;                            run (entered only with both fire buttons held at boot)
;                            $5700-$57FF = renderer dirty-cell queue
;              $59D0-$5A7F = driver variables (unused $FF padding in the arcade ROM)
; $6000-$6FFF  RAM: arcade work RAM ($E000-$EFFF); arcade stack tops at $6B80
;              $63B0-$63B9 = I/O cells ($9800-3, $A000-3, scroll $F000/$F800)
;              $6950-$6A4F = arcade sprite RAM copy ($9000-$90FF)
; $7000-$7FFF  RAM: arcade video RAM ($8000-$8FFF); fg tiles at $7C00
; $8000-$BFFF  ROM fixed bank: this driver
; $C000-$DFFF  ROM window, bank ARC_HI_BANK: arcade $6000-$7FFF (sound data + scenes)
ARC_WORK        equ $6000
ARC_VRAM        equ $7000
ARC_FG_TILE     equ ARC_VRAM + $0C00
ARC_SPRITES     equ $6950
IO_CELLS        equ $63B0
IO_FLIP         equ IO_CELLS+0
IO_IN0          equ IO_CELLS+4      ; P1: 0 left 1 down 2 right 3 up 4 fire 5 1P start 6 2P start 7 tilt
IO_IN1          equ IO_CELLS+5      ; P2: same, 6 coin 1, 7 coin 2 (all active low)
IO_DSW1         equ IO_CELLS+6
IO_DSW2         equ IO_CELLS+7
IO_SCROLL_X     equ IO_CELLS+8
IO_SCROLL_Y     equ IO_CELLS+9
DSW1_DEFAULT    equ $DF             ; MAME defaults: upright, 3 lives, normal difficulty
DSW2_DEFAULT    equ $FF             ; 1 coin 1 credit
DRV_RAM         equ $59D0
DRV_RAM_END     equ $5A80
ARC_IRQ         equ $00B8           ; arcade vblank handler
ARC_RESET       equ $0000
BOOT_STACK      equ $6B80
