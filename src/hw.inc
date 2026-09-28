; =============================================================================
; hw.inc - ColecoVision + Super Game Module + MegaCart hardware definitions
; =============================================================================

; --- TMS9918A VDP -------------------------------------------------------------
VDP_DATA        equ $BE
VDP_CTRL        equ $BF         ; write: address/register, read: status (acks NMI)

; VRAM layout (Screen 2 / Graphics II, full 6KB colour table)
VR_PT           equ $0000       ; pattern table, 3 thirds x 256 x 8
VR_PNT          equ $1800       ; name table, 32 x 24
VR_SAT          equ $1B00       ; sprite attribute table, 32 x 4
VR_CT           equ $2000       ; colour table, 3 thirds x 256 x 8
VR_SPT          equ $3800       ; sprite pattern table, 64 x 32 (16x16 sprites)

; Register values for the layout above
VDP_R0          equ $02         ; M3 = Graphics II
VDP_R1_OFF      equ $82         ; 16K, display blanked, VDP interrupt off, 16x16 sprites
VDP_R1_ON       equ $E2         ; 16K, display on, VDP interrupt (NMI) on, 16x16 sprites
VDP_R2          equ VR_PNT/$400
VDP_R3          equ $FF         ; colour table at $2000, full mask
VDP_R4          equ $03         ; pattern table at $0000, full mask
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
MC_BANKS        equ 8           ; 128KB image; raise as content grows
MC_FIXED        equ MC_BANKS-1

; --- SGM RAM map ------------------------------------------------------------------
; $0000-$00FF  Z80 vectors (installed at boot once the BIOS is swapped out)
; $6000-$6FFF  arcade work RAM ($E000-$EFFF), same low 12 bits  [phase 1]
; $7C00-$7EFF  driver variables
; $7F00-$7FFF  stack (grows down from $8000)
ARC_WORK        equ $6000
DRV_RAM         equ $7C00
STACK_TOP       equ $8000
