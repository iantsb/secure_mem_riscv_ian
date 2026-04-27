# Run synthesis for TileLink-facing secure memory controller wrapper.
# Usage:
#   vivado -mode batch -source tcl/run_synth_fixed_encryption_tilelink.tcl
# Optional:
#   vivado -mode batch -source tcl/run_synth_fixed_encryption_tilelink.tcl -tclargs /path/to/project.xpr

set script_dir [file dirname [file normalize [info script]]]
set default_root [file normalize [file join $script_dir ..]]
set default_xpr  [file join $default_root vivado_projects fixed_encryption_tilelink fixed_encryption_tilelink.xpr]
set XPR_PATH $default_xpr
if {$argc >= 1} { set XPR_PATH [file normalize [lindex $argv 0]] }

if {![file exists $XPR_PATH]} {
  puts "ERROR: project not found: $XPR_PATH"
  puts "Run create_fixed_encryption_tilelink.tcl first, or pass the .xpr path as -tclargs."
  exit 1
}





open_project $XPR_PATH
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $status"

if {[string match -nocase "*failed*" $status]} {
  puts "ERROR: synthesis failed. See runme.log under *.runs/synth_1/."
  exit 1
}

open_run synth_1 -name synth_1

set proj_dir [get_property DIRECTORY [current_project]]
set rpt_dir  [file join $proj_dir reports]
file mkdir $rpt_dir

report_utilization -file [file join $rpt_dir utilization_synth.rpt]
report_timing_summary -file [file join $rpt_dir timing_synth.rpt]
#report_hierarchy -file [file join $rpt_dir hierarchy_synth.rpt]
puts "Synthesis complete. Reports written under: [get_property DIRECTORY [current_run]]"
