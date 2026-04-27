# XSIM testbench for clean serialized secure memory implementation.
# Usage from repo root:
#   vivado -mode batch -source tb/run_xsim_clean_serial_tb.tcl

set ROOT_DIR [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set RTL_DIR  [file join $ROOT_DIR rtl]
set TB_DIR   [file join $ROOT_DIR tb]
set AES_DIR  [file join $RTL_DIR aes]

proc add_sv {files} {
  foreach f $files {
    if {![file exists $f]} { puts "ERROR: missing source $f"; exit 1 }
    read_verilog -sv $f
  }
}

proc add_v {files} {
  foreach f $files {
    if {![file exists $f]} { puts "ERROR: missing source $f"; exit 1 }
    read_verilog $f
  }
}

add_sv [list \
  $RTL_DIR/packages/metadata_pkg.sv \
  $RTL_DIR/packages/cf_math_pkg.sv \
  $RTL_DIR/common/lzc.sv \
  $RTL_DIR/topology/securememory_topology_clean.sv \
  $RTL_DIR/metadata_cache/metadata_cache.sv \
  $RTL_DIR/metadata_cache/metadata_counter_allocator.sv \
  $RTL_DIR/metadata_cache/metadata_controller_serial.sv \
  $RTL_DIR/memory-encryption-unit/aes_ctr_nx128.sv \
  $RTL_DIR/memory-encryption-unit/meu_ctr_datapath.sv \
  $RTL_DIR/integritychecker/bmt_hash_compare.sv \
  $RTL_DIR/integritychecker/integritychecker_bmt.sv \
  $RTL_DIR/memory-controller/secure_memory_controller_serial_bmt.sv \
  $TB_DIR/tb_metadata_counter_allocator.sv \
  $TB_DIR/tb_secure_memory_serial_bmt.sv \
]

add_v [list \
  $AES_DIR/aes_core.v \
  $AES_DIR/aes_key_mem.v \
  $AES_DIR/aes_encipher_block.v \
  $AES_DIR/aes_decipher_block.v \
  $AES_DIR/aes_sbox.v \
  $AES_DIR/aes_inv_sbox.v \
]

# Run the small unit test first.
synth_design -rtl -top tb_metadata_counter_allocator
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

# Then elaborate/run the integration test.
synth_design -rtl -top tb_secure_memory_serial_bmt
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
