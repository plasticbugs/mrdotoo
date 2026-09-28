# Insert a coin, start a 1-player game, walk around; screenshots along the way.
# Env: MRDO_SYM, MRDO_OUT (screenshot prefix).
set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} {
    set f [open $::mrdo_sym]
    foreach line [split [read $f] "\n"] {
        if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] }
    }
    close $f
    error "symbol $name not found"
}
proc inp {p1 p2} {
    poke [symaddr inp_p1] $p1
    poke [symaddr inp_p2] $p2
    poke [symaddr inp_override] 1
}
# Render a few real frames (throttle on), capture, then fast-forward again.
proc shot_at {t name} {
    after time $t { set throttle on }
    after time [expr {$t + 0.2}] [list screenshot -raw $::env(MRDO_OUT)_$name.png]
    after time [expr {$t + 0.25}] { set throttle off }
}
proc status {tag} {
    puts stderr "STATUS $tag vblanks=[peek16 [symaddr frame_cnt]] irqs=[peek16 [symaddr irq_count]] held=[peek16 [symaddr deferred_cnt]]"
}
set throttle off
after time 3   { inp 0xff 0xff }
after time 4   { inp 0xff 0xbf }
after time 4.1 { inp 0xff 0xff }
after time 5.5 { inp 0xdf 0xff }
after time 6.0 { inp 0xff 0xff }
after time 9   { status start }
shot_at 9 start
after time 10  { inp 0xfb 0xff }
after time 12  { inp 0xf7 0xff }
after time 13  { inp 0xfe 0xff }
after time 15  { inp 0xef 0xff }
after time 15.2 { inp 0xff 0xff }
after time 18  { status play }
shot_at 18 play
after time 19.5  { exit }
after realtime 60 { puts stderr "STATUS timeout"; exit }
