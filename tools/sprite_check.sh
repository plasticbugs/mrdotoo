#!/bin/sh
# Every sprite-list build over a HEAVY replay (tools/diff/sprite_check.tcl):
# expected on-screen sprites vs the list + tiled apples. Run after any change
# to src/sprites.asm or src/apples.asm. usage: tools/sprite_check.sh [SEED] [FRAMES]
cd "$(dirname "$0")/.."
SEED=${1:-3}; FRAMES=${2:-1500}
MRDO_SYM=$PWD/build/mrdo_validate.sym REF=build/diff/s$SEED/ref OUTRAM=build/bench.ram FRAMES=$FRAMES HEAVY=1 \
  ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} -machine ColecoVision_SGM \
  -carta build/mrdo_validate.rom -romtype ColecoMegaCart -command "set renderer none" \
  -script tools/diff/cv_replay.tcl -script tools/diff/sprite_check.tcl 2>&1 | grep -A5 "SPRITE CHECK"
