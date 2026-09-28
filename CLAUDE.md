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
- **Camera and Screen 2 thirds:** all three thirds share ONE pattern table ($0000) and ONE colour table ($2000) through the R4/R3 masks (R4=$00, R3=$9F), so a camera shift needs no tile moves and a tile set is 2 x 1792 bytes. Nothing may write per-third tile data.
- **VRAM free for tables:** $0800-$13FF (IDC uses $0800+) and $2800-$37FF; $1400-$16FF is the second name table.
- **Two name tables** ($1800 and $1400, R2 flips): a full redraw (camera move, new tile set, queue overflow) is drawn into the hidden one, then cells queued up to that point (`flip_mark`) are drained into it too, then R2 flips. While the arcade bulk-repaints (queue overflowing, >= 16 writes per vblank) the redraw waits, so no half-painted picture is ever shown. A tile-set change uploads both tables in one NMI with the display blanked and the backdrop in the new set's main colour (~1 frame). The HUD panel (cols 24-31) must be written to BOTH name tables.
- **Sprites:** one colour per sprite for now; upgrade (e.g. a two-colour Mr. Do) only once the game runs at full speed with the complete logic. All rotations and flips are pre-drawn in ROM (the TMS9918 cannot flip).
- **Design load:** 7 monsters + 3 chompers + Mr. Do + ball + 5 apples on screen at once.
- **4-per-line limit:** this is the TMS9918's own limit; the SGM does not change the video chip. Strategy:
  1. Take objects out of the sprite list where it's cheap: draw grid-aligned static objects (e.g. resting apples) as background tiles, using SGM RAM for the extra tile data.
  2. Multiplex the rest (src/sprites.asm): count sprites per 8-line band; with no band at 5+, the SAT goes out in list order (no flicker at all). Otherwise: pinned sprites first (Mr. Do, codes $00-$26 via build/sprites/pin.bin), then sprites in uncrowded bands (never flicker), then the crowded ones rotated 3 places per frame in arcade order. The full row-cluster sort was tried and cost too much CPU; tools/flicker_sim.py shows crowded-rotate-3 matches it except the 5-in-a-row case.
  3. Draw one in four ball-code ($70) sprites: the ball's 20-fragment burst (and its re-form) was ~42k T-states per frame. Visual only; the logic is untouched.
  4. SAT writes are spaced >= 30 T-states apart because the sprite pass can run past the end of vblank, where the TMS9918 drops faster writes.

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
- **Pathfinder starvation guard** (`take_irq`, normal build only): when the handler overruns every frame (chomper session: 62-88k T with our NMI), each held vblank is taken at the handler's own exit, so the background pathfinder never runs an instruction and monsters/chompers never get a route (they sat in the nest). After 2 back-to-back held deliveries that would preempt real background work (a pathfinder `call`, or a `ret` into anything but the idle loops $00AC/$0154) the 3rd is skipped (`pf_drops` counts them); the background then runs until the next NMI. Ordinary play: 0 skips in 21 s; a forced chomper session: ~35 skips in its heaviest 4 s. The real fix is the hotspot work below.
- Port consequence: the CV vblank is an NMI (unmaskable). The NMI handler must copy the RAM buffers to VRAM first. It then runs the arcade handler only if that handler is not already running; if it is, it sets a pending flag, which the translated code services at its `ei` points (this imitates the level-held IRQ). The pathfinder's context discard and SP reset must be kept exactly.

## Target hardware
- ColecoVision + Super Game Module, on MegaCart cartridge boards. The user has an SGM and a flash cart for testing real-hardware builds; test on hardware as soon as the renderer exists (the VDP needs ~8µs between VRAM writes during active display, and openMSX doesn't enforce it strictly).
- The game must detect a missing SGM and show a "Super Game Module required" screen.

## How the arcade program runs (Phase 1)
- The arcade main ROM runs at its ORIGINAL addresses: `tools/patch_arcade.py` copies $0000-$5FFF into SGM RAM and rewrites only operands that point at moved things (work RAM $E000->$6000, video $8000->$7000, I/O and scroll -> RAM cells, sound data and scene code $6000-$7FFF -> MegaCart window bank 0). Instruction lengths and timing are unchanged. Every patch is listed in `build/arc_patches.txt`.
- The code map (`tools/codemap.py`) seeds from the Ghidra entries (`tools/data/ghidra_functions.txt`) plus jump-table targets and every instruction MAME executed (`tools/data/extra_entries.txt`). Code missing from the map is left unpatched. That caused a real bug (jump-table state handlers), so after any sweep, re-check that "executed but unmapped" is 0.
- Constants that only look like addresses (sprite code/colour pairs, positions, bit masks, negative offsets such as `$FFE0`) are listed in `KEEP_IMM` after review. Values of $F000 and up are never relocated unless they are exact scroll-register memory operands.
- Vblank: every arcade `ei` became `rst $08`. The NMI either enters the arcade handler directly (interrupts were on) or holds the vblank by rewriting $0008 to `jp take_irq`. Delivery mimics the Z80's one-instruction EI delay (`irq_after_ei` finishes the `ret` or `call` that follows the `ei`); the arcade's `ld sp,$EB76` resume path depends on the exact stack layout.
- **MegaCart hotspot:** reading $FFC0-$FFFF switches banks, so no switchable bank may keep data in its last 64 bytes. `tools/check_rom.py` enforces this on every build. The arcade image is stored 8KB per bank.
- Arcade writes into ROM addresses are ignored on the board but would corrupt our RAM copy of the code. The known one ($1761, write to $DC1A) is patched out.

## Lockstep validation
- `make validate FRAMES=n SEED=s` records n vblank handlers in MAME (`tools/diff/mame_record.lua`, scripted random play), replays the same inputs on `build/mrdo_validate.rom` in openMSX (`tools/diff/cv_replay.tcl`), and compares work RAM plus video RAM at the same sync point of every handler (`tools/diff/compare.py`). Relocated pointers held in RAM compare as equal.
- Validation mode runs the background pathfinder to completion with the vblank held off, identically in both emulators. Otherwise the result depends on CPU speed (the arcade's pathfinder progress per frame is a function of its 4 MHz Z80) and the RAM diverges for timing reasons alone.
- MAME inputs are injected by the read tap and latched at handler start. MAME's own input system updates once per frame, which can land mid-handler.
- Non-gameplay screens (title, instruction) are captured from MAME with `tools/capture_screen.py NAME CAM REC:first-last --not REC:ranges` (`NOCOIN=1 NOSTART=1` recordings leave the attract sequence running) and listed in `SCREENS` in tools/gen_screens.py; the first signature match wins, so a screen whose signature also shows elsewhere (the title's logo) goes last.
- **Cutscenes with scrolling art** (src/scene.asm): the arcade scrolls the whole bg layer ($F800, along the player-view x axis) under the fixed fg text; the characters sit in a few band rows with no fg over them. Captured with `tools/capture/scene_record.lua` (per video frame + scroll log; SCEN=vg pokes a VERY GOOD round end) and `capture_screen.py NAME CAM scene:PREFIX:f0-f1 --band R0-R1 --not ...`. gen_screens pre-shifts every (left, right) bg pair to phases 0/2/4/6 in one bank per scene (hash by `pkey`). Runtime: per band row a 32-bit art mask + a VRAM cache (IDC, $0800) of the pair id per native row, invalidated by scene_mark on arcade writes and looked up lazily; a build gives each art cell the next slot of the off-screen slot bank (2 x 70 codes after the static set), then the next vblank flushes tiles (back to back inside vblank, spaced after) and names. 2-pixel steps; heavy builds (> 24 tiles) split the flush and build over more vblanks. VERY GOOD: 467 vblanks for the arcade's 421 handlers (finale ~94% speed).
- RAM validation cannot see rendering bugs. `tools/diff/compare_frames.sh SEED CAM H1 H2 ...` captures MAME and the normal build at the same handlers and writes a side-by-side sheet (build/frames.png) with a per-frame pixel agreement (baseline ~81% with correct sprites; a sprite placement bug shows up at a glance).
- Debug aids (env vars): `WATCH=addr` (MAME: arcade address; openMSX: CV address) logs writes with PC and handler; `RTRACE`, `ITRACE`, `HTRACE` trace fg-tile reads, input reads and handler entries.

## Build and test
- **Always run MAME with `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy`** (plus `-video none -sound none`). Without it MAME activates as a macOS GUI app and pulls the user's screen to another Space. Recordings and `-snapshot_directory` screenshots work the same. openMSX is fine as is.
- `make`: SjASMPlus builds `build/mrdo.rom` (256KB MegaCart image). `make run` starts openMSX. `make test` boots headless-ish for 4 emulated seconds, prints the self-test verdicts and saves `build/boot.png`.
- openMSX machine `ColecoVision_SGM`, romtype `ColecoMegaCart`. openMSX Tcl scripts read symbols from `build/mrdo.sym`. Set `throttle on` for a few frames before `screenshot`, otherwise the capture is black.
- Generated data goes to `build/` (created by `tools/*.py`, which import the do_disassemble tools via `$DO_DISASM`, default `~/work/do_disassemble`).

## Hardware layout (see `src/hw.inc`)
- MegaCart: the last 16KB bank is fixed at $8000-$BFFF; reading $FFC0+n maps bank n at $C000-$FFFF. Bank-switching code runs from the fixed bank or RAM.
- SGM: `out ($53),1` gives 24KB RAM at $2000-$7FFF; `out ($7F),$0D` swaps the BIOS out for 8KB RAM at $0000-$1FFF. After boot the BIOS is gone; our vectors live at $0000/$0038/$0066.
- VRAM: PT $0000, PNT $1800, SAT $1B00, CT $2000 (full 6KB), SPT $3800.
- Once the display is on, only the NMI (vblank) handler touches the VDP. The main loop works in RAM buffers.
- Arcade work RAM $E000-$EFFF is rebased to $6000-$6FFF (same low 12 bits) so emulator RAM dumps can be diffed against MAME directly.
