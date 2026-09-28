# Measure the driver's per-vblank work (NMI entry -> read_inputs, i.e. the
# renderer + sprites) in Z80 T-states, during a scripted game.
# Env: MRDO_SYM. Prints median / p95 / max after 20 emulated seconds.
set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} {
    set f [open $::mrdo_sym]
    foreach line [split [read $f] "\n"] {
        if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] }
    }
    close $f; error "no $name"
}
proc now {} { expr {[machine_info VDP_frame_count] * 358416 + [machine_info VDP_cycle_in_frame]} }
set ::on 0; set ::t0 0; set ::ts 0; set ::nmi_samples {}; set ::spr_samples {}
debug set_bp [symaddr nmi] {$::on} { set ::t0 [now]; set ::ts 0 }
debug set_bp [symaddr sprites_update] {$::on} { set ::ts [now] }
set ::loads 0; set ::slots 0; set ::resolves 0; set ::hits 0
set ::te 0; set ::tc 0; set ::p1 {}; set ::p2 {}; set ::p3 {}
debug set_bp [symaddr sprites_emit] {$::on && $::ts} { set ::te [now]; lappend ::p1 [expr {($::te - $::ts)/6}] }

debug set_bp [symaddr sprite_resolve] {$::on} { incr ::resolves }
debug set_bp [symaddr sprites_update.hit] {$::on} { incr ::hits }
debug set_bp [symaddr sprite_load] {$::on} { incr ::loads }
debug set_bp [symaddr sprite_slot] {$::on} { incr ::slots }
debug set_bp [symaddr check_colourway] {$::on} {
    if {$::ts} { lappend ::spr_samples [expr {([now] - $::ts) / 6}]; set ::ts 0 }
    if {$::te} { lappend ::p2 [expr {([now] - $::te) / 6}]; set ::te 0 }
}
debug set_bp [symaddr read_inputs] {$::on} { lappend ::nmi_samples [expr {([now] - $::t0) / 6}] }
set throttle off
after time 4   { poke [symaddr inp_p1] 0xff; poke [symaddr inp_p2] 0xbf; poke [symaddr inp_override] 1 }
after time 4.1 { poke [symaddr inp_p2] 0xff }
after time 5   { poke [symaddr inp_p1] 0xdf }
after time 5.1 { poke [symaddr inp_p1] 0xff }
after time 9   { set ::on 1 }
after time 10  { poke [symaddr inp_p1] 0xfb }
after time 12  { poke [symaddr inp_p1] 0xf7 }
after time 13  { poke [symaddr inp_p1] 0xfe }
after time 15  { poke [symaddr inp_p1] 0xef }
after time 15.2 { poke [symaddr inp_p1] 0xff }
after time 20 {
    puts stderr "sprites drawn=$::hits resolves=$::resolves slot lookups=$::slots pattern loads=$::loads over [llength $::nmi_samples] frames"
    foreach {name l} [list "NMI work (render+sprites)" $::nmi_samples "  of which sprites" $::spr_samples "    resolve + bands" $::p1 "    emit" $::p2] {
        set s [lsort -integer $l]; set n [llength $s]
        if {!$n} continue
        puts stderr [format "%-28s n=%d median=%d p95=%d max=%d T-states" $name $n [lindex $s [expr {$n/2}]] [lindex $s [expr {int($n*0.95)}]] [lindex $s end]]
    }
    exit
}
after realtime 60 { puts stderr "backstop"; exit }
