#!/bin/sh
# Lockstep RAM diff: record MAME, replay on the CV build, compare.
# usage: tools/diff/run_diff.sh [FRAMES] [SEED]
set -e
cd "$(dirname "$0")/../.."
FRAMES=${1:-3000}; SEED=${2:-1}
OUT=build/diff/s$SEED; mkdir -p $OUT
ROMPATH=${MRDO_ROMPATH:-$PWD/build/mame_roms}
if [ ! -d "$ROMPATH/mrdo" ]; then
  mkdir -p "$ROMPATH/mrdo"
  for f in a4-01 c4-02 e4-03 f4-04 h5-05 k5-06 n8-07 r8-08 s8-09 u8-10 f10--1 j10--4 t02--3 u02--2; do
    ln -sf "${DO_DISASM:-$HOME/work/do_disassemble}/$f.bin" "$ROMPATH/mrdo/$f.bin"
  done
  head -c 260 /dev/zero > "$ROMPATH/mrdo/u001_pal16r6cn.j2"   # stand-in for the missing PAL dump
fi
echo "recording $FRAMES handlers in MAME (seed $SEED)..."
OUT=$OUT/ref FRAMES=$FRAMES SEED=$SEED mame mrdo -rompath "$ROMPATH" -video none -sound none \
  -nothrottle -skip_gameinfo -autoboot_script tools/diff/mame_record.lua > $OUT/mame.log 2>&1 || true
echo "replaying on the ColecoVision build..."
MRDO_SYM=$PWD/build/mrdo_validate.sym REF=$OUT/ref OUTRAM=$OUT/cv.ram FRAMES=$FRAMES \
  ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} -machine ColecoVision_SGM \
  -carta build/mrdo_validate.rom -romtype ColecoMegaCart -script tools/diff/cv_replay.tcl > $OUT/openmsx.log 2>&1 || true
python3 tools/diff/compare.py $OUT/ref.ram $OUT/cv.ram
