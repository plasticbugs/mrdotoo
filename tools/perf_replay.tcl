# Load after tools/diff/cv_replay.tcl: times the arcade handler (entry $00B8
# to its exit, our NMI work inside it subtracted) over the replay, which runs
# the same game every time: a deterministic benchmark for speed patches.
# Prints mean / median / p90 / p99 and the total when the replay exits, and
# the vblanks the whole replay took (our NMI work included; fewer = faster).
proc pr_now {} { expr {[machine_info VDP_frame_count] * 358416 + [machine_info VDP_cycle_in_frame]} }
set ::pr_v0 -1
debug set_bp 0x00B8 {$::pr_v0 < 0} { set ::pr_v0 [peek16 [symaddr frame_cnt]] }
set ::pr_in 0; set ::pr_th 0; set ::pr_nmit 0; set ::pr_H {}; set ::pr_tn 0
debug set_bp [symaddr nmi] {} { if {![peek [symaddr in_nmi]]} { set ::pr_tn [pr_now] } }
debug set_bp [symaddr read_inputs] {$::pr_tn} { if {$::pr_in} { incr ::pr_nmit [expr {([pr_now]-$::pr_tn)/6}] }; set ::pr_tn 0 }
debug set_bp 0x00B8 {} { set ::pr_th [pr_now]; set ::pr_in 1; set ::pr_nmit 0 }
foreach pc {0x0136 0x0138 0x0141 0x014D} {
    debug set_bp $pc {$::pr_in} { lappend ::pr_H [expr {([pr_now]-$::pr_th)/6 - $::pr_nmit}]; set ::pr_in 0 }
}
rename exit pr_exit
proc exit {args} {
    set s [lsort -integer $::pr_H]; set n [llength $s]; set t 0; foreach x $s { incr t $x }
    puts stderr "vblanks for the replay: [expr {([peek16 [symaddr frame_cnt]] - $::pr_v0) & 0xFFFF}]"
    puts stderr [format "arcade handler: n=%d mean=%d median=%d p90=%d p99=%d total=%d" $n [expr {$t/$n}] \
        [lindex $s [expr {$n/2}]] [lindex $s [expr {int($n*.9)}]] [lindex $s [expr {int($n*.99)}]] $t]
    pr_exit
}
