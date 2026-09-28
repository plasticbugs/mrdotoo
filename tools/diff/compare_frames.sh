#!/bin/sh
# Arcade vs ColecoVision at the same vblank handlers. Uses the validation
# build, whose logic matches the MAME recording exactly (both run the
# pathfinder to completion); the normal build drifts over long runs.
# usage: tools/diff/compare_frames.sh SEED CAM H1 H2 ...   (sheet: build/frames.png)
# Uses the seed's validation recording for the inputs (make validate first).
set -e
cd "$(dirname "$0")/../.."
SEED=$1; CAM=$2; shift 2
LAST=$(for h in "$@"; do echo $h; done | sort -n | tail -1)
SNAP=$(echo "$@" | tr ' ' ',')
rm -rf build/frames && mkdir -p build/frames/mame
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy OUT=build/frames/rec FRAMES=$((LAST + 2)) SEED=$SEED SNAP=$SNAP \
  mame mrdo -rompath "$PWD/build/mame_roms" -video none -sound none -nothrottle -skip_gameinfo \
  -snapshot_directory "$PWD/build/frames/mame" -autoboot_script tools/diff/mame_record.lua > /dev/null 2>&1
for h in "$@"; do
  MRDO_SYM=$PWD/build/mrdo_validate.sym REF=build/frames/rec OUTRAM=build/frames/cv.ram FRAMES=$((LAST + 10)) \
    SNAP=$h SNAPN=1 SNAPFILE=$PWD/build/frames/cv_%d.png \
    ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} -machine ColecoVision_SGM \
    -carta build/mrdo_validate.rom -romtype ColecoMegaCart -script tools/diff/cv_replay.tcl > /dev/null 2>&1
done
python3 tools/diff/compare_frames.py build/frames.png "$CAM" build/frames/mame/mrdo build/frames/cv_%d.png "$@"
