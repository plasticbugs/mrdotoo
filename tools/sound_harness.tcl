# Sound engine harness (tools/sound_harness.sh): the game logic frozen, the
# arcade sound engine driven by a seeded schedule of requests, every chip
# write logged per vblank. The output depends only on the engine, not on game
# speed, so two builds (e.g. before / after an engine rewrite) must produce
# identical logs.
#
# - The game stays in its attract sequence (no coin): it never posts a sound
#   there ($02D9/$02EA return unless $E000 bit 7 is set), so the engine sees
#   only these requests, whatever speed the game logic runs at. (Freezing the
#   arcade handler instead broke the vblank delivery: an NMI storm.) Its stop
#   entry $02EA has no such check, so it becomes a `ret` (the attract posts
#   stops at times that depend on game speed: the engine RAM differed), and
#   so does its reset-all-sounds routine $5A80 (called from $11E4 / $194E /
#   $22E7 as the attract runs).
# - Requests as the game posts them: $02D9 = state[$EC00 + id] = 1, $02EA =
#   set 2 (stop); plus snd_req, the fast-path flag.
# - Counted in engine ticks, not vblanks: the NMI owes and catches up ticks
#   when it is busy (snd_due), so ticks per vblank depend on CPU timing. Each
#   tick k gets its requests just before it runs (breakpoint at $5A90).
# - Log lines: "v <tick> <ram crc>" per tick (the engine's work RAM
#   $EC00-$EFFF = CV $6C00-$6FFF, as the tick starts), "r <id>" / "s <id>"
#   for requests/stops, "w <port> <value>" for each write to the SN76489
#   ($FF) or the SGM AY ($50 address, $51 data).
set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} {
    set f [open $::mrdo_sym]
    foreach line [split [read $f] "\n"] {
        if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] }
    }
    close $f; error "no $name"
}
set ::sndreq [symaddr snd_req]
set ::out [open $::env(SHOUT) w]
set ::on 0
# sound ids that have streams (MRDO_SOUND_MAP.md: $00, $09-$0E, $18 are silent)
set ::ids {}
foreach i {1 2 3 4 5 6 7 8 15 16 17 18 19 20 21 22 23 25 26 27 28 29 30 31 32 33 34 35 36 37} { lappend ::ids $i }
set ::sched [dict create]
proc at {v what} { dict lappend ::sched $v $what }
# A: each sound alone (music stopped after 360 vblanks), 40 quiet vblanks after
set t 30
foreach id $::ids { at $t "r $id"; at [expr {$t + 360}] "s $id"; incr t 400 }
# B: a seeded random mix (overlaps, priority steals, stops mid-note)
expr {srand($::env(SEED))}
set n [expr {$t + $::env(MIX)}]
for {set sv $t} {$sv < $n} {incr sv} {
    set x [expr {rand()}]
    if {$x < 0.03} { at $sv "r [lindex $::ids [expr {int(rand() * [llength $::ids])}]]" } elseif {$x < 0.04} { at $sv "s [lindex $::ids [expr {int(rand() * [llength $::ids])}]]" }
}
set ::end [expr {$n + 300}]
set ::v -1                  ;# (after the schedule: global scope)

proc wlog {port} { if {$::on} { puts $::out "w $port [format %02x $::wp_last_value]" } }
debug set_watchpoint write_io 0xFF {} { wlog ff }
debug set_watchpoint write_io 0x50 {} { wlog 50 }
debug set_watchpoint write_io 0x51 {} { wlog 51 }
proc vb {} {
    if {!$::on} return
    incr ::v
    if {$::v % 2000 == 0} { puts stderr "harness tick $::v / $::end"; flush $::out }
    puts $::out "v $::v [format %08x [zlib crc32 [debug read_block memory 0x6C00 1024]]]"
    if {[dict exists $::sched $::v]} {
        foreach e [dict get $::sched $::v] {
            lassign $e k id
            set a [expr {0x6C00 + $id}]
            if {$k eq "r"} { poke $a 1 } else { poke $a [expr {[peek $a] | 4}] }
            poke $::sndreq 1
            puts $::out "$k $id"
        }
    }
    if {[peek 0x6000] & 0x80} { puts stderr "harness: the game started (\$E000 bit 7)"; close $::out; exit }
    if {$::v >= $::end} { close $::out; puts stderr [format "COST %d ticks, %.0f T a tick" $::v [expr {$::cost * 3579545.0 / $::v}]]; exit }
}
debug set_bp 0x5A90 {} vb
# Engine cost: emulated time from the tick's entry to its return (the `jr`
# after `call SND_TICK` in snd_nmi_tick), summed: printed at the end in
# T-states (3.579545 MHz). Deterministic for a given ROM and schedule.
set ::cost 0.0; set ::t0 0
debug set_bp 0x5A90 {} { set ::t0 [machine_info time] }
debug set_bp [expr {[symaddr snd_nmi_tick.done] - 2}] {} { if {$::on && $::t0 > 0} { set ::cost [expr {$::cost + [machine_info time] - $::t0}] } }
set throttle off
after time 2 { poke 0x02EA 0xC9; poke 0x5A80 0xC9; set ::on 1 }
