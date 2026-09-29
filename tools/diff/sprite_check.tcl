# Sprite pass check (tools/sprite_check.sh): at the end of every list build,
# the entries the arcade's sprite RAM says should be on screen (on-screen
# box, one in four ball fragments, 32 at most) must equal the list plus the
# apples drawn as tiles. Catches a pass that drops sprites (95d09cb: every
# code below $5E was skipped and the per-frame SAT checks did not notice).
set ::as [symaddr ARC_SPRITES]; set ::n 0; set ::bad 0; set ::ex {}
debug set_bp [symaddr sprites_update.done] {} {
  incr ::n
  set yb [expr {240 - [peek [symaddr cam]] * 8}]
  set want 0; set frag 0
  for {set i 0} {$i < 64} {incr i} {
    set a [expr {$::as + 4*$i}]
    set Y [peek [expr {$a+1}]]; if {$Y == 0} break
    if {[peek $a] == 0x70} { incr frag; if {($frag & 3) != 1} continue }
    set x [expr {224 - $Y}]; set y [expr {$yb - [peek [expr {$a+3}]]}]
    if {$x < -31 || $x >= 192 || $y < -15 || $y >= 192 || $y - 1 == 0xD0} continue
    incr want
  }
  if {$want > 32} { set want 32 }
  set got [expr {(([reg de] & 0xFF) - ([symaddr spr_list] & 0xFF)) / 4}]
  if {[peek [symaddr mode]] == 1} { incr got [peek [symaddr SCN_BUF]] }
  if {$got != $want} { incr ::bad; if {[llength $::ex] < 5} { lappend ::ex "handler $::h: want $want, got $got (mode [peek [symaddr mode]])" } }
}
rename exit sc_exit
proc exit {args} {
  puts stderr "SPRITE CHECK: $::n passes, $::bad mismatches"
  foreach e $::ex { puts stderr "  $e" }
  sc_exit
}
