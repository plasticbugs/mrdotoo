# Apple visibility dump (tools/apple_vis.sh): at every NMI (= the picture the
# VDP just showed), write mode/R2/cam/R1, arcade sprite RAM, SAT, displayed name table, SPT.
set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} {
    set f [open $::mrdo_sym]
    foreach line [split [read $f] "\n"] {
        if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] }
    }
    close $f; error "no $name"
}
proc inp {p1 p2} { poke [symaddr inp_p1] $p1; poke [symaddr inp_p2] $p2; poke [symaddr inp_override] 1 }
set ::out [open $::env(AVOUT) wb]
fconfigure $::out -translation binary
set ::av_mode [symaddr mode]; set ::av_cam [symaddr cam]; set ::arc [symaddr ARC_SPRITES]; set ::innmi [symaddr in_nmi]
set ::nd 0
proc avd {} {
  if {[peek $::av_mode] == 1 && [machine_info time] > 7} {
    set pnt [expr {([vdpreg 2] & 0x0F) * 0x400}]
    puts -nonewline $::out [binary format cccc [peek $::av_mode] [vdpreg 2] [peek $::av_cam] [vdpreg 1]]
    puts -nonewline $::out [debug read_block memory $::arc 256]
    puts -nonewline $::out [debug read_block VRAM 0x1B00 128]
    puts -nonewline $::out [debug read_block VRAM $pnt 768]
    puts -nonewline $::out [debug read_block VRAM 0x3800 2048]
    incr ::nd
  }
}
debug set_bp 0x0066 {} avd
after time 4   { inp 0xff 0xbf }
after time 4.1 { inp 0xff 0xff }
after time 5   { inp 0xdf 0xff }
after time 5.1 { inp 0xff 0xff; poke [symaddr inp_override] 0 }
set throttle off
after realtime 5 { puts stderr "rt5 [machine_info time]" }
after realtime 30 { puts stderr "rt30 [machine_info time]"; exit }
after time 0.5 { foreach a {0x32A6 0x44B0 0x4B94} { poke $a 0x18 } }
if {[info exists ::env(LEVEL)]} { debug set_bp 0x1A76 {} { poke 0x609F $::env(LEVEL) } }
expr {srand($::env(SEED))}
set ::dirs {0xfe 0xfd 0xfb 0xf7 0xff}
proc mv {} {
    set d [lindex $::dirs [expr {int(rand()*5)}]]
    if {rand() < 0.15} { set d [expr {$d & 0xef}] }
    poke [symaddr inp_p1] $d; poke [symaddr inp_override] 1; after time [expr {0.3 + rand()*0.8}] mv
}
after time 6 mv
if {[info exists ::env(ALPHA)]} { proc al {} { poke 0x60B2 [expr {[peek 0x60B2] | 3}]; after time 10 al }; after time 12 al }
after time $::env(SECS) { close $::out; puts stderr "AV dumps $::nd"; exit }
