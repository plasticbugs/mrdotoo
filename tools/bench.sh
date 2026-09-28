#!/bin/sh
# Deterministic speed benchmark: replay a HEAVY lockstep recording (make one
# with `HEAVY=1 make validate FRAMES=3000 SEED=3`) on the validation build and
# time it (tools/perf_replay.tcl).  usage: tools/bench.sh [SEED] [FRAMES]
cd "$(dirname "$0")/.."
SEED=${1:-3}; FRAMES=${2:-3000}
MRDO_SYM=$PWD/build/mrdo_validate.sym REF=build/diff/s$SEED/ref OUTRAM=build/bench.ram FRAMES=$FRAMES HEAVY=1 \
  ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} -machine ColecoVision_SGM \
  -carta build/mrdo_validate.rom -romtype ColecoMegaCart -script tools/diff/cv_replay.tcl -script tools/perf_replay.tcl 2>&1 \
  | grep -E "vblanks for|arcade handler"
