#!/bin/sh
# Sound engine harness (tools/sound_harness.tcl): game frozen, seeded request
# schedule, every SN76489/AY write per engine tick -> $OUT (default
# build/sound_harness.txt). Compare two builds' logs with cmp/diff: a sound
# engine change must leave them identical.
# usage: tools/sound_harness.sh [SEED] [MIX vblanks] [OUT]
cd "$(dirname "$0")/.."
SEED=${1:-1}; MIX=${2:-20000}; OUT=${3:-build/sound_harness.txt}
MRDO_SYM=$PWD/build/mrdo.sym SHOUT=$OUT SEED=$SEED MIX=$MIX \
  ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} -machine ColecoVision_SGM \
  -carta build/mrdo.rom -romtype ColecoMegaCart -command "set renderer none" \
  -script tools/sound_harness.tcl 2>&1 | grep --line-buffered "harness tick" | tail -1
echo "$OUT: $(grep -c '^v ' $OUT) ticks, $(grep -c '^w ' $OUT) chip writes, $(grep -c '^[rs] ' $OUT) requests/stops"
