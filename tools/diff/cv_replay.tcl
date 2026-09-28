# Replay the MAME-recorded inputs on the ColecoVision build and dump arcade
# work RAM ($6000-$6FFF here) at the same sync point ($00D5) of every handler.
# Env: MRDO_SYM, REF (recording prefix), OUTRAM (dump file), FRAMES.
set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} {
    set f [open $::mrdo_sym]
    foreach line [split [read $f] "\n"] {
        if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] }
    }
    close $f
    error "symbol $name not found"
}
set ::IO [expr 0x63B0]
set ::ovr [symaddr inp_override]
set ::ip1 [symaddr inp_p1]
set ::ip2 [symaddr inp_p2]
# inputs: per handler, per port, the value (carried forward). Reads before
# the sync point (coin poll, PC $01A6-$01F9) are applied at handler start,
# later ones at the sync point, so a value that changed mid-handler in MAME
# changes at the same place here.
set ::cur {255 255 223 255}
set ::pre [dict create]
set ::post [dict create]
set f [open $::env(REF).inp]
foreach line [split [read $f] "\n"] {
    if {[scan $line "%d %d %d %x" h port v pc] == 4} {
        if {$h < 0} { set h 0 }
        if {$pc >= 0x01A6 && $pc < 0x01FA} {
            dict lappend ::pre $h [list $port $v]
        } else {
            dict lappend ::post $h [list $port $v]
        }
    }
}
close $f
proc apply_inputs {changes} {
    if {[dict exists $changes $::h]} {
        foreach pv [dict get $changes $::h] { lset ::cur [lindex $pv 0] [lindex $pv 1] }
    }
    for {set p 0} {$p < 4} {incr p} { poke [expr {$::IO + 4 + $p}] [lindex $::cur $p] }
    poke $::ip1 [lindex $::cur 0]
    poke $::ip2 [lindex $::cur 1]
    poke $::ovr 1
}
set ::h 0
set ::maxh $::env(FRAMES)
set ::out [open $::env(OUTRAM) wb]
fconfigure $::out -translation binary

proc on_handler {} {
    if {[info exists ::env(HTRACE)] && $::h >= $::env(HTRACE) && $::h <= $::env(HTRACE) + 4} {
        puts stderr [format "HT h=%d handler entry sp=%04x ret=%04x" $::h [reg sp] [peek16 [reg sp]]]
    }
    apply_inputs $::pre
}
# optional: SNAP=h: screenshot at handler h (renders real frames from h-40)
proc on_sync {} {
    if {[info exists ::env(SNAP)]} {
        if {$::h == $::env(SNAP) - 40} { set ::throttle on }
        if {$::h == $::env(SNAP)} {
            debug break
            after realtime 0.3 [list apply {{} {
                screenshot -raw $::env(SNAPFILE)
                exit
            }}]
        }
    }
    apply_inputs $::post
    puts -nonewline $::out [debug read_block memory 0x6000 4096]
    puts -nonewline $::out [debug read_block memory 0x7000 4096]
    incr ::h
    if {$::h >= $::maxh} { close $::out; exit }
}
# optional: WATCH=hexaddr (CV address) logs every write with PC and handler
if {[info exists ::env(WATCH)]} {
    debug set_watchpoint write_mem 0x$::env(WATCH) {} {
        puts stderr [format "WATCH h=%d pc=%04x <- %02x" $::h [reg pc] $::wp_last_value]
    }
}
# optional: RTRACE=h logs fg-tile reads during handler h (after its sync)
if {[info exists ::env(RTRACE)]} {
    set ::rt [expr {$::env(RTRACE) + 1}]
    debug set_watchpoint read_mem {0x7C00 0x7FFF} {} {
        if {$::h == $::rt} {
            puts stderr [format "RT pc=%04x %04x=%02x" [reg pc] [expr {$::wp_last_address + 0x1000}] $::wp_last_value]
        }
    }
}
if {[info exists ::env(ITRACE)]} {
    set ::it $::env(ITRACE)
    debug set_watchpoint read_mem [expr {$::IO + 4}] {} {
        if {$::h >= $::it && $::h <= $::it + 3} {
            puts stderr [format "IT n=%d pc=%04x v=%02x" $::h [reg pc] $::wp_last_value]
        }
    }
}
debug set_bp 0x00B8 {} on_handler
debug set_bp 0x00D5 {} on_sync
# Stall detector: if no handler reaches the sync point for 5 emulated
# seconds, the port has hung. Report where the CPU is and stop.
set ::last_h -1
proc stall_check {} {
    if {$::h == $::last_h} {
        set st {}
        for {set i 0} {$i < 24} {incr i 2} { lappend st [format %04x [peek16 [expr {[reg sp] + $i}]]] }
        puts stderr [format "STALL at handler %d: pc=%04x sp=%04x stack: %s" $::h [reg pc] [reg sp] [join $st { }]]
        close $::out
        # watch the vblank paths for a few frames, then quit
        foreach n {nmi.direct nmi.hold take_irq irq_after_ei irq_enter} {
            debug set_bp [symaddr $n] {} [list apply {{n} {
                puts stderr [format "  %-12s sp=%04x (sp)=%04x (sp+8)=%04x" $n [reg sp] [peek16 [reg sp]] [peek16 [expr {[reg sp]+8}]]]
            }} $n]
        }
        foreach a {0x00b8 0x00d5 0x0012 0x0008} {
            debug set_bp $a {} [list apply {{a} { puts stderr [format "  bp %04x sp=%04x" $a [reg sp]] }} $a]
        }
        after time 0.05 exit
    }
    set ::last_h $::h
    after time 5 stall_check
}
after time 5 stall_check
set throttle off
if {![info exists ::no_timeout]} { after realtime 120 { puts stderr "timeout at handler $::h"; exit } }
