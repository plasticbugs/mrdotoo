# Sprite pass check (tools/sprite_check.sh): at the end of every list build,
# the entries the arcade's sprite RAM says should be on screen (on-screen
# box, one in four ball fragments, 32 at most) must equal the list plus the
# apples drawn as tiles. Catches a pass that drops sprites (95d09cb: every
# code below $5E was skipped and the per-frame SAT checks did not notice).
set ::as [symaddr ARC_SPRITES]; set ::n 0; set ::bad 0; set ::ex {}; set ::exp {}; set ::pbad 0
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
    lappend ::exp [list [expr {($y - 1) & 0xFF}] [expr {$x < 0 ? $x + 32 : $x}] [expr {$x < 0 ? 0x80 : 0}] [expr {([peek $a] & 0x7F) == 0x5E}]]
  }
  # every list entry's place: y, x and the early clock bit, in queue order
  # (resting apples on the playfield may be tiles instead: not listed)
  set ::ln [expr {(([reg de] & 0xFF) - ([symaddr spr_list] & 0xFF)) / 4}]
  set ::pq 0
  for {set ::pi 0} {$::pi < $::ln} {incr ::pi} {
    set ::pe [expr {[symaddr spr_list] + 4*$::pi}]
    set ::ly [peek $::pe]; set ::lx [peek [expr {$::pe+1}]]; set ::lc [expr {[peek [expr {$::pe+3}]] & 0x80}]
    while {$::pq < [llength $::exp]} {
      lassign [lindex $::exp $::pq] ::pey ::pex ::pec ::papl
      if {$::papl && ($::pey != $::ly || $::pex != $::lx) && [peek [symaddr mode]] == 1} { incr ::pq; continue }
      break
    }
    if {$::pq >= [llength $::exp] || $::pey != $::ly || $::pex != $::lx || $::pec != $::lc} { incr ::pbad; if {[llength $::ex] < 5} { lappend ::ex "handler $::h entry $::pi: list [format %02x%02x $::ly $::lx] want [format %02x%02x $::pey $::pex]" } }
    incr ::pq
  }
  set ::exp {}
  if {$want > 32} { set want 32 }
  set got [expr {(([reg de] & 0xFF) - ([symaddr spr_list] & 0xFF)) / 4}]
  if {[peek [symaddr mode]] == 1} { incr got [peek [symaddr SCN_BUF]] }
  if {$got != $want} { incr ::bad; if {[llength $::ex] < 5} { lappend ::ex "handler $::h: want $want, got $got (mode [peek [symaddr mode]])" } }
}
rename exit sc_exit
proc exit {args} {
  puts stderr "SPRITE CHECK: $::n passes, $::bad count mismatches, $::pbad position mismatches"
  foreach e $::ex { puts stderr "  $e" }
  sc_exit
}
