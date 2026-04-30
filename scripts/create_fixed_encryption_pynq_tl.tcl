set script_dir [file dirname [file normalize [info script]]]
set default_root [file normalize [file join $script_dir ..]]

set ROOT_DIR     $default_root
set PROJECT_NAME "fixed_encryption_pynq_tl"
set PROJECT_BASE [file normalize [file join $ROOT_DIR vivado_projects]]
set FPGA_PART xc7z020clg400-1
set TOP_MODULE   "secure_tl_pynq_top"

if {$argc >= 1} { set ROOT_DIR [file normalize [lindex $argv 0]] }
if {$argc >= 2} { set PROJECT_NAME [lindex $argv 1] }
if {$argc >= 3} { set PROJECT_BASE [file normalize [lindex $argv 2]] }
if {$argc >= 4} { set FPGA_PART [lindex $argv 3] }

set RTL_DIR [file join $ROOT_DIR rtl]
set AES_DIR [file join $RTL_DIR aes]
set PROJ_DIR [file join $PROJECT_BASE $PROJECT_NAME]

set sv_files [list]
set v_files  [list]

proc add_sv_required {path} {
    global sv_files
    set f [file normalize $path]
    if {![file exists $f]} {
        puts "ERROR: required SystemVerilog file not found: $f"
        exit 1
    }
    lappend sv_files $f
}

proc add_sv_optional {path} {
    global sv_files
    set f [file normalize $path]
    if {[file exists $f]} {
        lappend sv_files $f
    } else {
        puts "INFO: optional SystemVerilog file not found, skipping: $f"
    }
}

proc add_v_required {path} {
    global v_files
    set f [file normalize $path]
    if {![file exists $f]} {
        puts "ERROR: required Verilog file not found: $f"
        exit 1
    }
    lappend v_files $f
}

proc add_v_optional {path} {
    global v_files
    set f [file normalize $path]
    if {[file exists $f]} {
        lappend v_files $f
    } else {
        puts "INFO: optional Verilog file not found, skipping: $f"
    }
}

file mkdir $PROJECT_BASE
create_project $PROJECT_NAME $PROJ_DIR -part $FPGA_PART -force
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
add_sv_optional [file join $RTL_DIR metadata_cache metadata_counter_allocator.sv]

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
add_sv_required [file join $RTL_DIR top secure_tl_pynq_top.sv]


set XDC_FILE [file join $ROOT_DIR constraints secure_mem_pynq_impl.xdc]

if {![file exists $XDC_FILE]} {
    puts "ERROR: missing XDC file: $XDC_FILE"
    exit 1
}

add_files -fileset constrs_1 $XDC_FILE
set_property file_type XDC [get_files $XDC_FILE]
set_property IS_ENABLED true [get_files $XDC_FILE]
set_property USED_IN_SYNTHESIS true [get_files $XDC_FILE]
set_property USED_IN_IMPLEMENTATION true [get_files $XDC_FILE]

update_compile_order -fileset constrs_1

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
