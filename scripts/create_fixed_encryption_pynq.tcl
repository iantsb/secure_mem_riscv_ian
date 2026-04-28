

set script_dir [file dirname [file normalize [info script]]]
set default_root [file normalize [file join $script_dir ..]]

set ROOT_DIR     $default_root
set PROJECT_NAME "fixed_encryption_pynq"
set PROJECT_BASE [file normalize [file join $ROOT_DIR vivado_projects]]
set FPGA_PART xc7z020clg400-1
set TOP_MODULE   "secure_serial_pynq_top"

if {$argc >= 1} { set ROOT_DIR [file normalize [lindex $argv 0]] }
if {$argc >= 2} { set PROJECT_NAME [lindex $argv 1] }
if {$argc >= 3} { set PROJECT_BASE [file normalize [lindex $argv 2]] }
if {$argc >= 4} { set FPGA_PART [lindex $argv 3] }

set RTL_DIR [file join $ROOT_DIR rtl]
set AES_DIR [file join $RTL_DIR aes]
set PROJ_DIR [file join $PROJECT_BASE $PROJECT_NAME]

file mkdir $PROJECT_BASE
create_project $PROJECT_NAME $PROJ_DIR -part $FPGA_PART -force

# Packages first.
set sv_files [list \
  [file join $RTL_DIR packages metadata_pkg.sv] \
  [file join $RTL_DIR packages cf_math_pkg.sv] \
  [file join $RTL_DIR common lzc.sv] \
  [file join $RTL_DIR topology securememory_topology_clean.sv] \
  [file join $RTL_DIR metadata_cache metadata_cache.sv] \
  [file join $RTL_DIR metadata_cache metadata_counter_allocator.sv] \
  [file join $RTL_DIR metadata_cache metadata_controller_serial.sv] \
  [file join $RTL_DIR memory-encryption-unit aes_ctr_nx128.sv] \
  [file join $RTL_DIR memory-encryption-unit meu_ctr_datapath.sv] \
  [file join $RTL_DIR integritychecker bmt_hash_compare.sv] \
  [file join $RTL_DIR integritychecker integritychecker_bmt.sv] \
  [file join $RTL_DIR memory-controller secure_memory_controller_serial_bmt.sv] \
  [file join $RTL_DIR top secure_serial_pynq_top.sv] \
]

set v_files [list \
  [file join $AES_DIR aes_core.v] \
  [file join $AES_DIR aes_key_mem.v] \
  [file join $AES_DIR aes_encipher_block.v] \
  [file join $AES_DIR aes_decipher_block.v] \
  [file join $AES_DIR aes_sbox.v] \
  [file join $AES_DIR aes_inv_sbox.v] \
]

add_files -fileset constrs_1 [file join $ROOT_DIR constraints secure_serial_pynq.xdc]

foreach f [concat $sv_files $v_files] {
  if {![file exists $f]} {
    puts "ERROR: required source file not found: $f"
    exit 1
  }
}

add_files -fileset sources_1 $sv_files
add_files -fileset sources_1 $v_files

foreach f $sv_files {
  set_property file_type SystemVerilog [get_files $f]
}

set_property top $TOP_MODULE [current_fileset]
update_compile_order -fileset sources_1

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]

puts "Created project: $PROJ_DIR/$PROJECT_NAME.xpr"
puts "Top module:      $TOP_MODULE"
puts "Part:            $FPGA_PART"
puts "AES directory:   $AES_DIR"
