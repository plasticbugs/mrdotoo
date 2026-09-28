# Load after tools/diff/cv_replay.tcl on a replay that contains ball bursts
# (e.g. seed 2, handlers 1900-2000). Per vblank it records the driver's NMI
# work and the arcade handler's time, grouped by how many ball-code ($70)
# sprites the arcade had queued; prints a table when the replay exits.
proc bc_now {} { expr {[machine_info VDP_frame_count] * 358416 + [machine_info VDP_cycle_in_frame]} }
proc bc_frags {} {
    set n 0
    for {set a 0x6950} {$a < 0x6A50} {incr a 4} {
        if {[peek [expr {$a + 1}]] == 0} break
        if {[peek $a] == 0x70} { incr n }
    }
    return $n
}
set ::bc_t0 0; set ::bc_th 0; set ::bc_f 0; set ::bc_hf 0
array set ::bc_nmi {}; array set ::bc_arc {}
debug set_bp [symaddr nmi] {} { set ::bc_t0 [bc_now]; set ::bc_f [bc_frags] }
debug set_bp [symaddr read_inputs] {$::bc_t0} {
    set k [expr {($::bc_f + 4) / 5 * 5}]
    lappend ::bc_nmi($k) [expr {([bc_now] - $::bc_t0) / 6}]; set ::bc_t0 0
}
debug set_bp 0x00B8 {} { set ::bc_th [bc_now]; set ::bc_hf [bc_frags] }
foreach pc {0x0136 0x0138 0x0141 0x014D} {
    debug set_bp $pc {$::bc_th} {
        set k [expr {($::bc_hf + 4) / 5 * 5}]
        lappend ::bc_arc($k) [expr {([bc_now] - $::bc_th) / 6}]; set ::bc_th 0
    }
}
proc bc_stat {l} {
    set s [lsort -integer $l]; set n [llength $s]
    format "n=%-5d median=%-6d max=%d" $n [lindex $s [expr {$n/2}]] [lindex $s end]
}
rename exit bc_exit
proc exit {args} {
    foreach k [lsort -integer [array names ::bc_nmi]] {
        set a [expr {[info exists ::bc_arc($k)] ? [bc_stat $::bc_arc($k)] : "-"}]
        puts stderr [format "fragments <=%-3d NMI %-32s arcade %s" $k [bc_stat $::bc_nmi($k)] $a]
    }
    bc_exit
}
