
set script_dir [file dirname [file normalize [info script]]]
set default_root [file normalize [file join $script_dir ..]]
set default_xpr  [file join $default_root vivado_projects fixed_encryption_clean fixed_encryption_clean.xpr]

set XPR_PATH $default_xpr
if {$argc >= 1} { set XPR_PATH [file normalize [lindex $argv 0]] }

if {![file exists $XPR_PATH]} {
  puts "ERROR: project not found: $XPR_PATH"
  puts "Run create_fixed_encryption_clean_serial.tcl first, or pass the .xpr path as -tclargs."
  exit 1
}

open_project $XPR_PATH
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"

if {![string match "*Complete*" $synth_status]} {
  puts "ERROR: synthesis did not complete successfully."
  exit 1
}

open_run synth_1 -name synth_1

set rpt_dir [file join [get_property DIRECTORY [current_project]] reports]
file mkdir $rpt_dir

report_utilization -file [file join $rpt_dir post_synth_utilization.rpt] -hierarchical
report_timing_summary -file [file join $rpt_dir post_synth_timing_summary.rpt]
report_drc -file [file join $rpt_dir post_synth_drc.rpt]

puts "Reports written to: $rpt_dir"
