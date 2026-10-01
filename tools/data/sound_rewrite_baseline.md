# Sound engine rewrite: baseline (build 9bc81d7, 2026-09-30)

Audio (tools/sound_harness.sh SEED 40000; files in build/sound_base/, regenerate
from 9bc81d7 if lost): every rewrite step must give byte-identical logs.

| seed | vblanks | chip writes | requests/stops |
|---|---|---|---|
| 1 | 52331 | 360661 | 1628 |
| 2 | 52331 | 354209 | 1667 |
| 3 | 52331 | 355511 | 1662 |

Speed (tools/speed_check.sh, handlers per vblank, 8-68 s):

| scenario | seed 7 | seed 8 |
|---|---|---|
| monsters | 72.2% | 75.2% |
| chomper | 68.3% | 73.8% |
| ball | 70.2% | 86.7% |

tools/bench.sh (validation build, HEAVY replay): 3843 vblanks, handler mean 37142 T.
Profile (seeded many-monster play, 60 s): sound = 10.8% of busy CPU: arcade tick
body 1.7%, allocator $5E10 1.3%, channel output $5BB3 1.1%, stream reader $5C69
0.9%, our translation layer (snd_silchk/sil1/sil2/chout/tone/period/w1/w2) ~5.8%.
