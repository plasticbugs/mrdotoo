#!/bin/sh
# Run MAME on mrdo, headless. Every MAME run in this repo goes through here.
#
# Nothing may touch the display. `-video none` stops MAME rendering but does
# NOT stop it creating a window, and MAME's defaults are fullscreen (window 0,
# maximize 1): on macOS the desktop jumps to another Space each time a run
# starts. Three measures, because they fail independently: SDL_VIDEODRIVER=dummy
# keeps SDL off the display (read before MAME parses anything), -videodriver
# dummy says the same through MAME, and -window -nomaximize keeps any window
# that is created anyway small. Snapshots (-snapshot_directory), -aviwrite and
# -wavwrite still work (-sound none does not stop -wavwrite recording).
#
# Callers pass -seconds_to_run (emulated seconds) as a backstop: the Lua
# scripts end the run themselves, but a hung script must not run forever.
# ROMPATH: the romset directory (default build/mame_roms, made by
# tools/diff/run_diff.sh from symlinks; never in git).
root=$(cd "$(dirname "$0")/.." && pwd)
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
exec mame mrdo -rompath "${ROMPATH:-$root/build/mame_roms}" \
    -video none -videodriver dummy -window -nomaximize \
    -sound none -nothrottle -skip_gameinfo \
    "$@"
