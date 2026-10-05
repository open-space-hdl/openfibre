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
# Documentation: hdl/ofb_vck190/docs/architecture.md
#---------------------------------------------------------------------------------------------------

set root [file normalize [file join [file dirname [info script]] .. .. ..]]
set out  [file join $root vivado_out ofb_vck190]
set step [expr {[llength $argv] > 0 ? [lindex $argv 0] : "all"}]

create_project -force ofb_vck190 $out -part xcvc1902-vsva2197-2MP-e-S
set_property target_language VHDL [current_project]

# Open Logic: areas base, axi, intf and ft into the library olo, in the order of compile_order.txt
set fh [open [file join $root open-logic compile_order.txt] r]
foreach line [split [read $fh] "\n"] {
    set rel [string trim $line]
    if {$rel eq ""} { continue }
    set area [lindex [split $rel /] 1]
    if {$area in {base axi intf ft}} {
        set f [add_files -norecurse [file join $root open-logic $rel]]
        set_property library olo $f
        set_property file_type {VHDL 2008} $f
    }
}
close $fh

# OpenFibre: the modules of component_list.txt, PA-1 and the board top
set fh [open [file join $root component_list.txt] r]
set modules {}
foreach line [split [read $fh] "\n"] {
    set m [string trim $line]
    if {$m ne "" && [string index $m 0] ne "#"} { lappend modules $m }
}
close $fh
lappend modules hdl/ofb_pa_gty hdl/ofb_vck190
foreach m $modules {
    foreach src [glob -nocomplain [file join $root $m src *.vhd]] {
        set f [add_files -norecurse $src]
        set_property file_type {VHDL 2008} $f
    }
}

# Transceiver wizard instance (156.25 MHz reference clock)
source [file join $root hdl ofb_pa_gty tcl ofb_gtw.tcl]
ofb_gtw_create ofb_gtw 156.25
generate_target all [get_ips ofb_gtw]

# Control, interfaces and processing system (CIPS): every Versal design needs it, the platform management
# controller configures the device. Default configuration (no interfaces to the programmable logic), JTAG boot.
create_bd_design ofb_cips
create_bd_cell -type ip -vlnv [lindex [lsort [get_ipdefs -filter {NAME == versal_cips}]] end] cips
validate_bd_design
save_bd_design
set bd [get_files ofb_cips.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
close_bd_design [current_bd_design]
set_property generic {IncludeCips_g=true} [current_fileset]

# Constraints: board, Open Logic crossings (implementation only)
add_files -fileset constrs_1 -norecurse [file join $root hdl ofb_vck190 constr ofb_vck190.xdc]
source [file join $root open-logic src base tcl olo_base_constraints_amd.tcl]
source [file join $root open-logic src intf tcl olo_intf_constraints_amd.tcl]

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
