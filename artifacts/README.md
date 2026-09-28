# Progress artifacts

A record of the port's progress: screenshots, previews and (later) audio
recordings, one folder per milestone. Files here are committed; `build/` is not.

| Folder | Milestone |
|---|---|
| `01-phase0-boot` | CV + SGM + MegaCart skeleton boots; SGM-required screen |
| `02-phase1-arcade-logic` | The arcade program runs on the ColecoVision (debug text view of the arcade's foreground layer); lockstep-identical to MAME for 3 x 20,000 frames |
| `03-phase2-renderer` | The real playfield renderer: arcade tiles converted to Screen 2 |

## 03-phase2-renderer
- `tileset-preview-scene1-midgame.png`: offline preview; a recorded arcade frame rendered through the generated tables (before any Z80 code existed).
- `first-render-game-start.png`: first real render on the ColecoVision (openMSX); camera at the bottom position because Mr. Do starts in the bottom row.
- `first-render-scene1-dug-tunnel.png`: the same game after Mr. Do dug right and up; the tunnel is drawn tile by tile from the arcade's own writes, and the camera has moved back to the middle.
