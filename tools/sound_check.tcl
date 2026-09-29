set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} { set f [open $::mrdo_sym]; foreach line [split [read $f] "\n"] { if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] } }; close $f; error "no $name" }
proc inp {p1 p2} { poke [symaddr inp_p1] $p1; poke [symaddr inp_p2] $p2; poke [symaddr inp_override] 1 }
# model per arcade chip: latch, tone[3], vol[4], noise
proc newchip {} { return [dict create lat 0 t0 0 t1 0 t2 0 v0 15 v1 15 v2 15 v3 15 n -1] }
set ::chip(1) [newchip]; set ::chip(2) [newchip]
proc apply {c v} {
  if {$v & 0x80} {
    dict set c lat $v; set ch [expr {($v >> 5) & 3}]
    if {$v & 0x10} { dict set c v$ch [expr {$v & 15}] } elseif {$ch == 3} { dict set c n [expr {$v & 7}] } else { dict set c t$ch [expr {([dict get $c t$ch] & 0x3F0) | ($v & 15)}] }
  } else {
    set l [dict get $c lat]; set ch [expr {($l >> 5) & 3}]
    if {$ch < 3 && !($l & 0x10)} { dict set c t$ch [expr {([dict get $c t$ch] & 15) | (($v & 0x3F) << 4)}] }
  }
  return $c
}
# every byte that reaches a translator updates the model
debug set_bp [symaddr snd_w1] {} { set ::chip(1) [apply $::chip(1) [reg a]] }
debug set_bp [symaddr snd_w2] {} { set ::chip(2) [apply $::chip(2) [reg a]] }
set ::checks 0; set ::bad 0; set ::ex {}
proc expect {chipn bytes} {
  set c $::chip($chipn); foreach b $bytes { set c [apply $c $b] }
  # the latch register may differ harmlessly (tone pairs always rewrite it); compare the rest
  foreach k {t0 t1 t2 v0 v1 v2 v3 n} { if {[dict get $c $k] != [dict get $::chip($chipn) $k]} { return 0 } }
  return 1
}
# snd_chout: remember what the original would write; check after it returns
debug set_bp [symaddr snd_chout] {} {
  set a [reg a]; set iy [reg iy]; set b8 [peek [expr {$iy+8}]]; set b9 [peek [expr {$iy+9}]]
  set d [expr {0x80 | (($a & 6) << 4)}]; set t [expr {$a & 0x38}]
  if {$t >= 0x20 && $t < 0x30} { set ::pend [list [expr {($a & 1) + 1}] [list [expr {$d | $b8}] [expr {$d | $b9 | 0x10}]]] } else { set ::pend [list [expr {($a & 1) + 1}] [list [expr {(($b9 & 0xF0) >> 4) | $d}] $b8 [expr {($b9 & 15) | $d | 0x10}]]] }
}
debug set_bp 0x5C12 {} { incr ::checks; if {![expect [lindex $::pend 0] [lindex $::pend 1]]} { incr ::bad; if {[llength $::ex] < 5} { lappend ::ex "chout t=[format %.2f [machine_info time]] $::pend" } } }
foreach {sym ret n} [list snd_sil1 0x5AEA 1 snd_sil2 0x5AF1 2] {
  debug set_bp [symaddr $sym] {} "set ::spend \[list $n \[reg a\]\]"
  debug set_bp $ret {} { incr ::checks; if {![expect [lindex $::spend 0] [list [lindex $::spend 1]]]} { incr ::bad; if {[llength $::ex] < 5} { lappend ::ex "sil $::spend" } } }
}
set throttle off
after time 4   { inp 0xff 0xbf }
after time 4.1 { inp 0xff 0xff }
after time 5   { inp 0xdf 0xff }
after time 5.2 { inp 0xff 0xff }
set ::dirs {0xfe 0xfd 0xfb 0xf7 0xef 0xff}
proc mv {} { poke [symaddr inp_p1] [lindex $::dirs [expr {int(rand()*6)}]]; poke [symaddr inp_override] 1; after time 0.7 mv }
after time 6 mv
after time 10 { poke 0x60B2 [expr {[peek 0x60B2] | 3}] }
after time 50 { puts stderr "SNDVERIFY checks=$::checks bad=$::bad"; foreach e $::ex { puts stderr "  $e" }; exit }
