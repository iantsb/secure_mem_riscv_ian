# Run clean serialized secure-memory simulations.
#
# Usage from repo root:
#   vivado -mode batch -source tcl/run_clean_serial_tb.tcl
#
# Optional:
#   vivado -mode batch -source tcl/run_clean_serial_tb.tcl \
#     -tclargs /absolute/path/to/fixed_encryption_clean.xpr

# Close any accidentally open project, including in-memory projects.
if {[llength [current_project -quiet]]} {
    close_project
}

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]

set default_xpr [file normalize [file join $root_dir vivado_projects fixed_encryption_clean fixed_encryption_clean.xpr]]
set xpr_path $default_xpr

if {$argc >= 1} {
    set xpr_path [file normalize [lindex $argv 0]]
}

puts "Opening project:"
puts "  $xpr_path"

if {![file exists $xpr_path]} {
    puts "ERROR: project not found:"
    puts "  $xpr_path"
    puts "Run create_fixed_encryption_clean_serial.tcl first."
    exit 1
}

open_project $xpr_path

puts "Current project:"
puts "  [current_project]"
puts "Project directory:"
puts "  [get_property DIRECTORY [current_project]]"

set project_dir [file normalize [get_property DIRECTORY [current_project]]]
set expected_dir [file dirname $xpr_path]

if {![string equal $project_dir $expected_dir]} {
    puts "WARNING: opened project directory does not match expected directory."
    puts "Expected:"
    puts "  $expected_dir"
    puts "Actual:"
    puts "  $project_dir"
}

# Testbench paths.
set tb_counter [file normalize [file join $root_dir tb tb_metadata_counter_allocator.sv]]
set tb_serial  [file normalize [file join $root_dir tb tb_secure_memory_serial_bmt.sv]]

if {![file exists $tb_counter]} {
    puts "ERROR: missing testbench:"
    puts "  $tb_counter"
    close_project
    exit 1
}

if {![file exists $tb_serial]} {
    puts "ERROR: missing testbench:"
    puts "  $tb_serial"
    close_project
    exit 1
}

# Add testbench files to sim_1 if not already present.
if {[llength [get_files -quiet $tb_counter]] == 0} {
    puts "Adding TB:"
    puts "  $tb_counter"
    add_files -fileset sim_1 $tb_counter
}

if {[llength [get_files -quiet $tb_serial]] == 0} {
    puts "Adding TB:"
    puts "  $tb_serial"
    add_files -fileset sim_1 $tb_serial
}

set_property file_type SystemVerilog [get_files $tb_counter]
set_property file_type SystemVerilog [get_files $tb_serial]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Save the project after modifying sim_1. Some Vivado flows require this before launch_simulation.
#save_project

# Remove stale behavioral sim state if it exists.
catch {reset_simulation -simset sim_1 -mode behavioral}

# --------------------------------------------------------------------
# Test 1: metadata counter allocator unit test
# --------------------------------------------------------------------
puts "============================================================"
puts "Running tb_metadata_counter_allocator"
puts "============================================================"

set_property top tb_metadata_counter_allocator [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

catch {reset_simulation -simset sim_1 -mode behavioral}

# --------------------------------------------------------------------
# Test 2: clean serialized secure-memory integration test
# --------------------------------------------------------------------
puts "============================================================"
puts "Running tb_secure_memory_serial_bmt"
puts "============================================================"

set_property top tb_secure_memory_serial_bmt [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

puts "============================================================"
puts "All clean serial simulations completed."
puts "============================================================"

close_project
exit 0