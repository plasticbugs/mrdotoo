#!/bin/sh
# Apples on screen, as the VDP shows them: seeded random play on the normal
# build (invincible; LEVEL=n, ALPHA=1 forces letter monster + chompers every
# 10 s), every vblank's SAT / name table / SPT + the arcade's sprite RAM, then
# tools/apple_vis.py: per apple, the pattern lines the TMS9918 draws (first 4
# sprites per line) or its 4 tiles. Gaps should stay within the crowded
# rotation's bound (<= ~8 vblanks; a longer "gone" run is a bug).
# usage: tools/apple_vis.sh   (six runs in parallel, ~100 emulated s each)
cd "$(dirname "$0")/.."
T=build/apple_vis; mkdir -p $T
run() {
  env MRDO_SYM=$PWD/build/mrdo.sym AVOUT=$T/$1.bin SEED=$2 SECS=100 $3 \
  ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} -machine ColecoVision_SGM \
  -carta build/mrdo.rom -romtype ColecoMegaCart -command "set renderer none" \
  -script tools/diff/apple_vis.tcl > $T/$1.log 2>&1
}
run a 11 "" & run b 22 "LEVEL=3" & run c 33 "LEVEL=5" &
run d 44 "LEVEL=5 ALPHA=1" & run e 55 "LEVEL=8 ALPHA=1" & run f 66 "LEVEL=2" &
wait
python3 tools/apple_vis.py $T/a.bin $T/b.bin $T/c.bin $T/d.bin $T/e.bin $T/f.bin
