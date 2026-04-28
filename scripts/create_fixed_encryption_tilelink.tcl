

set script_dir [file dirname [file normalize [info script]]]
set default_root [file normalize [file join $script_dir ..]]
set ROOT_DIR $default_root
set FPGA_PART xc7z020clg400-1

if {$argc >= 1} { set ROOT_DIR [file normalize [lindex $argv 0]] }
if {$argc >= 2} { set FPGA_PART [lindex $argv 1] }

set PROJ_DIR [file join $ROOT_DIR vivado_projects fixed_encryption_tilelink]
set PROJ_NAME fixed_encryption_tilelink
set RTL_DIR  [file join $ROOT_DIR rtl]
set AES_DIR  [file join $RTL_DIR aes]

file mkdir $PROJ_DIR
create_project $PROJ_NAME $PROJ_DIR -part $FPGA_PART -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

proc add_sv_required {path} {
  if {![file exists $path]} {
    puts "ERROR: required source missing: $path"
    exit 1
  }
  add_files -fileset sources_1 $path
  set_property file_type SystemVerilog [get_files $path]
}

proc add_v_required {path} {
  if {![file exists $path]} {
    puts "ERROR: required source missing: $path"
    exit 1
  }
  add_files -fileset sources_1 $path
}

proc add_sv_optional {path} {
  if {[file exists $path]} {
    add_files -fileset sources_1 $path
    set_property file_type SystemVerilog [get_files $path]
  } else {
    puts "INFO: optional source not found, skipping: $path"
  }
}

# Packages first.
add_sv_required [file join $RTL_DIR packages config_pkg.sv]
add_sv_required [file join $RTL_DIR packages riscv_pkg.sv]
add_sv_required [file join $RTL_DIR packages tilelink_pkg.sv]
add_sv_optional [file join $RTL_DIR packages metadata_pkg.sv]
add_sv_optional [file join $RTL_DIR packages cf_math_pkg.sv]
add_sv_required [file join $RTL_DIR packages build_config_pkg.sv]

add_sv_optional [file join $RTL_DIR common cf_math_pkg.sv]
add_sv_optional [file join $RTL_DIR common lzc.sv]
add_sv_required [file join $RTL_DIR common csr_regfile.sv]
add_sv_optional [file join $RTL_DIR common fp_arb.sv]

add_sv_required [file join $RTL_DIR epmp epmp_entry.sv]
add_sv_required [file join $RTL_DIR epmp epmp.sv]

add_sv_optional [file join $RTL_DIR tilelink ztl_assembler.sv]
add_sv_optional [file join $RTL_DIR tilelink ztl_fragmenter.sv]
add_sv_required [file join $RTL_DIR tilelink ztl_passthrough_width_adapter.sv]
add_sv_optional [file join $RTL_DIR tilelink ztl_xbar.sv]
add_sv_optional [file join $RTL_DIR tilelink ztl_ram.sv]
add_sv_optional [file join $RTL_DIR tilelink tlfrontend.sv]
add_sv_optional [file join $RTL_DIR tilelink tlbuffer_a.sv]
add_sv_optional [file join $RTL_DIR tilelink tlbuffer_d.sv]
add_sv_optional [file join $RTL_DIR tilelink tldispatcher_a.sv]
add_sv_optional [file join $RTL_DIR tilelink tldispatcher_d.sv]

add_sv_required [file join $RTL_DIR memory-controller secure_memory_controller.sv]
add_sv_optional [file join $RTL_DIR memory-controller memory_controller.sv]
add_sv_optional [file join $RTL_DIR memory-controller memory_bus.sv]

add_sv_optional [file join $RTL_DIR topology securememory_topology.sv]
add_sv_optional [file join $RTL_DIR topology securememory_topology_clean.sv]
add_sv_optional [file join $RTL_DIR metadata_cache metadata_cache.sv]
add_sv_optional [file join $RTL_DIR metadata_cache metadata_controller_v3.sv]
add_sv_optional [file join $RTL_DIR metadata_cache metadata_controller_serial.sv]
add_sv_optional [file join $RTL_DIR memory-encryption-unit memory_encryption_unit.sv]
add_sv_optional [file join $RTL_DIR memory-encryption-unit aes_ctr_nx128.sv]
add_sv_optional [file join $RTL_DIR memory-encryption-unit meu_ctr_datapath.sv]
add_sv_optional [file join $RTL_DIR integritychecker integritychecker.sv]
add_sv_optional [file join $RTL_DIR integritychecker integritychecker_bmt.sv]
add_sv_optional [file join $RTL_DIR integritychecker bmt_hash_compare.sv]
add_sv_optional [file join $RTL_DIR memory-controller secure_memory_controller_serial_bmt.sv]
add_sv_optional [file join $RTL_DIR memory-controller sm_addr_mapper.sv]

add_v_required [file join $AES_DIR aes_core.v]
add_v_required [file join $AES_DIR aes_key_mem.v]
add_v_required [file join $AES_DIR aes_encipher_block.v]
add_v_required [file join $AES_DIR aes_decipher_block.v]
add_v_required [file join $AES_DIR aes_sbox.v]
add_v_required [file join $AES_DIR aes_inv_sbox.v]

add_sv_required [file join $RTL_DIR top MemoryControllerWrapperTL.sv]

update_compile_order -fileset sources_1
set_property top MemoryControllerWrapperTL [current_fileset]

close_project
puts "Created project: [file join $PROJ_DIR $PROJ_NAME.xpr]"
