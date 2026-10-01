# Seeded speed scenario (tools/speed_check.sh): level 5, Mr. Do invincible,
# random play from a fixed seed; reports arcade handlers per vblank between
# 8 s and END s (100% = full speed). SCEN: monsters | chomper (a letter
# monster + chomper session forced every 10 s) | ball (fire pressed often).
set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} {
    set f [open $::mrdo_sym]
    foreach line [split [read $f] "\n"] {
        if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] }
    }
    close $f; error "no $name"
}
set ::p1 [symaddr inp_p1]; set ::p2 [symaddr inp_p2]; set ::ov [symaddr inp_override]
proc inp {a b} { poke $::p1 $a; poke $::p2 $b; poke $::ov 1 }
set throttle off
after time 0.5 { foreach a {0x32A6 0x44B0 0x4B94} { poke $a 0x18 } }   ;# invincible (jr nc -> jr)
debug set_bp 0x1A76 {} { poke 0x609F 4 }                               ;# level 5
after time 4   { inp 0xff 0xbf }
after time 4.1 { inp 0xff 0xff }
after time 5   { inp 0xdf 0xff }
after time 5.1 { inp 0xff 0xff; poke $::ov 0 }
set ::h 0; set ::f 0
debug set_bp 0x00B8 {[machine_info time] > 8} { incr ::h }
debug set_bp [symaddr nmi] {[machine_info time] > 8} { incr ::f }
expr {srand($::env(SEED))}
set ::dirs {0xfe 0xfd 0xfb 0xf7 0xff}
set ::fire [expr {$::env(SCEN) eq "ball" ? 0.4 : 0.0}]
proc mv {} {
    set d [lindex $::dirs [expr {int(rand() * 5)}]]
    if {rand() < $::fire} { set d [expr {$d & 0xef}] }
    poke $::p1 $d; poke $::ov 1
    after time 0.7 mv
}
after time 6 mv
if {$::env(SCEN) eq "chomper"} {
    proc force {} { poke 0x60B2 [expr {[peek 0x60B2] | 3}]; after time 10 force }
    after time 8 force
}
after time $::env(END) {
    puts stderr [format "SPEED %s seed %s: %d handlers / %d vblanks = %.1f%%" $::env(SCEN) $::env(SEED) $::h $::f [expr {100.0 * $::h / $::f}]]
    exit
}
