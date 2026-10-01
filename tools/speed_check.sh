#!/bin/sh
# Game speed in three seeded scenarios (tools/speed_play.tcl), run in
# parallel on the normal build: arcade handlers per vblank (100% = full
# speed). usage: tools/speed_check.sh [SEED] [END seconds]
cd "$(dirname "$0")/.."
SEED=${1:-7}; END=${2:-68}
for s in monsters chomper ball; do
  MRDO_SYM=$PWD/build/mrdo.sym SCEN=$s SEED=$SEED END=$END \
    ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} -machine ColecoVision_SGM \
    -carta build/mrdo.rom -romtype ColecoMegaCart -command "set renderer none" \
    -script tools/speed_play.tcl 2>&1 | grep SPEED &
done
wait
