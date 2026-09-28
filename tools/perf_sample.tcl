# PC sampler for tools/perf_heavy.tcl: every SAMPLE seconds of emulated time
# (default 0.0001 = ~358 T-states) record the PC while the arcade handler or
# the NMI runs; writes "pc count" lines to $SAMPLES_OUT at the end.
# Load after perf_heavy.tcl (it sets ::on).
set ::samp [dict create]
set ::sample_dt [expr {[info exists ::env(SAMPLE)] ? $::env(SAMPLE) : 0.0001}]
proc sample_tick {} {
    if {$::on} { dict incr ::samp [format %04x [reg pc]] }
    after time $::sample_dt sample_tick
}
after time 12 sample_tick
rename exit perf_exit
proc exit {args} {
    set f [open $::env(SAMPLES_OUT) w]
    dict for {k v} $::samp { puts $f "$k $v" }
    close $f
    perf_exit
}
