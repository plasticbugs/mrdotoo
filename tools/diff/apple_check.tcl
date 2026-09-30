# Tiled apples on screen (tools/sprite_check.sh runs it too): each vblank, every
# apple in the tiled list must show its 4 tiles in the name table on screen.
# "longest-run" is the longest stretch of vblanks one stayed missing
# (was 661 when a camera redraw lost it; 1 = the handover frame).
set ::sb [symaddr SCN_BUF]; set ::bad 0; set ::n 0; set ::miss [dict create]; set ::worst 0
debug set_bp [symaddr nmi] {[peek [symaddr mode]] == 1 && [peek [symaddr in_nmi]] == 0} {
  set pnt [expr {([vdpreg 2] & 0x0F) * 0x400}]
  set cam [peek [symaddr cam]]
  set cn [peek [expr {$::sb + 16}]]
  for {set i 0} {$i < $cn} {incr i} {
    set tx [peek [expr {$::sb + 17 + 2*$i}]]; set row [peek [expr {$::sb + 18 + 2*$i}]]
    set sy [expr {$row - $cam}]
    set ok 1
    for {set dy 0} {$dy < 2} {incr dy} { for {set dx 0} {$dx < 2} {incr dx} {
      set r [expr {$sy + $dy}]; if {$r < 0 || $r >= 24} continue
      set code [vpeek [expr {$pnt + $r*32 + $tx + $dx}]]
      if {$code != 172 + $dy*2 + $dx} { set ok 0 }
    } }
    incr ::n
    set k "$tx,$row"
    if {!$ok} { dict incr ::miss $k; set c [dict get $::miss $k]; if {$c > $::worst} { set ::worst $c } } else { dict set ::miss $k 0 }
    if {!$ok} { incr ::bad }
  }
}
rename exit a_exit
proc exit {args} { puts stderr "APLVIS apple-vblanks=$::n missing=$::bad longest-run=$::worst"; a_exit }
