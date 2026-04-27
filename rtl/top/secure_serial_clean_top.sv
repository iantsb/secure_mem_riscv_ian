`timescale 1ns/1ps

// Vivado synthesis shell for the clean serialized secure-memory datapath.
// This top intentionally avoids TileLink/RISC-V package dependencies.
// It exposes a simple line-based request/response interface plus separate
// protected-data-memory and metadata-memory interfaces.
module secure_serial_clean_top #(
  parameter int PLEN           = 56,
  parameter int CACHELINE_BITS = 512,
  parameter int VERSION_W      = 64,
  parameter int TAG_W          = 128,
  parameter int MARY           = 8
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,

  // Line-based request from a future TileLink/front-end adapter.
  input  logic                      req_valid_i,
  output logic                      req_ready_o,
  input  logic                      req_write_i,
  input  logic [PLEN-1:0]           req_addr_i,
  input  logic [PLEN-1:0]           req_mask_i,
  input  logic [PLEN-1:0]           req_base_i,
  input  logic [CACHELINE_BITS-1:0] req_wdata_i,

  output logic                      rsp_valid_o,
  input  logic                      rsp_ready_i,
  output logic [CACHELINE_BITS-1:0] rsp_rdata_o,
  output logic                      rsp_corrupt_o,

  // Protected data memory port.
  output logic                      data_mem_req_valid_o,
  input  logic                      data_mem_req_ready_i,
  output logic                      data_mem_req_write_o,
  output logic [PLEN-1:0]           data_mem_req_addr_o,
  output logic [CACHELINE_BITS-1:0] data_mem_req_wdata_o,
  input  logic                      data_mem_rsp_valid_i,
  input  logic [CACHELINE_BITS-1:0] data_mem_rsp_data_i,
  input  logic                      data_mem_rsp_error_i,

  // Metadata backing memory port.
  output logic                      meta_mem_req_valid_o,
  input  logic                      meta_mem_req_ready_i,
  output logic                      meta_mem_req_write_o,
  output logic [PLEN-1:0]           meta_mem_req_addr_o,
  output logic [CACHELINE_BITS-1:0] meta_mem_req_wdata_o,
  input  logic                      meta_mem_rsp_valid_i,
  input  logic [CACHELINE_BITS-1:0] meta_mem_rsp_data_i,
  input  logic                      meta_mem_rsp_error_i
);

  secure_memory_controller_serial_bmt #(
    .PLEN           (PLEN),
    .CACHELINE_BITS (CACHELINE_BITS),
    .VERSION_W      (VERSION_W),
    .TAG_W          (TAG_W),
    .MARY           (MARY)
  ) u_secure_memory_controller_serial_bmt (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),

    .req_valid_i          (req_valid_i),
    .req_ready_o          (req_ready_o),
    .req_write_i          (req_write_i),
    .req_addr_i           (req_addr_i),
    .req_mask_i           (req_mask_i),
    .req_base_i           (req_base_i),
    .req_wdata_i          (req_wdata_i),

    .rsp_valid_o          (rsp_valid_o),
    .rsp_ready_i          (rsp_ready_i),
    .rsp_rdata_o          (rsp_rdata_o),
    .rsp_corrupt_o        (rsp_corrupt_o),

    .data_mem_req_valid_o (data_mem_req_valid_o),
    .data_mem_req_ready_i (data_mem_req_ready_i),
    .data_mem_req_write_o (data_mem_req_write_o),
    .data_mem_req_addr_o  (data_mem_req_addr_o),
    .data_mem_req_wdata_o (data_mem_req_wdata_o),
    .data_mem_rsp_valid_i (data_mem_rsp_valid_i),
    .data_mem_rsp_data_i  (data_mem_rsp_data_i),
    .data_mem_rsp_error_i (data_mem_rsp_error_i),

    .meta_mem_req_valid_o (meta_mem_req_valid_o),
    .meta_mem_req_ready_i (meta_mem_req_ready_i),
    .meta_mem_req_write_o (meta_mem_req_write_o),
    .meta_mem_req_addr_o  (meta_mem_req_addr_o),
    .meta_mem_req_wdata_o (meta_mem_req_wdata_o),
    .meta_mem_rsp_valid_i (meta_mem_rsp_valid_i),
    .meta_mem_rsp_data_i  (meta_mem_rsp_data_i),
    .meta_mem_rsp_error_i (meta_mem_rsp_error_i)
  );

endmodule
