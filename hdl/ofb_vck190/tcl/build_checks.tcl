#---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
#---------------------------------------------------------------------------------------------------
# Checks of the builds of tcl/build.tcl, in plain Tcl (no Vivado command), so that test/build_checks_test.tcl runs
# them in tclsh on excerpts of logs and reports:
# - Constraint integrity of a run, from its log: a constraint whose object query matched nothing (cell, net, pin,
#   port or clock), a constraint without a valid object, the constraint file of a module that is not in the netlist,
#   a constraint script that failed. Vivado reports these as warnings or errors and continues; the timing analysis
#   then lacks the constraint.
# - Methodology checks of the clock relations: TIMING-6 and TIMING-7 (clocks timed together without a common primary
#   clock or node: a missing clock pair constraint) and TIMING-47 (max delay datapath only between synchronous
#   clocks: a clock pair constraint whose other clock was empty masks a whole clock domain, hold included).
# - The design timing summary: worst setup and hold slack and the number of failing endpoints.
#
# tcl/build.tcl stops on a failed integrity check (after synthesis, or after the results of the implementation are
# written) and reports the timing summary in build_info.txt; a failed timing does not stop the build.
#---------------------------------------------------------------------------------------------------

namespace eval ofb_build_checks {
    # Message ids of a constraint that did not apply
    variable msg_ids {
        {Vivado 12-180} {Vivado 12-507} {Vivado 12-508} {Vivado 12-584} {Vivado 12-627} {Vivado 12-1008}
        {Vivado 12-4739} {Designutils 20-1280} {Common 17-55} {Common 17-1548}
    }
    # Known exception, each entry a list of string match patterns that all match the message line: the scoped Open
    # Logic constraint of the distributed RAM read path names g_async.RdPipe_reg[1][*], which synthesis renames when
    # it retimes the register (RdPipe_reg[1][<bit>]_bret). That path crosses from the write clock to the read clock
    # of an asynchronous FIFO and is bounded by the clock pair constraints of ofb_vck190.xdc, which this check keeps
    # from being lost (no message for them, no TIMING-6, TIMING-7 or TIMING-47). The messages are counted and
    # reported, never dropped. To be removed when the Open Logic constraint matches retimed registers.
    variable exceptions {
        {{*olo_base_ram_sdp.tcl:*} {*g_async.RdPipe_reg\[1\]\[\*\]*}}
    }
    # Expected number of these messages in the implementation log (the Open Logic constraints are not used in
    # synthesis, so none there): 8 VC output FIFOs, each with one Vivado 12-1008, one Vivado 12-4739 and two
    # Vivado 12-180. Another number fails the check: then more or fewer constraints are lost than this exception
    # explains.
    variable known_count 32
    # Methodology checks that fail the build
    variable timing_checks {TIMING-6 TIMING-7 TIMING-47}
}

# Constraint messages of a run log: dict with the lists violations and excepted (the message lines)
proc ofb_build_checks::log_check {log} {
    variable msg_ids
    variable exceptions
    set fh [open $log r]
    set text [read $fh]
    close $fh
    set violations {}
    set excepted {}
    foreach line [split $text "\n"] {
        set hit 0
        foreach id $msg_ids {
            if {[string first "\[$id\]" $line] >= 0} {
                set hit 1
                break
            }
        }
        if {!$hit} { continue }
        set known 0
        foreach entry $exceptions {
            set all 1
            foreach pattern $entry {
                if {![string match $pattern $line]} {
                    set all 0
                    break
                }
            }
            if {$all} {
                set known 1
                break
            }
        }
        if {$known} {
            lappend excepted [string trim $line]
        } else {
            lappend violations [string trim $line]
        }
    }
    return [dict create violations $violations excepted $excepted]
}

# Violations of the methodology checks of the clock relations in a report_methodology report: dict rule -> count
proc ofb_build_checks::methodology_check {rpt} {
    variable timing_checks
    set fh [open $rpt r]
    set text [read $fh]
    close $fh
    set found [dict create]
    foreach line [split $text "\n"] {
        if {[regexp {^\|\s*(TIMING-\d+)\s*\|[^|]*\|[^|]*\|\s*(\d+)\s*\|} $line -> rule n]} {
            if {$rule in $timing_checks} { dict set found $rule $n }
        }
    }
    return $found
}

# Design timing summary of a report_timing_summary report: dict wns, setup_fail, whs, hold_fail (slack in ns as
# written in the report, NA when not analysed)
proc ofb_build_checks::timing_summary {rpt} {
    set fh [open $rpt r]
    set lines [split [read $fh] "\n"]
    close $fh
    set start [lsearch -glob $lines {*Design Timing Summary*}]
    if {$start < 0} { error "no design timing summary in $rpt" }
    for {set i $start} {$i < [llength $lines]} {incr i} {
        if {[string match {*WNS(ns)*WHS(ns)*} [lindex $lines $i]]} { break }
    }
    # Header, dashes, values
    set values [regexp -all -inline {\S+} [lindex $lines [expr {$i + 2}]]]
    if {[llength $values] < 8} { error "unexpected design timing summary in $rpt" }
    return [dict create wns [lindex $values 0] setup_fail [lindex $values 2] whs [lindex $values 4] \
        hold_fail [lindex $values 6]]
}

# True when the integrity checks failed: a constraint message outside the exception, a known message in synthesis,
# a number of known messages in the implementation other than known_count, or a methodology check of the clock
# relations
proc ofb_build_checks::integrity_failed {synth impl methodology} {
    variable known_count
    if {[llength [dict get $synth violations]] > 0 || [llength [dict get $synth excepted]] > 0} { return 1 }
    if {$impl ne ""} {
        if {[llength [dict get $impl violations]] > 0} { return 1 }
        if {[llength [dict get $impl excepted]] != $known_count} { return 1 }
    }
    return [expr {[dict size $methodology] > 0}]
}

# True when setup or hold fails
proc ofb_build_checks::timing_failed {timing} {
    foreach key {wns whs} {
        set v [dict get $timing $key]
        if {[string is double -strict $v] && $v < 0} { return 1 }
    }
    return 0
}

# Summary lines for the console and build_info.txt
proc ofb_build_checks::summary {synth impl methodology timing} {
    variable known_count
    set n_synth [llength [dict get $synth violations]]
    set n_impl [expr {$impl eq "" ? 0 : [llength [dict get $impl violations]]}]
    set known_synth [llength [dict get $synth excepted]]
    set known_impl [expr {$impl eq "" ? 0 : [llength [dict get $impl excepted]]}]
    set rules {}
    dict for {rule n} $methodology { lappend rules "$rule x $n" }
    if {[integrity_failed $synth $impl $methodology]} {
        set text "CONSTRAINT INTEGRITY FAILED: constraints that did not apply: synthesis $n_synth, implementation\
            $n_impl; methodology: [expr {[llength $rules] ? [join $rules {, }] : {none}}]"
    } else {
        set text "constraint integrity: passed (no constraint without its object, no TIMING-6, TIMING-7 or\
            TIMING-47)"
    }
    set known "known Open Logic constraint messages (retimed RAM read register): synthesis $known_synth (expected 0)"
    if {$impl ne ""} { append known ", implementation $known_impl (expected $known_count)" }
    set lines [list $text $known]
    if {$timing ne ""} {
        set t "WNS [dict get $timing wns] ns ([dict get $timing setup_fail] failing setup endpoints), WHS\
            [dict get $timing whs] ns ([dict get $timing hold_fail] failing hold endpoints)"
        if {[timing_failed $timing]} {
            lappend lines "TIMING NOT MET: $t"
        } else {
            lappend lines "timing met: $t"
        }
    }
    return $lines
}

# Details for results/constraint_check.txt: the summary, then every message line
proc ofb_build_checks::write_report {path synth impl methodology timing} {
    set fh [open $path w]
    foreach line [summary $synth $impl $methodology $timing] { puts $fh $line }
    foreach {name result} [list synthesis $synth implementation $impl] {
        if {$result eq ""} { continue }
        puts $fh ""
        puts $fh "$name: constraints that did not apply"
        foreach line [dict get $result violations] { puts $fh "  $line" }
        puts $fh "$name: known Open Logic constraint messages"
        foreach line [dict get $result excepted] { puts $fh "  $line" }
    }
    close $fh
}
