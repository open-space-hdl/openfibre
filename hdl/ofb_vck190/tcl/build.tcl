#---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
#---------------------------------------------------------------------------------------------------
# Builds the OpenFibre reference design for the AMD VCK190: project in vivado_out/ofb_vck190, transceiver
# wizard instance, Open Logic and OpenFibre sources, constraints, synthesis, implementation and device image.
#
# Usage (from the repository root):
#   vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl [-tclargs <words>]
#   The words are optional and come in any order, for example -tclargs all si570 100:
#   <step>: project (create the project only), rtl (project and RTL elaboration of the design), synth, impl,
#   all (default: all, device image included)
#   <refclk>: source of the transceiver reference clock, which selects its pins
#   (constr/ofb_vck190_refclk_<refclk>.xdc): si570 (default: oscillator Si570 through the clock buffer SI53340 to
#   GTY_REFCLK0 of GTY quad 201) or 8a34001 (clock generator 8A34001, output Q1, to MGTREFCLK1 of GTY quad 200)
#   <frequency>: frequency of the reference clock in MHz, 100 or 156.25, for the transceiver wizard instance and the
#   clock constraint (default: 100 with si570, the frequency of the Si570 after power-up; 156.25 with 8a34001)
#
# The results of a complete build go to <project>/results: the device image, the reports (timing summary,
# utilisation, methodology, DRC), the constraints that do not apply (invalid_constraints.xdc), constraint_check.txt
# and build_info.txt with the step, the reference clock with its frequency and pins, the Vivado version, the commits
# of the repository and of its submodules, the result of the constraint integrity check and the timing summary. The
# step rtl writes invalid_constraints.xdc and build_info.txt of the elaborated design.
#
# Constraint integrity (tcl/build_checks.tcl): the build stops when a constraint did not apply in synthesis or in
# implementation (an object query that matched nothing, for example a clock that does not exist yet) or when the
# methodology checks TIMING-6, TIMING-7 or TIMING-47 report a clock pair without its constraint; after synthesis
# before the implementation starts, after the implementation once the results are written. A design that misses
# timing is reported (TIMING NOT MET in the console and in build_info.txt) but does not stop the build.
#
# The environment variable OFB_VIVADO_OUT selects another project directory. On Windows the device image step
# compiles the platform loader firmware in a deep directory below the project; with a project path of more than
# about 40 characters the compiler exceeds the Windows path length limit and write_device_image fails ("opening
# dependency file ... No such file or directory"). Use a short path there, for example OFB_VIVADO_OUT=C:/ofb.
#
# Documentation: hdl/ofb_vck190/docs/architecture.md
#---------------------------------------------------------------------------------------------------

set root [file normalize [file join [file dirname [info script]] .. .. ..]]
source [file join $root hdl ofb_vck190 tcl build_checks.tcl]
if {[info exists env(OFB_VIVADO_OUT)] && $env(OFB_VIVADO_OUT) ne ""} {
    set out [file normalize $env(OFB_VIVADO_OUT)]
} else {
    set out [file join $root vivado_out ofb_vck190]
}
if {$tcl_platform(platform) eq "windows" && [string length $out] > 40} {
    puts "WARNING: project path $out has more than 40 characters, write_device_image may fail on Windows (path\
        length limit); set OFB_VIVADO_OUT to a short directory, for example C:/ofb"
}
# Arguments: the step, the source and the frequency of the reference clock, plain words in any order
set step all
set refclk si570
set refclk_mhz ""
foreach arg $argv {
    if {$arg in {project rtl synth impl all}} {
        set step $arg
    } elseif {$arg in {si570 8a34001}} {
        set refclk $arg
    } elseif {$arg in {100 156.25}} {
        set refclk_mhz $arg
    } else {
        error "unknown argument $arg (step: project, rtl, synth, impl, all; reference clock: si570, 8a34001;\
            frequency: 100, 156.25)"
    }
}
if {$refclk_mhz eq ""} {
    set refclk_mhz [dict get {si570 100 8a34001 156.25} $refclk]
}
puts "Step $step, reference clock $refclk at $refclk_mhz MHz"
if {![string match 2025.2* [version -short]]} {
    puts "WARNING: the build is made for Vivado 2025.2, this is [version -short]"
}
set results [file join $out results]

create_project -force ofb_vck190 $out -part xcvc1902-vsva2197-2MP-e-S
set_property target_language VHDL [current_project]

# Open Logic: areas base, axi, intf and ft into the library olo, in the order of compile_order.txt (one add_files
# call for all files)
set fh [open [file join $root open-logic compile_order.txt] r]
set olo_files {}
foreach line [split [read $fh] "\n"] {
    set rel [string trim $line]
    if {$rel eq ""} { continue }
    set area [lindex [split $rel /] 1]
    if {$area in {base axi intf ft}} { lappend olo_files [file join $root open-logic $rel] }
}
close $fh
set f [add_files -norecurse $olo_files]
set_property library olo $f
set_property file_type {VHDL 2008} $f

# OpenFibre: the modules of component_list.txt, PA-1 and the board top
set fh [open [file join $root component_list.txt] r]
set modules {}
foreach line [split [read $fh] "\n"] {
    set m [string trim $line]
    if {$m ne "" && [string index $m 0] ne "#"} { lappend modules $m }
}
close $fh
lappend modules hdl/ofb_pa_gty hdl/ofb_vck190
set ofb_files {}
foreach m $modules {
    set ofb_files [concat $ofb_files [glob -nocomplain [file join $root $m src *.vhd]]]
}
set f [add_files -norecurse $ofb_files]
set_property file_type {VHDL 2008} $f

# Transceiver wizard instance at the frequency of the reference clock
source [file join $root hdl ofb_pa_gty tcl ofb_gtw.tcl]
ofb_gtw_create ofb_gtw $refclk_mhz
generate_target all [get_ips ofb_gtw]

# Control, interfaces and processing system (CIPS): every Versal design needs it, the platform management
# controller configures the device (JTAG boot). Two clocks of the PMC clock generator for the programmable logic:
# pl0 100 MHz (MIB, free-running clock of the transceivers, power-on reset), pl1 150 MHz (user side of the core), and
# the fabric reset pl0_resetn. The master port M_AXI_FPD (32 bits, clock pl0) reaches the MIB at 0xA400_0000 through
# a SmartConnect, which also takes the LED poller of the top level (S_AXI_POLL, MIB at 0x000) and converts both to
# AXI4-Lite (M_AXI_MIB, the top level uses the address bits 11:0).
create_bd_design ofb_cips
set cips [create_bd_cell -type ip -vlnv [lindex [lsort [get_ipdefs -filter {NAME == versal_cips}]] end] cips]
set_property -dict [list \
    CONFIG.CLOCK_MODE {Custom} \
    CONFIG.PS_PL_CONNECTIVITY_MODE {Custom} \
    CONFIG.PS_PMC_CONFIG { \
        CLOCK_MODE {Custom} \
        DESIGN_MODE {1} \
        PMC_CRP_PL0_REF_CTRL_FREQMHZ {100} \
        PMC_CRP_PL1_REF_CTRL_FREQMHZ {150} \
        PS_M_AXI_FPD_DATA_WIDTH {32} \
        PS_NUM_FABRIC_RESETS {1} \
        PS_PL_CONNECTIVITY_MODE {Custom} \
        PS_USE_M_AXI_FPD {1} \
        PS_USE_PMCPL_CLK0 {1} \
        PS_USE_PMCPL_CLK1 {1} \
    } \
] $cips
# Frequency of pl0 as generated by the PMC clock generator (99.999 MHz), for the external AXI ports
set pl0_hz [get_property CONFIG.FREQ_HZ [get_bd_pins cips/pl0_ref_clk]]
create_bd_cell -type ip -vlnv [lindex [lsort [get_ipdefs -filter {NAME == proc_sys_reset}]] end] rst_pl0
set sc [create_bd_cell -type ip -vlnv [lindex [lsort [get_ipdefs -filter {NAME == smartconnect}]] end] mib_axi]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $sc
create_bd_port -dir O -type clk pl0_clk
create_bd_port -dir O -type clk pl1_clk
create_bd_port -dir O -type rst pl0_resetn
foreach {name mode} {M_AXI_MIB Master S_AXI_POLL Slave} {
    set port [create_bd_intf_port -mode $mode -vlnv xilinx.com:interface:aximm_rtl:1.0 $name]
    set_property -dict [list CONFIG.PROTOCOL AXI4LITE CONFIG.DATA_WIDTH 32 CONFIG.ADDR_WIDTH 12 \
        CONFIG.FREQ_HZ $pl0_hz] $port
}
set_property -dict [list CONFIG.FREQ_HZ $pl0_hz CONFIG.ASSOCIATED_BUSIF M_AXI_MIB:S_AXI_POLL] [get_bd_ports pl0_clk]
connect_bd_net [get_bd_pins cips/pl0_ref_clk] [get_bd_ports pl0_clk] [get_bd_pins cips/m_axi_fpd_aclk] \
    [get_bd_pins rst_pl0/slowest_sync_clk] [get_bd_pins mib_axi/aclk]
connect_bd_net [get_bd_pins cips/pl1_ref_clk] [get_bd_ports pl1_clk]
connect_bd_net [get_bd_pins cips/pl0_resetn] [get_bd_ports pl0_resetn] [get_bd_pins rst_pl0/ext_reset_in]
connect_bd_net [get_bd_pins rst_pl0/interconnect_aresetn] [get_bd_pins mib_axi/aresetn]
connect_bd_intf_net [get_bd_intf_pins cips/M_AXI_FPD] [get_bd_intf_pins mib_axi/S00_AXI]
connect_bd_intf_net [get_bd_intf_ports S_AXI_POLL] [get_bd_intf_pins mib_axi/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins mib_axi/M00_AXI] [get_bd_intf_ports M_AXI_MIB]
assign_bd_address -offset 0xA4000000 -range 0x00001000 -target_address_space [get_bd_addr_spaces cips/M_AXI_FPD] \
    [get_bd_addr_segs M_AXI_MIB/Reg]
assign_bd_address -offset 0x00000000 -range 0x00001000 -target_address_space [get_bd_addr_spaces S_AXI_POLL] \
    [get_bd_addr_segs M_AXI_MIB/Reg]
validate_bd_design
save_bd_design
set bd [get_files ofb_cips.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
close_bd_design [current_bd_design]
set_property generic {IncludeCips_g=true} [current_fileset]

# Constraints. First the clock constraint of the reference clock at the selected frequency, written into the project
# directory (processing order EARLY): the clock pair constraints of ofb_vck190.xdc find the lane clock as the clock of
# the transceiver output clock buffer, and that clock exists only once the reference clock it is derived from is
# defined. Read later, the lane clock is empty and the clock pair constraints are lost or, with one clock missing,
# cover a whole clock domain. Then the board constraints, the pins of the selected reference clock and the Open Logic
# crossings (implementation only, processing order LATE). The scoped constraints of olo_intf_sync are not loaded:
# they constrain device pins, and the design uses olo_intf_sync for internal asynchronous signals only (their
# crossings are constrained in ofb_vck190.xdc).
set refclk_xdc [file join $out ofb_vck190_refclk_clock.xdc]
set fh [open $refclk_xdc w]
puts $fh "# Written by tcl/build.tcl: transceiver reference clock $refclk at $refclk_mhz MHz"
puts $fh "create_clock -period [format %.3f [expr {1000.0 / $refclk_mhz}]] -name gt_refclk \[get_ports GtRefClk_P\]"
close $fh
add_files -fileset constrs_1 -norecurse $refclk_xdc
set_property PROCESSING_ORDER EARLY [get_files $refclk_xdc]
add_files -fileset constrs_1 -norecurse [file join $root hdl ofb_vck190 constr ofb_vck190.xdc]
add_files -fileset constrs_1 -norecurse [file join $root hdl ofb_vck190 constr ofb_vck190_refclk_${refclk}.xdc]
source [file join $root open-logic src base tcl olo_base_constraints_amd.tcl]

set_property top ofb_vck190_top [current_fileset]
update_compile_order -fileset sources_1

# Implementation: placement and routing explore several directives, physical optimization also after routing
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# build_info.txt of the open design: the step, the reference clock with its frequency, the period of its clock and
# the pins of its ports in the design, the Vivado version and the commits of the repository and of its submodules
proc write_build_info {path} {
    global step refclk refclk_mhz root
    set fh [open $path w]
    puts $fh "ofb_vck190, step $step, [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "Vivado [version -short], part [get_property PART [current_project]]"
    set pins {}
    foreach port {GtRefClk_P GtRefClk_N} { lappend pins "$port [get_property PACKAGE_PIN [get_ports $port]]" }
    set period [get_property -quiet PERIOD [get_clocks -quiet gt_refclk]]
    puts $fh "reference clock $refclk at $refclk_mhz MHz, gt_refclk period $period ns: [join $pins {, }]"
    if {[catch {exec git -C $root log -1 --format=%H} commit]} { set commit "unknown (git not available)" }
    puts $fh "repository $commit"
    if {![catch {exec git -C $root submodule status} status]} {
        puts $fh "submodules:
$status"
    }
    close $fh
}

if {$step eq "project"} { return }
if {$step eq "rtl"} {
    synth_design -rtl -name rtl_1
    # Constraints that do not apply to the elaborated design: a dropped constraint shows up before a synthesis
    file mkdir $results
    write_xdc -force -constraints invalid [file join $results invalid_constraints.xdc]
    write_build_info [file join $results build_info.txt]
    return
}

# The runs of launch_runs are Vivado processes of their own that start at the same time (the IP of the transceiver
# wizard and of the block design out of context, then synth_1). On a fresh installation of Vivado they create the user
# directory of the Tcl Store together, and one of them can fail at start-up with Common 17-1257 ("Failed to create
# directory") and "tclapp::load_apps failed" (AMD AR 63253). The runs inherit the environment of this process: with
# XILINX_LOCAL_USER_DATA=no, the workaround of the answer record, their Tcl Store stays out of that directory.
set ::env(XILINX_LOCAL_USER_DATA) no
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed" }
# Constraint integrity of the synthesis: stop before the implementation when a constraint did not apply
set synth_check [ofb_build_checks::log_check [file join [get_property DIRECTORY [get_runs synth_1]] runme.log]]
if {[ofb_build_checks::integrity_failed $synth_check "" {}]} {
    file mkdir $results
    ofb_build_checks::write_report [file join $results constraint_check.txt] $synth_check "" {} ""
    error "CONSTRAINT INTEGRITY FAILED in synthesis: [llength [dict get $synth_check violations]] constraint(s) did\
        not apply, see [file join $results constraint_check.txt]"
}
if {$step eq "synth"} { return }

if {$step eq "impl"} {
    launch_runs impl_1 -jobs 8
} else {
    launch_runs impl_1 -to_step write_device_image -jobs 8
}
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed" }

# Results: reports of the implemented design, the device image and what was built
file mkdir $results
open_run impl_1
report_utilization -file [file join $results utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $results utilization_hierarchical.rpt]
report_timing_summary -file [file join $results timing_summary.rpt]
report_methodology -file [file join $results methodology.rpt]
report_drc -file [file join $results drc.rpt]
# Constraints that do not apply to the implemented design (expected: none, the file holds only its header)
write_xdc -force -constraints invalid [file join $results invalid_constraints.xdc]
foreach pdi [glob -nocomplain [file join [get_property DIRECTORY [get_runs impl_1]] *.pdi]] {
    file copy -force $pdi $results
}
# Constraint integrity of the implementation and the timing summary, into constraint_check.txt and build_info.txt
set impl_check [ofb_build_checks::log_check [file join [get_property DIRECTORY [get_runs impl_1]] runme.log]]
set methodology [ofb_build_checks::methodology_check [file join $results methodology.rpt]]
set timing [ofb_build_checks::timing_summary [file join $results timing_summary.rpt]]
set summary [ofb_build_checks::summary $synth_check $impl_check $methodology $timing]
ofb_build_checks::write_report [file join $results constraint_check.txt] $synth_check $impl_check $methodology $timing
write_build_info [file join $results build_info.txt]
set fh [open [file join $results build_info.txt] a]
foreach line $summary { puts $fh $line }
close $fh
puts "Results in $results (reference clock $refclk at $refclk_mhz MHz)"
puts [string repeat = 100]
foreach line $summary { puts $line }
puts [string repeat = 100]
if {[ofb_build_checks::integrity_failed $synth_check $impl_check $methodology]} {
    error "CONSTRAINT INTEGRITY FAILED in implementation, see [file join $results constraint_check.txt]"
}
