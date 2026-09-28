# MAME profiling scripts (arcade Mr. Do!)

Written during Phase 0 to measure the arcade's per-frame CPU cost and sprite usage.

- `play.lua`, `wc.lua`, `wcq.lua`: headless scenario drivers. `wc*` use setup pokes: level $E09F=4 (level 5, 8 monsters), invincibility breakpoints at $32A6/$44B0/$4B94, $E0B2|=3 to force the alpha monster and chompers.
- `wct.lua`: full instruction trace with `totalcycles`; `rprof.py` builds per-routine inclusive/exclusive profiles from it, `hot.py` gives a per-instruction view.
- `census*.py`: sprite queue census ($E311). `sim.py`, `perf.py`, `ana*.py`: frame-budget analysis.
- `labels.json`: arcade address -> MSX-port label map.

Rompath: a `mrdo/` folder with the do_disassemble ROM files plus `u001_pal16r6cn.j2`, a 260-byte zero-filled stand-in for the missing protection PAL dump (the game runs normally with it). Run MAME with `-debug -debugger none -video none -sound none -nothrottle -autoboot_script <script>.lua`.
