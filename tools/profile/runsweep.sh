#!/bin/bash
S=/private/tmp/claude-501/-Users-scottmoschella-work-mrdotoo/bd43a10e-58a4-4108-809d-77457ea027a2/scratchpad/mame_profile
r(){ n=$1; dbg=$2; shift 2; if [ "$dbg" = 1 ]; then D="-debug -debugger none"; else D=""; fi
  env OUT=$S/sweep/$n.json "$@" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy mame mrdo -rompath $S/roms -video none -sound none -nothrottle -skip_gameinfo $D -autoboot_script $S/sweep.lua > $S/sweep/$n.out 2>&1; }
r s1_attract 0 FRAMES=30000 MODE=attract &
r s2_play 0 FRAMES=30000 MODE=random SEED=1 &
r s3_idle_alpha 1 FRAMES=15000 MODE=idle INV=1 LEVEL=4 ALPHA=3000 &
r s4_rand_alpha_letters 1 FRAMES=30000 MODE=random INV=1 LEVEL=4 ALPHA=2400 LETTERS=1 SEED=2 &
r s5_rounds 1 FRAMES=40000 MODE=random INV=1 WIN=1200 SEED=6 &
r s6_gameover_hiscore 0 FRAMES=30000 MODE=random TOPUP=0 SCORE=1 SEED=3 &
r s7_two_player 0 FRAMES=30000 MODE=random TOPUP=0 SCORE=1 TWO=1 SEED=4 &
r s8_two_player_cocktail 0 FRAMES=30000 MODE=random TOPUP=0 TWO=1 COCKTAIL=1 SEED=5 &
wait
r s9_nofire_alpha 1 FRAMES=20000 MODE=random NOFIRE=1 INV=1 LEVEL=4 ALPHA=2400 SEED=8
echo ALLDONE
