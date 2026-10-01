# Sound engine rewrite: baseline (build 9bc81d7, 2026-09-30)

Audio: tools/sound_ab.sh (tools/sound_harness.tcl on build/base/mrdo.rom, the
baseline build's ROM + .sym, against build/mrdo.rom; seeds 1-3, MIX 40000; per
engine tick: chip writes and the engine RAM $EC00-$EFFF; tools/sound_cmp.py).
Every rewrite step must print IDENTICAL for all three. The harness keeps the game
in attract and blocks its stop entry $02EA and reset routine $5A80 (their timing
depends on game speed). Negative test: dropping one noise write -> DIFFERENT at tick 0.

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

## Steps

Engine cost (tools/sound_ab.sh prints it): T-states per tick in the harness,
deterministic (the seeded play scenarios are chaotic: one seed swings +-1.5 points
for any timing change, so they only show trends).

| step | what | audio A/B | T/tick seed 1 | monsters 7 | chomper 7 | ball 7 |
|---|---|---|---|---|---|---|
| 0 | baseline 9bc81d7 | - | 13496 | 72.2% | 68.3% | 70.2% |
| 1 | silencing pass $5ADD native (snd_silpass) | IDENTICAL | - | 75.4% | 71.1% | 71.8% |
| 2 | output loop $5BFA native, snd_chout table-driven | IDENTICAL | 11615 | 74.0% | 71.2% | 72.8% |
