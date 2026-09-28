# Heavy-round speed measurement on the normal build (the port's version of
# tools/profile/wc.lua): level 5 (8 monsters), Mr. Do invincible, the letter
# monster + chompers forced every ALPHA seconds, random play. Reports how many
# arcade handlers ran per vblank, held/skipped vblanks, and the arcade
# handler's own time (our NMI time inside it subtracted).
# Env: MRDO_SYM, SECS (measured seconds, default 30), SEED, ALPHA (s, 0 = off),
#      CALLS="addr ..." also counts calls of those arcade routines and their IY.
set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} {
    set f [open $::mrdo_sym]
    foreach line [split [read $f] "\n"] {
        if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] }
    }
    close $f; error "no $name"
}
proc now {} { expr {[machine_info VDP_frame_count] * 358416 + [machine_info VDP_cycle_in_frame]} }
proc inp {p1 p2} { poke [symaddr inp_p1] $p1; poke [symaddr inp_p2] $p2; poke [symaddr inp_override] 1 }
set secs [expr {[info exists ::env(SECS)] ? $::env(SECS) : 30}]
set alpha [expr {[info exists ::env(ALPHA)] ? $::env(ALPHA) : 20}]
expr {srand([info exists ::env(SEED)] ? $::env(SEED) : 1)}

# invincibility (skip the death paths: carry clear) and level 5
foreach a {0x32A6 0x44B0 0x4B94} { debug set_bp $a {} { reg f [expr {[reg f] & 0xFE}] } }
debug set_bp 0x1A76 {} { poke 0x609F 4 }

set ::on 0; set ::in 0; set ::th 0; set ::nmit 0; set ::H {}; set ::tn 0
debug set_bp [symaddr nmi] {$::on} { if {![peek [symaddr in_nmi]]} { set ::tn [now] } }
debug set_bp [symaddr read_inputs] {$::on && $::tn} { if {$::in} { incr ::nmit [expr {([now]-$::tn)/6}] }; set ::tn 0 }
debug set_bp 0x00B8 {$::on} { set ::th [now]; set ::in 1; set ::nmit 0 }
foreach pc {0x0136 0x0138 0x0141 0x014D} {
    debug set_bp $pc {$::on && $::in} { lappend ::H [expr {([now]-$::th)/6 - $::nmit}]; set ::in 0 }
}
array set ::calls {}; array set ::iys {}
if {[info exists ::env(CALLS)]} {
    foreach a $::env(CALLS) {
        debug set_bp $a {$::on} "incr ::calls($a); set ::iys($a,\[format %04x \[reg iy\]\]) 1"
    }
}

proc play {} {
    set d [lindex {0xfe 0xfd 0xfb 0xf7} [expr {int(rand()*4)}]]
    set fire [expr {rand() < 0.3 ? 0xef : 0xff}]
    inp [expr {$d & $fire}] 0xff
    after time [expr {0.2 + rand()*0.8}] play
}
set throttle off
after time 4   { inp 0xff 0xbf }
after time 4.1 { inp 0xff 0xff }
after time 5   { inp 0xdf 0xff }
after time 5.1 { inp 0xff 0xff }
after time 8   play
if {$alpha > 0} {
    proc force_alpha {} { poke 0x60B2 [expr {[peek 0x60B2] | 3}]; after time $::alpha force_alpha }
    after time 10 force_alpha
}
after time 12 {
    set ::on 1
    set ::v0 [peek16 [symaddr frame_cnt]]; set ::h0 [peek16 [symaddr irq_count]]
    set ::d0 [peek16 [symaddr deferred_cnt]]; set ::s0 [peek16 [symaddr pf_drops]]
}
after time [expr {12 + $secs}] {
    set v [expr {[peek16 [symaddr frame_cnt]] - $::v0}]
    set h [expr {[peek16 [symaddr irq_count]] - $::h0}]
    puts stderr [format "vblanks=%d handlers=%d (%.1f%%) held=%d skipped=%d monsters=%d" $v $h [expr {100.0*$h/$v}] \
        [expr {[peek16 [symaddr deferred_cnt]] - $::d0}] [expr {[peek16 [symaddr pf_drops]] - $::s0}] \
        [llength [lsearch -all -inline -not [lmap k {0 1 2 3 4 5 6 7} {expr {[peek [expr {0x621A + $k*0x15}]] >= 0x80}}] 0]]]
    set s [lsort -integer $::H]; set n [llength $s]
    puts stderr "arcade handler own T: n=$n median=[lindex $s [expr {$n/2}]] p90=[lindex $s [expr {int($n*.9)}]] p99=[lindex $s [expr {int($n*.99)}]]"
    foreach a [lsort [array names ::calls]] {
        puts stderr "calls $a: $::calls($a) iy: [lsort -unique [lmap k [array names ::iys $a,*] {lindex [split $k ,] 1}]]"
    }
    exit
}
after realtime 600 { puts stderr "backstop"; exit }
