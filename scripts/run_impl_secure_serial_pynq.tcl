# Run synthesis + implementation and write timing/utilization reports.
#
# Usage:
#   vivado -mode batch -source tcl/run_impl_secure_serial_pynq.tcl
#
# Optional:
#   vivado -mode batch -source tcl/run_impl_secure_serial_pynq.tcl \
#     -tclargs /path/to/project.xpr

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]

set default_xpr [file normalize [file join $root_dir vivado_projects fixed_encryption_clean fixed_encryption_clean.xpr]]
set xpr_path $default_xpr

if {$argc >= 1} {
    set xpr_path [file normalize [lindex $argv 0]]
}

if {![file exists $xpr_path]} {
    puts "ERROR: project not found:"
    puts "  $xpr_path"
    exit 1
}

open_project $xpr_path
update_compile_order -fileset sources_1

reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"

if {[string match -nocase "*failed*" $synth_status]} {
    puts "ERROR: synthesis failed."
    exit 1
}

launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"

if {[string match -nocase "*failed*" $impl_status]} {
    puts "ERROR: implementation failed."
    exit 1
}

open_run impl_1

set proj_dir [get_property DIRECTORY [current_project]]
set rpt_dir  [file normalize [file join $proj_dir reports]]
file mkdir $rpt_dir

report_timing_summary -file [file join $rpt_dir timing_impl_summary.rpt]
report_timing         -sort_by group -max_paths 20 -file [file join $rpt_dir timing_impl_paths.rpt]
report_utilization    -file [file join $rpt_dir utilization_impl.rpt]
report_power          -file [file join $rpt_dir power_impl.rpt]

puts "Implementation complete."
puts "Reports written under:"
puts "  $rpt_dir"

close_project
exit 0