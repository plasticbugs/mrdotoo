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
# a tone channel's three bytes sent at once (snd_tone): the same bytes
debug set_bp [symaddr snd_tone] {} {
  set c [reg c]; set d [reg d]; set iy [reg iy]
  set i8 [peek [expr {$iy+8}]]; set i9 [peek [expr {$iy+9}]]
  set n [expr {($c & 1) + 1}]
  foreach b [list [expr {(($i9 & 0xF0) >> 4) | $d}] $i8 [expr {($i9 & 0x0F) | $d | 0x10}]] { set ::chip($n) [apply $::chip($n) $b] }
}
set ::checks 0; set ::bad 0; set ::ex {}
# ...and its port writes must be what snd_w1 / snd_w2 write for those bytes
set ::tcap 0; set ::tio {}; set ::tn 0; set ::tbad 0
debug set_watchpoint write_io 0xFF {$::tcap} { lappend ::tio "S[format %02x $::wp_last_value]" }
debug set_watchpoint write_io 0x50 {$::tcap} { lappend ::tio "A[format %02x $::wp_last_value]" }
debug set_watchpoint write_io 0x51 {$::tcap} { lappend ::tio "W[format %02x $::wp_last_value]" }
debug set_bp [symaddr snd_tone] {} {
  set iy [reg iy]; set ::tin [list [reg c] [reg d] [peek [expr {$iy+8}]] [peek [expr {$iy+9}]] [peek [symaddr snd_tvolc]] [peek [symaddr snd_nvol2]]]
  set ::tio {}; set ::tcap 1
}
debug set_bp [symaddr snd_outloop.cr] {$::tcap} { set ::tcap 0; incr ::tn; if {[expect_io {*}$::tin] ne $::tio} { incr ::tbad; incr ::bad; if {[llength $::ex] < 5} { lappend ::ex "snd_tone $::tin: $::tio" } } }
set ::atn {15 14 14 13 12 12 11 10 10 9 8 8 7 6 6 0}
proc h2 {v} { format %02x [expr {$v & 0xFF}] }
proc expect_io {c d i8 i9 tvolc nvol2} {
  set lat [expr {(($i9 & 0xF0) >> 4) | $d}]
  set p [expr {(($i8 & 0x3F) << 4) | ($lat & 0x0F)}]
  set sc [expr {$p - ($p >> 3)}]
  set vb [expr {($i9 & 0x0F) | $d | 0x10}]
  set ch [expr {($c >> 1) & 3}]
  if {!($c & 1)} {
    return [list S[h2 [expr {($lat & 0xF0) | ($sc & 0x0F)}]] S[h2 [expr {($sc >> 4) & 0x3F}]] S[h2 $vb]]
  }
  set l [list A[h2 [expr {2*$ch}]] W[h2 [expr {$sc & 0xFF}]] A[h2 [expr {2*$ch+1}]] W[h2 [expr {$sc >> 8}]]]
  set vol [lindex $::atn [expr {$vb & 15}]]
  if {$ch == 2} {
    set e [expr {$vol > $nvol2 ? $vol : $nvol2}]
    set mix [expr {$nvol2 ? (0x38 & ~0x20) : 0x38}]
    lappend l A0a W[h2 $e] A07 W[h2 $mix]
  } else { lappend l A[h2 [expr {8+$ch}]] W[h2 $vol] }
  return $l
}

proc expect {chipn bytes} {
  set c $::chip($chipn); foreach b $bytes { set c [apply $c $b] }
  # the latch register may differ harmlessly (tone pairs always rewrite it); compare the rest
  foreach k {t0 t1 t2 v0 v1 v2 v3 n} { if {[dict get $c $k] != [dict get $::chip($chipn) $k]} { return 0 } }
  return 1
}
# snd_chout: remember what the original would write; check after it returns
# (snd_outloop.cr: the native output loop's return point from snd_chout)
debug set_bp [symaddr snd_chout] {} {
  set a [reg a]; set iy [reg iy]; set b8 [peek [expr {$iy+8}]]; set b9 [peek [expr {$iy+9}]]
  set d [expr {0x80 | (($a & 6) << 4)}]; set t [expr {$a & 0x38}]
  if {$t >= 0x20 && $t < 0x30} { set ::pend [list [expr {($a & 1) + 1}] [list [expr {$d | $b8}] [expr {$d | $b9 | 0x10}]]] } else { set ::pend [list [expr {($a & 1) + 1}] [list [expr {(($b9 & 0xF0) >> 4) | $d}] $b8 [expr {($b9 & 15) | $d | 0x10}]]] }
}
debug set_bp [symaddr snd_outloop.cr] {} { incr ::checks; if {![expect [lindex $::pend 0] [lindex $::pend 1]]} { incr ::bad; if {[llength $::ex] < 5} { lappend ::ex "chout t=[format %.2f [machine_info time]] $::pend" } } }
# snd_silpass (the tick's silencing pass, native): the original writes a
# volume-off byte ($9F/$BF/$DF/$FF) to each chip channel whose bit in $EC74
# is clear (chip 1 bit 7-2k, chip 2 bit 6-2k for channel k). A tone channel
# it skips (its SND_SIL bit set) must already be silent in the model; then
# the model takes every byte the original would have written.
set ::use_a [expr {[symaddr ARC_WORK] + 0xC74}]
debug set_bp [symaddr snd_silpass] {} {
  set use [peek $::use_a]; set sil [peek [symaddr SND_SIL]]
  foreach k {0 1 2 3} {
    set a [expr {0x9F + 32 * $k}]
    foreach n {1 2} {
      if {$use & (1 << ($n == 1 ? 7 - 2 * $k : 6 - 2 * $k))} continue
      if {$k < 3 && ($sil & (1 << ($n == 1 ? $k : 3 + $k)))} {
        incr ::checks
        if {[dict get $::chip($n) v$k] != 15} { incr ::bad; if {[llength $::ex] < 5} { lappend ::ex "sil chip $n ch $k skipped, volume [dict get $::chip($n) v$k]" } }
      }
      set ::chip($n) [apply $::chip($n) $a]
    }
  }
}
set throttle off
after time 4   { inp 0xff 0xbf }
after time 4.1 { inp 0xff 0xff }
after time 5   { inp 0xdf 0xff }
after time 5.2 { inp 0xff 0xff }
set ::dirs {0xfe 0xfd 0xfb 0xf7 0xef 0xff}
set ::mvn 0
proc mv {} { incr ::mvn; set d [lindex $::dirs [expr {int(rand()*6)}]]; if {$::mvn % 4 == 0} { set d [expr {$d & 0xEF}] }; poke [symaddr inp_p1] $d; poke [symaddr inp_override] 1; after time 0.7 mv }
after time 6 mv
after time 10 { poke 0x60B2 [expr {[peek 0x60B2] | 3}] }
after time 50 { puts stderr "SNDVERIFY checks=$::checks tone-writes=$::tn bad=$::bad"; foreach e $::ex { puts stderr "  $e" }; exit }
