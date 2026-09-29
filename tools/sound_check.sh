#!/bin/sh
# Sound output check (tools/sound_check.tcl): 45 s of scripted play with a
# chomper session on the normal build. A model of each arcade chip is kept
# from every byte our translators receive; wherever the engine's channel
# output (snd_chout) or its silencing (snd_sil1/2) ran, the bytes the
# original code writes must leave that model unchanged. Must print bad=0.
# Run after any change to src/sound.asm or the sound patches.
cd "$(dirname "$0")/.."
MRDO_SYM=$PWD/build/mrdo.sym ${OPENMSX:-/Applications/openMSX.app/Contents/MacOS/openmsx} \
  -machine ColecoVision_SGM -carta build/mrdo.rom -romtype ColecoMegaCart -command "set renderer none" \
  -script tools/sound_check.tcl 2>&1 | grep -A5 SNDVERIFY
