#!/bin/sh
# A/B the sound engine: tools/sound_harness.tcl on the baseline ROM
# (build/base/mrdo.rom + .sym, copied from the baseline commit's build) and
# on build/mrdo.rom, for seeds 1-3; compares per tick (tools/sound_cmp.py).
# usage: tools/sound_ab.sh [MIX]
cd "$(dirname "$0")/.."
MIX=${1:-40000}; rc=0
run() {
  MRDO_SYM=$PWD/$2 SHOUT=$3 SEED=$4 MIX=$MIX \
    ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} -machine ColecoVision_SGM \
    -carta $1 -romtype ColecoMegaCart -command "set renderer none" -script tools/sound_harness.tcl > /dev/null 2>&1
}
for s in 1 2 3; do
  [ -f build/base/h$s.$MIX.txt ] || run build/base/mrdo.rom build/base/mrdo.sym build/base/h$s.$MIX.txt $s &
  run build/mrdo.rom build/mrdo.sym build/sh_new$s.txt $s &
done
wait
for s in 1 2 3; do
  printf "seed %s: " $s; python3 tools/sound_cmp.py build/base/h$s.$MIX.txt build/sh_new$s.txt || rc=1
done
exit $rc
