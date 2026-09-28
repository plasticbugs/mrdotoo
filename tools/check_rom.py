#!/usr/bin/env python3
"""Build check: reading $FFC0-$FFFF switches MegaCart banks, so no switchable
bank may hold data in its last 64 bytes. usage: check_rom.py ROM"""
import sys
rom = open(sys.argv[1], "rb").read()
banks = len(rom) // 16384
bad = [b for b in range(banks - 1) if any(x != 0xFF for x in rom[b * 16384 + 0x3FC0:(b + 1) * 16384])]
if bad:
    sys.exit(f"{sys.argv[1]}: data in the $FFC0-$FFFF hotspot of bank(s) {bad}")
