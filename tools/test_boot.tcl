# Boot the ROM, let it run, then check the driver's self-test results and
# take a screenshot. Driven by tools/test_boot.sh; results go to stdout.
set ::mrdo_sym $::env(MRDO_SYM)
proc symaddr {name} {
    set sym $::mrdo_sym
    set f [open $sym]
    foreach line [split [read $f] "\n"] {
        if {[regexp "^${name}: EQU 0x0*(\[0-9A-Fa-f\]+)" $line -> hex]} { close $f; return [expr 0x$hex] }
    }
    close $f
    error "symbol $name not found"
}
set throttle off
# Fast-forward, then render a few real frames so the screenshot has content.
after time $::env(MRDO_SECS) { set throttle on }
after time [expr {$::env(MRDO_SECS) + 0.2}] {
  if {[catch {
    set fc [peek16 [symaddr frame_cnt]]
    set ic [peek16 [symaddr irq_count]]
    set dc [peek16 [symaddr deferred_cnt]]
    puts stderr "RESULT vblanks=$fc arcade_irqs=$ic held=$dc pc=[format %04x [reg pc]]"
    screenshot -raw $::env(MRDO_SHOT)
  } err]} { puts stderr "RESULT error: $err" }
  exit
}
# Never hang the caller if something above fails.
after realtime 30 { puts stderr "RESULT timeout"; exit }
