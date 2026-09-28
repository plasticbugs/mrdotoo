# CLAUDE.md

Arcade-faithful port of Mr. Do! (Universal 1982) to the ColecoVision + Super Game Module.

## Priorities (in order)
1. The complete arcade game logic, behaving identically to the arcade.
2. Full speed (60 Hz).
3. Graphics. One-colour sprites and simplified art are acceptable when they buy 1 or 2.

## Sources of truth
- `~/work/do_disassemble/mrdo_main.bin`: the arcade main-CPU ROM. This is the reference for all logic.
- `~/work/do_disassemble/msx/mrdo_msx.asm`: MSX2 port with the arcade code translated. Use it for hook points, known pitfalls and bug fixes; its renderer (V9938 bitmap) does not apply here.
- `~/work/do_disassemble/tools/`: Python tools (arcade gfx decode, level composition, `mrdo_xlate.py` translator, CV maze/sprite asset experiments).
- `~/work/mrdoarcade` branch `feat/arcade-logic-sgm`: an earlier CV+SGM attempt. Its sound engine (`mrdo_snd.asm`) plays the arcade note streams on the SN76489 plus the SGM AY. It uses tniASM syntax and a trimmed 12-row maze; do not copy the trim.

## Decisions
- **Playfield:** all 13 arcade cell rows are kept (208px of play area against 192px of screen). An 8px-step vertical camera (offsets 0/8/16) follows Mr. Do. The logic and maze data stay byte-identical to the arcade; all screen fitting happens in the renderer. Never trim rows or patch coordinates in the logic.
- **HUD:** the playfield is 24 tiles wide (cols 0-23); score, lives and EXTRA go in the 64px panel (cols 24-31).
- **Camera and Screen 2 thirds:** a camera shift moves tiles between pattern-table thirds, so all three thirds hold the same playfield tile set.
- **Sprites:** one colour per sprite for now; upgrade (e.g. a two-colour Mr. Do) only once the game runs at full speed with the complete logic. All rotations and flips are pre-drawn in ROM (the TMS9918 cannot flip).
- **Design load:** 7 monsters + 3 chompers + Mr. Do + ball + 5 apples on screen at once.
- **4-per-line limit:** this is the TMS9918's own limit; the SGM does not change the video chip. Strategy:
  1. Take objects out of the sprite list where it's cheap: draw grid-aligned static objects (e.g. resting apples) as background tiles, using SGM RAM for the extra tile data.
  2. Multiplex the rest with the row-cluster scheme: sort by player-view Y; group sprites whose 16px spans chain-overlap; a group larger than the free places on its line (4 minus pinned sprites there) rotates each frame, advancing by that number of free places; groups that fit keep a stable order and never flicker. Mr. Do is pinned first.
  3. Simulated against the romhack's +4 rotation: 5 in a row goes from a worst sprite at 20% visible to 80% (ideal); 11 in a row from 20% to 36% (ideal); sprites on uncrowded lines never flicker. Simulator: tools/flicker_sim.py.

## Arcade execution model (measured in MAME, 2026-09-27)
- Z80 4.1 MHz, 59.943 Hz: 68,398 cycles/frame. CV: 3.58 MHz, 59,659 T-states/frame.
- IM1; $0038 → IRQ handler $00B8. The main loop is only `jr $` at $00AC. All logic runs in the handler, which runs with interrupts off. The arcade IRQ is level-held, so an overrunning frame's IRQ fires as soon as `ei` runs.
- At handler exit, flags in $E001 either return ($0136) or discard the interrupted context and start the background pathfinder with interrupts on ($0138→$54EC maze search, $0141→$558E, $014D→$5647, which ends in a second idle loop at $0154). The pathfinder sets SP to $EB80/$EB76; the stack starts at $EB80.
- Map: $8000-$87FF bg video RAM, $8800-$8FFF fg video RAM, $9000-$90FF sprite RAM, $9800 flip, $9801/$9802 SN76489 x2, $9803 protection PAL, $A000-$A003 inputs/DIP switches, $E000-$EFFF work RAM, $F000/$F800 scroll.
- Gameplay handler cost: mean ~30.6k, p95 44.8k, max 73.2k cycles, so it fits the CV frame except about 0.1-0.4% of frames. The pathfinder takes about 56k cycles every ~30 frames and delivers results ~1 frame later than on the arcade.
- **Worst case** (level 5+, 8 monster slots, not 7; invincibility pokes in MAME): 8 monsters idle, median 63.7k / p95 70.3k; 8 monsters + 3 chompers, median 52.6k / max 79.7k; 6+ monsters + a falling apple, median 54.5k. Cost is about 6-7k cycles per monster. The unmodified logic cannot hold 60 Hz on the CV in heavy rounds (the budget is ~54k after VDP work). Hot routines must be hand-optimised, with the frame-by-frame RAM diff against MAME proving they behave identically.
- **Hotspots** (8 monsters idle, 66k/frame; profile in tools/profile): actor_update $3231 is 67% inclusive. Most of that is 12-slot object-table scans through IY, repeated for every monster: $1F78 apple_wobble 8.6k, $40AA monster-vs-objects 10.4k excl., $41EC/$48F2 chomper scans 5.5k/6.0k. Then the sound tick $5A90 (IX bit tests over 38 slots) 4.3k, and queue sprite $0297 + upload $026D 7.6k (replaced by our own sprite path). Target saving is about 12k per frame for the median and 16-17k for p95.
- **Optimisation rule:** a rewritten routine must leave arcade work RAM ($6000-$6FFF mirror) byte-identical to MAME every frame. Speed-up side structures (e.g. an active-object list) live outside that mirror and are maintained at every write site.
- Sprite queue at $E311 (copied verbatim to $9000 by $026E): byte 0 code, 1 Y (drawn at 256-Y, 0 = unused), 2 colour (low nibble) + flip bits $10/$20, 3 X. Player-view row = constant arcade X. Apples are sprites (code $5E). Live sprites: normal play max 31 / p99 22; worst row normal play p99 5, max 9. 20 × code $70 fragments appear when the ball re-forms. Distinct (code, flip) per round can reach 187, so the SPT needs a per-frame cache (~17 new per frame at most), not a static set.
- Port consequence: the CV vblank is an NMI (unmaskable). The NMI handler must copy the RAM buffers to VRAM first. It then runs the arcade handler only if that handler is not already running; if it is, it sets a pending flag, which the translated code services at its `ei` points (this imitates the level-held IRQ). The pathfinder's context discard and SP reset must be kept exactly.

## Target hardware
- ColecoVision + Super Game Module, on MegaCart cartridge boards. The user has an SGM and a flash cart for testing real-hardware builds; test on hardware as soon as the renderer exists (the VDP needs ~8µs between VRAM writes during active display, and openMSX doesn't enforce it strictly).
- The game must detect a missing SGM and show a "Super Game Module required" screen.

## Build and test
- `make`: SjASMPlus builds `build/mrdo.rom` (128KB MegaCart image). `make run` starts openMSX. `make test` boots headless-ish for 4 emulated seconds, prints the self-test verdicts and saves `build/boot.png`.
- openMSX machine `ColecoVision_SGM`, romtype `ColecoMegaCart`. openMSX Tcl scripts read symbols from `build/mrdo.sym`. Set `throttle on` for a few frames before `screenshot`, otherwise the capture is black.
- Generated data goes to `build/` (created by `tools/*.py`, which import the do_disassemble tools via `$DO_DISASM`, default `~/work/do_disassemble`).

## Hardware layout (see `src/hw.inc`)
- MegaCart: the last 16KB bank is fixed at $8000-$BFFF; reading $FFC0+n maps bank n at $C000-$FFFF. Bank-switching code runs from the fixed bank or RAM.
- SGM: `out ($53),1` gives 24KB RAM at $2000-$7FFF; `out ($7F),$0D` swaps the BIOS out for 8KB RAM at $0000-$1FFF. After boot the BIOS is gone; our vectors live at $0000/$0038/$0066.
- VRAM: PT $0000, PNT $1800, SAT $1B00, CT $2000 (full 6KB), SPT $3800.
- Once the display is on, only the NMI (vblank) handler touches the VDP. The main loop works in RAM buffers.
- Arcade work RAM $E000-$EFFF is rebased to $6000-$6FFF (same low 12 bits) so emulator RAM dumps can be diffed against MAME directly.
