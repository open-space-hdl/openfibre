#---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
#---------------------------------------------------------------------------------------------------
# Register access to the MIB of the VCK190 reference design over JTAG with XSDB (master port M_AXI_FPD of
# the CIPS, MIB at 0xA400_0000), and the bit error rate test of the lanes with the PRBS generators and
# checkers of the transceivers (user guide, section 6).
#
# Usage (XSDB of Vivado or Vitis 2025.2, board in JTAG boot mode):
#   xsdb% source hdl/ofb_vck190/tcl/xsdb_mib.tcl
#   xsdb% mib_connect                        ;# connect and select the Versal device
#   xsdb% device program <device image>.pdi  ;# unless programmed with the Vivado Hardware Manager
#   xsdb% mib_rd 0x000                       ;# ID
#   xsdb% mib_wr 0x100 0x63                  ;# LANE_CTRL of lane 0
#   xsdb% prbs_ber 0 31 480                  ;# lane 0, PRBS-31, 480 s
#   xsdb% prbs_off 0                         ;# end of the PRBS test of lane 0
#
# Documentation: hdl/ofb_vck190/docs/hardware_test.md
#---------------------------------------------------------------------------------------------------

set MibBase 0xA4000000

# Connects to the hardware server and selects the Versal device as the target of the memory accesses
proc mib_connect {} {
    connect
    targets -set -nocase -filter {name =~ "*Versal*"}
}

# Reads the MIB register at the byte offset ofs and returns its value (hexadecimal)
proc mib_rd {ofs} {
    set v [mrd -force -value [expr {$::MibBase + $ofs}]]
    return [format 0x%08X $v]
}

# Writes value to the MIB register at the byte offset ofs
proc mib_wr {ofs value} {
    mwr -force [expr {$::MibBase + $ofs}] $value
}

# Offset of a lane register: reg = 0x100 (LANE_CTRL) to 0x11C (LANE_PRBS_WORDS)
proc lane_ofs {lane reg} {
    return [expr {$reg + 0x20 * $lane}]
}

# Pattern code of LANE_PRBS_CTRL for PRBS-7, -9, -15, -23 or -31
proc prbs_code {pattern} {
    set codes {7 1 9 2 15 3 23 4 31 5}
    if {![dict exists $codes $pattern]} { error "pattern must be 7, 9, 15, 23 or 31" }
    return [dict get $codes $pattern]
}

# Bit error rate test of one lane: the pattern is sent and checked on the lane (far end with the same pattern,
# QSFP loopback module or near-end serial loopback, LANE_CTRL bit 16), the counters run for the given time, then
# one forced error checks the measurement chain. The SpaceFibre link of the lane is down during the test.
proc prbs_ber {lane pattern seconds} {
    set sel [expr {[prbs_code $pattern] * 0x11}]
    set ctrl [lane_ofs $lane 0x114]
    mib_wr $ctrl $sel
    after 10
    mib_wr $ctrl [expr {0x10000 | $sel}]
    set locked 0
    for {set i 0} {$i < 100} {incr i} {
        if {[expr {[mib_rd [lane_ofs $lane 0x104]] & 0x80}] != 0} { set locked 1; break }
        after 10
    }
    if {!$locked} { error "lane $lane: PRBS checker not locked (pattern, cable or far end)" }
    puts "lane $lane: PRBS-$pattern checker locked, measuring for $seconds s"
    for {set s 0} {$s < $seconds} {incr s} { after 1000 }
    mib_wr $ctrl [expr {0x100 | $sel}]
    set errors [expr {[mib_rd [lane_ofs $lane 0x118]]}]
    set words [expr {[mib_rd [lane_ofs $lane 0x11C]]}]
    mib_wr $ctrl $sel
    set bits [expr {double($words) * 65536.0 * 40.0}]
    if {$bits == 0} { error "lane $lane: no word checked" }
    if {$errors == 0} {
        puts [format "lane %d: %.3g bits, no error, BER below %.2g (95 %% confidence)" $lane $bits [expr {3.0 / $bits}]]
    } else {
        puts [format "lane %d: %.3g bits, %d words with errors, BER %.2g" $lane $bits $errors [expr {$errors / $bits}]]
    }
    mib_wr $ctrl [expr {0x20000 | $sel}]
    after 10
    set after_force [expr {[mib_rd [lane_ofs $lane 0x118]]}]
    puts "lane $lane: forced error counted [expr {$after_force - $errors}] time(s) (expected 1)"
    return [list $errors $words]
}

# Ends the PRBS test of a lane (LaneStart or AutoStart starts the link again)
proc prbs_off {lane} {
    mib_wr [lane_ofs $lane 0x114] 0
}
