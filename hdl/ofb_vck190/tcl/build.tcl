#---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
#---------------------------------------------------------------------------------------------------
# Builds the OpenFibre reference design for the AMD VCK190: project in vivado_out/ofb_vck190, transceiver
# wizard instance, Open Logic and OpenFibre sources, constraints, synthesis, implementation and device image.
#
# Usage (from the repository root):
#   vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl [-tclargs <step>]
#   <step>: project (create the project only), synth, impl, all (default: all, device image included)
#
# The environment variable OFB_VIVADO_OUT selects another project directory. On Windows the device image step
# compiles the platform loader firmware in a deep directory below the project; with a project path of more than
# about 40 characters the compiler exceeds the Windows path length limit and write_device_image fails ("opening
# dependency file ... No such file or directory"). Use a short path there, for example OFB_VIVADO_OUT=C:/ofb.
#
# Documentation: hdl/ofb_vck190/docs/architecture.md
#---------------------------------------------------------------------------------------------------

set root [file normalize [file join [file dirname [info script]] .. .. ..]]
if {[info exists env(OFB_VIVADO_OUT)] && $env(OFB_VIVADO_OUT) ne ""} {
    set out [file normalize $env(OFB_VIVADO_OUT)]
} else {
    set out [file join $root vivado_out ofb_vck190]
}
if {$tcl_platform(platform) eq "windows" && [string length $out] > 40} {
    puts "WARNING: project path $out has more than 40 characters, write_device_image may fail on Windows (path\
        length limit); set OFB_VIVADO_OUT to a short directory, for example C:/ofb"
}
set step [expr {[llength $argv] > 0 ? [lindex $argv 0] : "all"}]

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

# Transceiver wizard instance (156.25 MHz reference clock)
source [file join $root hdl ofb_pa_gty tcl ofb_gtw.tcl]
ofb_gtw_create ofb_gtw 156.25
generate_target all [get_ips ofb_gtw]

# Control, interfaces and processing system (CIPS): every Versal design needs it, the platform management
# controller configures the device (JTAG boot). Two clocks of the PMC clock generator for the programmable logic:
# pl0 100 MHz (MIB, free-running clock of the transceivers, power-on reset), pl1 150 MHz (user side of the core), and
# the fabric reset pl0_resetn; no other interface to the programmable logic.
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
        PS_NUM_FABRIC_RESETS {1} \
        PS_PL_CONNECTIVITY_MODE {Custom} \
        PS_USE_PMCPL_CLK0 {1} \
        PS_USE_PMCPL_CLK1 {1} \
    } \
] $cips
create_bd_port -dir O -type clk pl0_clk
create_bd_port -dir O -type clk pl1_clk
create_bd_port -dir O -type rst pl0_resetn
connect_bd_net [get_bd_pins cips/pl0_ref_clk] [get_bd_ports pl0_clk]
connect_bd_net [get_bd_pins cips/pl1_ref_clk] [get_bd_ports pl1_clk]
connect_bd_net [get_bd_pins cips/pl0_resetn] [get_bd_ports pl0_resetn]
validate_bd_design
save_bd_design
set bd [get_files ofb_cips.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
close_bd_design [current_bd_design]
set_property generic {IncludeCips_g=true} [current_fileset]

# Constraints: board, Open Logic crossings (implementation only). The scoped constraints of olo_intf_sync are not
# loaded: they constrain device pins, and the design uses olo_intf_sync for internal asynchronous signals only (their
# crossings are constrained in ofb_vck190.xdc).
add_files -fileset constrs_1 -norecurse [file join $root hdl ofb_vck190 constr ofb_vck190.xdc]
source [file join $root open-logic src base tcl olo_base_constraints_amd.tcl]

set_property top ofb_vck190_top [current_fileset]
update_compile_order -fileset sources_1

if {$step eq "project"} { return }

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed" }
if {$step eq "synth"} { return }

launch_runs impl_1 -to_step write_device_image -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed" }
open_run impl_1
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -file [file join $out timing_summary.rpt]
