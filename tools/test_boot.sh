#!/bin/sh
# Headless-ish boot test: 4 emulated seconds, then self-test verdicts + screenshot.
cd "$(dirname "$0")/.."
OPENMSX=${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx}
export MRDO_SYM="$PWD/build/mrdo.sym" MRDO_SHOT="$PWD/build/boot.png"
rm -f "$MRDO_SHOT"
"$OPENMSX" -machine ColecoVision_SGM -carta build/mrdo.rom -romtype ColecoMegaCart \
    -script tools/test_boot.tcl 2>&1 | grep RESULT
test -f "$MRDO_SHOT" && echo "screenshot: $MRDO_SHOT"
