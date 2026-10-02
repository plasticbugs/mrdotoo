# Progress artifacts

A record of the port's progress: screenshots, previews and (later) audio
recordings, one folder per milestone. Files here are committed; `build/` is not.

| Folder | Milestone |
|---|---|
| `01-phase0-boot` | CV + SGM + MegaCart skeleton boots; SGM-required screen |
| `02-phase1-arcade-logic` | The arcade program runs on the ColecoVision (debug text view of the arcade's foreground layer); lockstep-identical to MAME for 3 x 20,000 frames |
| `03-phase2-renderer` | The real playfield renderer: arcade tiles converted to Screen 2 |
| `05-title-and-hud` | Title screen via per-screen tile sets; the HUD panel |
| `04-hack-art-and-multiplexer` | CV-romhack art for monsters, diggers, apples, desserts and cherries; flicker multiplexer; thinned ball burst |

## 03-phase2-renderer
- `tileset-preview-scene1-midgame.png`: offline preview; a recorded arcade frame rendered through the generated tables (before any Z80 code existed).
- `first-render-game-start.png`: first real render on the ColecoVision (openMSX); camera at the bottom position because Mr. Do starts in the bottom row.
- `first-render-scene1-dug-tunnel.png`: the same game after Mr. Do dug right and up; the tunnel is drawn tile by tile from the arcade's own writes, and the camera has moved back to the middle.
- `sprite-sheet-one-colour.png`: all 128 arcade sprite codes converted to one-colour TMS9918 sprites (shape = non-black pixels, colour = dominant colour).
- `first-sprites-handler1800.png`, `arcade-vs-colecovision-handler1800.png`: first sprites; the same moment (handler 1800, identical inputs) in MAME (left) and on the ColecoVision (right). Tiles agree 98.7% pixel-for-pixel; every apple and monster is at the arcade's position.
- `sprites-in-play.png`: scripted game with sprites, after the sprite pass was optimized (per-entry cache, SAT streamed in vblank).
- `multiplexer-arcade-vs-cv-1477-1480.png`: four consecutive frames with up to 6 sprites on one scanline, arcade (top) vs ColecoVision (bottom): every apple, monster and Mr. Do stays visible; only the crowded rows rotate.

## 04-hack-art-and-multiplexer
- `sprite-mapping-arcade-vs-hack.png`: every arcade sprite code next to the CV-romhack art chosen for it (tools/gen_sprites_hack.py). Mr. Do, alpha monster, chompers, ball, diamond and score signs stay arcade.
- `tiles-preview-hack-cherries.png`: the romhack's cherries composited over the level dirt.
- `gameplay-hack-sprites-and-cherries.png`: scripted game with the new art.
- `ball-burst-half-fragments.png`: the ball's 20-fragment burst drawn as 10 (visual only; the logic still runs all 20). The burst frame's driver cost fell from ~42k to ~19k T-states.

## 05-title-and-hud
- `title-screen.png`, `title-screen-colour-cycle.png`: the arcade title rendered on the ColecoVision straight after power-on (previously ~8 s of black while the arcade ran its title unseen). Non-gameplay screens use captured per-screen tile sets (tools/capture_screen.py, tools/gen_screens.py) with a hashed cell lookup; the logo's colour cycling animates as on the arcade.
- `sprite-fix-arcade-vs-cv-760-1000.png`: after fixing the sprite X bug (the ball-fragment check clobbered the Y value): arcade (top) vs ColecoVision normal build (bottom) at the same handlers. Arcade cherries restored.
- `06-chomper-red-desserts/`: chomper mode (after the dessert) paints the playfield red instead of black; dessert plates drawn as background tiles. Left arcade (MAME), right CV (validation build), same handlers.
- `07-hack-desserts/`: dessert as the romhack's full-colour tiles (arcade left, CV right); chomper session stuck in the nest before the pathfinder starvation guard, and moving after it.
- `08-no-black-flash/`: green-to-red chomper transition in one step (arcade top, CV bottom; one flat red frame during the tile upload); the instruction screen as its own captured screen set; a forced chomper session with the chompers out of the nest.
- `09-very-good-cutscene/`: the high-score table and WONDERFUL as captured screen sets; the VERY GOOD cutscene with the arcade's scrolling characters (pre-shifted pair tiles streamed each build); a simulation of the ROM tables against the arcade render; the sequence on the CV.
- `10-all-cutscenes/`: diamond (SPECIAL) and EXTRA scenes as captured screens, after the logic fixes that made their text appear (unrelocated scene records, broken ROM checksums).
- `11-speed-and-vg-fix/`: consecutive VERY GOOD finale frames after the fix (no torn characters): spaced VRAM writes, whole-band builds between arcade frames.
- `12-sprites/`: the romhack's blue chompers mapped onto arcade codes $27-$2A (white chompers stay arcade); two-colour Mr. Do; the romhack's EXTRA screen with its waving flag.
- `13-sound/`: the arcade's own sound engine on the CV SN76489 + SGM AY (chip 1 -> SN, chip 2 -> AY, periods scaled 7/8). Game start on MAME vs the CV; a heavy level-5 round where the logic runs at ~62% speed but the music keeps tempo (the sound tick runs from the NMI every vblank).
- `14-score-ovals/`: the kill / dessert score ovals (codes $72-$77, arcade colour line $0A: white digits on a black oval) as one white sprite with the digits cut out, over dirt and tunnel. Before, the whole oval was one solid white block.
- `15-hud/`: the HUD panel (screen columns 24-31, MSX2 layout): 1ST + score, EXTRA box (grey / lit / blinking letters), SCENE, TOP + top score, lives (2ND and its score in 2-player games), all mirrored from the arcade's own HUD cells; the dessert drawn from on-demand plate tiles (which freed the HUD's tile codes).
- `15-hud/hiscore_entry_letter.png`: the name-entry row with the initial being chosen (fg attr $22, full font incl. the heart and '.') now in the high-score screen's tile set.
- `15-hud/next_letter_marker.png`: the next EXTRA letter (the arcade's letter-monster sprite on the box) marked white on blue in the panel.
- `09-very-good-cutscene/vg_landed_romhack_frame1/2.png`: once VERY GOOD's characters land, the romhack's picture (tiles + black cover sprites, two frames) replaces the arcade tiles; `vg_arriving_arcade_tiles.png` is the scroll-in just before.
- `16-extra-pan/`: EXTRA: the romhack picture from the scene's first frame, its landscape panning 8 tiles in step with the arcade's scroll (CV frames every 0.1 s), and the arcade's pan in MAME for reference.
- `09-very-good-cutscene/vg_romhack_characters_sequence.png`: the letter monster in arcade tiles, then the romhack's dinosaur, apple and Mr. Do walking in (8-pixel steps) and landing; `vg_ending_to_black_to_level.png`: landed, black while the next level is drawn, scene 4 (0.5 s instead of 3.5 s).
- `12-sprites/mrdo_death_last_frames_red_white.png`: Mr. Do's last death frames; $26 (halo) was all white (white is its dominant colour), now red with the white overlay like the others.
- `17-title-logo/`: the romhack's animated "Mr. Do!" logo (colour bars) on the title and above the instruction screen, replacing the arcade logo capture.
- `10-all-cutscenes/diamond_romhack_clown_frames.png`: the diamond scene's clown and diamond from the romhack (three diamond frames, its sprites); `diamond_scene_credit_1.png`: the credit counted after the coin drops.
- `10-all-cutscenes/diamond_token_on_top.png`: the arcade's dropping credit token, SAT entry 0 over the romhack clown's sprites.
- `15-hud/hud_two_players.png`: 2-player game: 2ND and its score (the waiting player's score grey, as the arcade dims it).
- `15-hud/extra_collected_green.png`: collected EXTRA letters light green (user's pick); a marked collected letter green on blue.
- `18-apple-tiles/`: resting apples drawn as background tiles (out of the sprite budget); the handoff to the wobbling sprite frame by frame; the apple tiles over three levels' dirt.
- `19-cherry-lab/`: the Cherry Lab page (one cherry design per level look; published as a private artifact) and a first comparison: arcade original / current CV / draft.
- `19-cherry-lab/ingame_*`: the drafted cherries in game: 12 scenes; before (red band beside the cherry bodies) and after (black band).
- `21-arcade-icons/`: round-end icons as the arcade draws them (one TMS sprite per arcade pen, colours from the arcade's table at $7C81) on VERY GOOD and WONDERFUL, replacing the romhack tile icons. `verygood_icons_sheet.png`: every icon on every SCENE line (files `vg_<s1><s2><s3>_a/b`: 1 creep, 2 cherries, 3 diamond, 4 EXTRA; b = later, characters in). `icons_arcade_vs_tms.png` arcade vs TMS colours; `icons_colour_options.png` red 8/9 x blue 4/5 (kept 8 and 4: Mr. Do's red).
- `22-alpha-prize-quirk/`: MAME (the real arcade code), recorded in real time: a lone letter monster killed, then the center prize collected 12 frames later (`mame_prize_12frames.mp4`: no session; the dying monster's update clears the prize's request, $E0B2 03 -> 02 -> 00) and 90 frames later (`mame_prize_90frames.mp4`: the letter monster and chompers come out). `mame_prize_38frames.mp4`: 38 frames (0.63 s), the last that still loses the session (39+ starts it). Mr. Do is placed on the prize by the script (tools/diff/mame_alpha_prize.lua); logs alongside.
- `23-apple-lab/`: the Apple Lab page (one resting apple per level look; published as a private artifact, db collection `apples`) and its data; `old_sprite_bestguess.png`: per level look, the old tiles / the in-game sprite over dirt / the best guess now in the build; `arcade_old_sprite_firstdraft.png`: the arcade apple and a first, rejected draft (arcade shape and highlight: a boxy halo).
