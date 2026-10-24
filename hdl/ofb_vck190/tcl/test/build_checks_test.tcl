#---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
#---------------------------------------------------------------------------------------------------
# Test of tcl/build_checks.tcl in tclsh (no Vivado): the checks run on excerpts of synthesis and implementation logs
# and of the methodology and timing summary reports, written to a temporary directory, in the format Vivado 2025.2
# writes them. Cases: the reference clock read after the clock pair constraints (the lane clock not found in
# synthesis, TIMING-6, TIMING-7 and TIMING-47 after the implementation), the order of tcl/build.tcl (only the known
# Open Logic messages), a number of known messages other than the expected one, a further constraint without its
# object, timing met and not met.
#
# Usage: tclsh hdl/ofb_vck190/tcl/test/build_checks_test.tcl (exit code 1 when a check fails)
#---------------------------------------------------------------------------------------------------

source [file join [file dirname [file normalize [info script]]] .. build_checks.tcl]

set tmp [file join [expr {[info exists env(TMPDIR)] ? $env(TMPDIR) : [expr {[info exists env(TEMP)] ? $env(TEMP) :
    "/tmp"}]}] ofb_build_checks_test_[pid]]
file mkdir $tmp
set failures 0
set checks 0

proc fixture {name text} {
    global tmp
    set path [file join $tmp $name]
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
    return $path
}

proc check {what got expected} {
    global failures checks
    incr checks
    if {$got ne $expected} {
        puts "FAIL: $what: got '$got', expected '$expected'"
        incr failures
    }
}

# Logs ------------------------------------------------------------------------------------------------------------

set synth_common {INFO: [Synth 8-7079] Multithreading enabled for synth_design using a maximum of 2 processes.
Parsing XDC File [/build/hdl/ofb_vck190/constr/ofb_vck190.xdc]
INFO: [Timing 38-35] Done setting XDC timing constraints. [/build/hdl/ofb_vck190/constr/ofb_vck190.xdc:47]
Finished Parsing XDC File [/build/hdl/ofb_vck190/constr/ofb_vck190.xdc]
WARNING: [Synth 8-7129] Port Cfg_Unused[3] in module ofb_example is either unconnected or has no load
INFO: [Common 17-14] Message 'Vivado 12-180' appears 100 times and further instances of the messages will be disabled.
}
set lane_clk_lost {WARNING: [Vivado 12-1008] No clocks found for command 'get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *i_pa/i_bufg/O}]'. [/build/hdl/ofb_vck190/constr/ofb_vck190.xdc:42]
}
set synth_old [fixture synth_old.log "$synth_common$lane_clk_lost"]
set synth_new [fixture synth_new.log $synth_common]

# The scoped Open Logic constraint of one VC output FIFO RAM whose read register was retimed (four messages)
set ram_sdp {CRITICAL WARNING: [Vivado 12-180] No cells matched 'g_async.RdPipe_reg[1][*]'. [/build/open-logic/src/base/tcl/olo_base_ram_sdp.tcl:17]
WARNING: [Vivado 12-1008] No clocks found for command 'get_clocks -of_objects [get_cells -hierarchical {g_async.RdPipe_reg[1][*]}]'. [/build/open-logic/src/base/tcl/olo_base_ram_sdp.tcl:17]
CRITICAL WARNING: [Vivado 12-180] No cells matched 'g_async.RdPipe_reg[1][*]'. [/build/open-logic/src/base/tcl/olo_base_ram_sdp.tcl:17]
ERROR: [Vivado 12-4739] set_max_delay:No valid object(s) found for '-to [get_cells -hierarchical {g_async.RdPipe_reg[1][*]}]'. [/build/open-logic/src/base/tcl/olo_base_ram_sdp.tcl:17]
}
set impl_common {Parsing XDC File [/build/vivado_out/ofb_vck190/ofb_vck190_refclk_clock.xdc]
Finished Parsing XDC File [/build/vivado_out/ofb_vck190/ofb_vck190_refclk_clock.xdc]
WARNING: [Constraints 18-402] set_max_delay: 'i_pa/i_lane_rst/g_tmr.g_chain[2].RstSyncChain[2]_i_1' is not a valid startpoint. [/build/open-logic/src/base/tcl/olo_base_reset_gen.tcl:15]
}
set impl_new [fixture impl_new.log "$impl_common[string repeat $ram_sdp 8]"]
set impl_31 [fixture impl_31.log "$impl_common[string repeat $ram_sdp 7][join [lrange [split $ram_sdp \n] 1 3] \n]\n"]
set lost {CRITICAL WARNING: [Vivado 12-180] No cells matched 'i_core/i_dl/i_removed*'. [/build/hdl/ofb_vck190/constr/ofb_vck190.xdc:50]
}
set impl_extra [fixture impl_extra.log "$impl_common[string repeat $ram_sdp 8]$lost"]

# Reports ---------------------------------------------------------------------------------------------------------

set meth_head {Table of Contents
-----------------
1. REPORT SUMMARY
2. REPORT DETAILS

1. REPORT SUMMARY
-----------------
            Netlist: netlist
          Floorplan: design_1
      Design limits: <entire design considered>
             Max violations: <unlimited>
             Violations found: 1284
+-----------+------------------+-------------------------------------------------------------------------------------------------------+------------+
| Rule      | Severity         | Description                                                                                           | Violations |
+-----------+------------------+-------------------------------------------------------------------------------------------------------+------------+
}
set meth_old [fixture meth_old.rpt "$meth_head| TIMING-6  | Critical Warning | No common primary clock between related clocks\
    | 3          |
| TIMING-7  | Critical Warning | No common node between related clocks | 3          |
| TIMING-8  | Critical Warning | No common period between related clocks | 1          |
| PDRC-190  | Warning          | Suboptimally placed synchronized register chain | 117        |
| TIMING-47 | Warning          | False path, asynchronous clock group or max delay datapath only constraint between synchronous clocks | 2 \
             |
+-----------+------------------+------------+
"]
set meth_new [fixture meth_new.rpt "$meth_head| PDRC-190  | Warning          | Suboptimally placed synchronized register\
    chain | 117        |
| TIMING-9  | Warning          | Unknown CDC Logic | 1          |
+-----------+------------------+------------+
"]

proc timing_rpt {name values} {
    return [fixture $name "------------------------------------------------------------------------------------------------
| Design Timing Summary
| ---------------------
------------------------------------------------------------------------------------------------

    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------
$values


All user specified timing constraints are met.
"]
}
set tim_old [timing_rpt tim_old.rpt "     -5.435   -12940.861                   2583               131752        0.000        0.000\
                      0               107025        2.594        0.000                       0                 58773"]
set tim_met [timing_rpt tim_met.rpt "      0.030        0.000                      0               131752        0.012        0.000\
                      0               107025        2.594        0.000                       0                 58773"]

# Checks ----------------------------------------------------------------------------------------------------------

# Synthesis
set s_old [ofb_build_checks::log_check $synth_old]
set s_new [ofb_build_checks::log_check $synth_new]
check "synthesis, old order: constraints that did not apply" [llength [dict get $s_old violations]] 1
check "synthesis, old order: the lane clock query" [string match {*i_pa/i_bufg/O*} [lindex [dict get $s_old violations] 0]] 1
check "synthesis, old order: integrity failed" [ofb_build_checks::integrity_failed $s_old "" {}] 1
check "synthesis, new order: constraints that did not apply" [llength [dict get $s_new violations]] 0
check "synthesis, new order: integrity passed" [ofb_build_checks::integrity_failed $s_new "" {}] 0
# The Open Logic constraints are not used in synthesis: a known message there is not expected
set s_known [ofb_build_checks::log_check [fixture synth_known.log "$synth_common$ram_sdp"]]
check "synthesis with a known Open Logic message: integrity failed" \
    [ofb_build_checks::integrity_failed $s_known "" {}] 1

# Implementation
set i_new [ofb_build_checks::log_check $impl_new]
set i_31 [ofb_build_checks::log_check $impl_31]
set i_extra [ofb_build_checks::log_check $impl_extra]
check "implementation: known Open Logic messages" [llength [dict get $i_new excepted]] 32
check "implementation: constraints that did not apply" [llength [dict get $i_new violations]] 0
check "implementation, new order: integrity passed" [ofb_build_checks::integrity_failed $s_new $i_new {}] 0
check "implementation, 31 known messages: integrity failed" [ofb_build_checks::integrity_failed $s_new $i_31 {}] 1
check "implementation, further constraint lost: violations" [llength [dict get $i_extra violations]] 1
check "implementation, further constraint lost: integrity failed" \
    [ofb_build_checks::integrity_failed $s_new $i_extra {}] 1

# Methodology
set m_old [ofb_build_checks::methodology_check $meth_old]
set m_new [ofb_build_checks::methodology_check $meth_new]
check "methodology, old order" $m_old [dict create TIMING-6 3 TIMING-7 3 TIMING-47 2]
check "methodology, new order" [dict size $m_new] 0
check "methodology, old order: integrity failed" [ofb_build_checks::integrity_failed $s_new $i_new $m_old] 1

# Timing summary
set t_old [ofb_build_checks::timing_summary $tim_old]
set t_met [ofb_build_checks::timing_summary $tim_met]
check "timing summary values" $t_old [dict create wns -5.435 setup_fail 2583 whs 0.000 hold_fail 0]
check "timing not met" [ofb_build_checks::timing_failed $t_old] 1
check "timing met" [ofb_build_checks::timing_failed $t_met] 0
check "hold not met" [ofb_build_checks::timing_failed [dict create wns 0.120 setup_fail 0 whs -0.039 hold_fail 15]] 1

# Reasons that fail an implemented build: constraint integrity and timing
check "failure reasons, old order" [ofb_build_checks::failure_reasons $s_old $i_new $m_old $t_old] \
    [list "CONSTRAINT INTEGRITY FAILED" "TIMING NOT MET"]
check "failure reasons, timing only" [ofb_build_checks::failure_reasons $s_new $i_new $m_new $t_old] \
    [list "TIMING NOT MET"]
check "failure reasons, passed" [llength [ofb_build_checks::failure_reasons $s_new $i_new $m_new $t_met]] 0

# Summary lines
set sum_old [ofb_build_checks::summary $s_old $i_new $m_old $t_old]
set sum_new [ofb_build_checks::summary $s_new $i_new $m_new $t_met]
check "summary, old order" [lindex $sum_old 0] "CONSTRAINT INTEGRITY FAILED: constraints that did not apply: synthesis 1,\
    implementation 0; methodology: TIMING-6 x 3, TIMING-7 x 3, TIMING-47 x 2"
check "summary, known messages" [lindex $sum_new 1] "known Open Logic constraint messages (retimed RAM read register):\
    synthesis 0 (expected 0), implementation 32 (expected 32)"
check "summary, timing not met" [lindex $sum_old 2] "TIMING NOT MET: WNS -5.435 ns (2583 failing setup endpoints), WHS\
    0.000 ns (0 failing hold endpoints)"
check "summary, new order" [lindex $sum_new 0] "constraint integrity: passed (no constraint without its object, no\
    TIMING-6, TIMING-7 or TIMING-47)"
check "summary, timing met" [lindex $sum_new 2] "timing met: WNS 0.030 ns (0 failing setup endpoints), WHS 0.012 ns\
    (0 failing hold endpoints)"

# Report file
set report [file join $tmp constraint_check.txt]
ofb_build_checks::write_report $report $s_old $i_new $m_old $t_old
set fh [open $report r]
set text [read $fh]
close $fh
check "report: the lost lane clock constraint" [string match {*synthesis: constraints that did not apply*i_pa/i_bufg/O*} \
    $text] 1
check "report: the known messages listed" [regexp -all {olo_base_ram_sdp.tcl:17} $text] 32

file delete -force $tmp
if {$failures > 0} {
    puts "build_checks_test: $failures of $checks checks failed"
    exit 1
}
puts "build_checks_test: $checks checks passed"
