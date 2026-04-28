`timescale 1ns/1ps

import metadata_pkg::*;

// Simple serial line-based secure memory controller.

module secure_memory_controller_serial_bmt #(
  parameter int PLEN           = 56,
  parameter int CACHELINE_BITS = 512,
  parameter int VERSION_W      = 64,
  parameter int TAG_W          = 128,
  parameter int MARY           = 8,
  parameter logic [255:0] ENC_KEY = {
    128'h2b7e151628aed2a6abf7158809cf4f3c,
    128'h00000000000000000000000000000000
  },
  parameter logic ENC_KEYLEN = 1'b0,
  parameter logic [255:0] HASH_KEY = {
    128'h603deb1015ca71be2b73aef0857d7781,
    128'h1f352c073b6108d72d9810a30914dff4
  },
  parameter logic HASH_KEYLEN = 1'b1
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,

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

  // Metadata backing memory port used by metadata_controller_serial.
  output logic                      meta_mem_req_valid_o,
  input  logic                      meta_mem_req_ready_i,
  output logic                      meta_mem_req_write_o,
  output logic [PLEN-1:0]           meta_mem_req_addr_o,
  output logic [CACHELINE_BITS-1:0] meta_mem_req_wdata_o,
  input  logic                      meta_mem_rsp_valid_i,
  input  logic [CACHELINE_BITS-1:0] meta_mem_rsp_data_i,
  input  logic                      meta_mem_rsp_error_i
);

  typedef enum logic [4:0] {
    S_IDLE,
    S_READ_DATA_REQ,
    S_READ_DATA_WAIT,
    S_READ_IC_START,
    S_READ_IC_WAIT,
    S_READ_DECRYPT_START,
    S_READ_DECRYPT_WAIT,
    S_WRITE_ALLOC_REQ,
    S_WRITE_ALLOC_WAIT,
    S_WRITE_ENCRYPT_START,
    S_WRITE_ENCRYPT_WAIT,
    S_WRITE_DATA_REQ,
    S_WRITE_DATA_WAIT,
    S_WRITE_IC_START,
    S_WRITE_IC_WAIT,
    S_RESPOND
  } smc_state_e;

  smc_state_e state_q, state_n;

  logic [PLEN-1:0]           addr_q, addr_n;
  logic [PLEN-1:0]           mask_q, mask_n;
  logic [PLEN-1:0]           base_q, base_n;
  logic [CACHELINE_BITS-1:0] data_q, data_n;
  logic [CACHELINE_BITS-1:0] cipher_q, cipher_n;
  logic [VERSION_W-1:0]      version_q, version_n;
  logic                      corrupt_q, corrupt_n;
  logic                      write_q, write_n;

  logic [PLEN-1:0] topo_version_addr;
  logic [PLEN-1:0] topo_tag_addr;
  logic [PLEN-1:0] topo_leaf_addr;
  logic [31:0]     unused_blocks, unused_leaves, unused_height;

  securememory_topology_clean #(
    .PLEN           (PLEN),
    .CACHELINE_BITS (CACHELINE_BITS),
    .MARY           (MARY)
  ) u_topology_for_alloc (
    .mask_i                 (mask_q),
    .base_i                 (base_q),
    .addr_i                 (addr_q),
    .level_i                (32'd0),
    .metadata_block_count_o (unused_blocks),
    .metadata_tag_addr_o    (topo_tag_addr),
    .metadata_version_addr_o(topo_version_addr),
    .merkletree_leaf_count_o(unused_leaves),
    .merkletree_height_o    (unused_height),
    .merkletree_leaf_addr_o (topo_leaf_addr)
  );

  function automatic logic [2:0] line_lane64(input logic [PLEN-1:0] addr);
    line_lane64 = addr[8:6];
  endfunction

  // Metadata controller request mux. The SMC only issues metadata requests during
  // version allocation. The IC issues all validation/tag requests.
  logic                      smc_meta_req_valid;
  logic                      smc_meta_req_ready;
  meta_op_e                  smc_meta_req_op;
  logic [PLEN-1:0]           smc_meta_req_addr;
  logic [2:0]                smc_meta_req_lane;
  logic [CACHELINE_BITS-1:0] smc_meta_req_wdata;
  logic [TAG_W-1:0]          smc_meta_req_tag;
  logic                      smc_meta_rsp_valid;
  logic                      smc_meta_rsp_ready;
  logic [CACHELINE_BITS-1:0] smc_meta_rsp_data;
  logic [VERSION_W-1:0]      smc_meta_rsp_version;
  logic [TAG_W-1:0]          smc_meta_rsp_tag;
  logic                      smc_meta_rsp_error;

  logic                      ic_meta_req_valid;
  logic                      ic_meta_req_ready;
  meta_op_e                  ic_meta_req_op;
  logic [PLEN-1:0]           ic_meta_req_addr;
  logic [2:0]                ic_meta_req_lane;
  logic [CACHELINE_BITS-1:0] ic_meta_req_wdata;
  logic [TAG_W-1:0]          ic_meta_req_tag;
  logic                      ic_meta_rsp_valid;
  logic                      ic_meta_rsp_ready;
  logic [CACHELINE_BITS-1:0] ic_meta_rsp_data;
  logic [VERSION_W-1:0]      ic_meta_rsp_version;
  logic [TAG_W-1:0]          ic_meta_rsp_tag;
  logic                      ic_meta_rsp_error;

  logic                      md_req_valid;
  logic                      md_req_ready;
  meta_op_e                  md_req_op;
  logic [PLEN-1:0]           md_req_addr;
  logic [2:0]                md_req_lane;
  logic [CACHELINE_BITS-1:0] md_req_wdata;
  logic [TAG_W-1:0]          md_req_tag;
  logic                      md_rsp_valid;
  logic                      md_rsp_ready;
  logic [CACHELINE_BITS-1:0] md_rsp_data;
  logic [VERSION_W-1:0]      md_rsp_version;
  logic [TAG_W-1:0]          md_rsp_tag;
  logic                      md_rsp_hit;
  logic                      md_rsp_error;

  assign md_req_valid = smc_meta_req_valid | ic_meta_req_valid;
  assign md_req_op    = smc_meta_req_valid ? smc_meta_req_op    : ic_meta_req_op;
  assign md_req_addr  = smc_meta_req_valid ? smc_meta_req_addr  : ic_meta_req_addr;
  assign md_req_lane  = smc_meta_req_valid ? smc_meta_req_lane  : ic_meta_req_lane;
  assign md_req_wdata = smc_meta_req_valid ? smc_meta_req_wdata : ic_meta_req_wdata;
  assign md_req_tag   = smc_meta_req_valid ? smc_meta_req_tag   : ic_meta_req_tag;

  assign smc_meta_req_ready = smc_meta_req_valid && md_req_ready;
  assign ic_meta_req_ready  = !smc_meta_req_valid && ic_meta_req_valid && md_req_ready;

  assign md_rsp_ready = smc_meta_rsp_ready | ic_meta_rsp_ready;

  assign smc_meta_rsp_valid   = md_rsp_valid && (state_q == S_WRITE_ALLOC_WAIT);
  assign smc_meta_rsp_data    = md_rsp_data;
  assign smc_meta_rsp_version = md_rsp_version;
  assign smc_meta_rsp_tag     = md_rsp_tag;
  assign smc_meta_rsp_error   = md_rsp_error;

  assign ic_meta_rsp_valid   = md_rsp_valid && (state_q != S_WRITE_ALLOC_WAIT);
  assign ic_meta_rsp_data    = md_rsp_data;
  assign ic_meta_rsp_version = md_rsp_version;
  assign ic_meta_rsp_tag     = md_rsp_tag;
  assign ic_meta_rsp_error   = md_rsp_error;

  metadata_controller_serial #(
    .PLEN           (PLEN),
    .CACHELINE_BITS (CACHELINE_BITS),
    .VERSION_W      (VERSION_W),
    .TAG_W          (TAG_W)
  ) u_metadata_controller (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .req_valid_i       (md_req_valid),
    .req_ready_o       (md_req_ready),
    .req_op_i          (md_req_op),
    .req_addr_i        (md_req_addr),
    .req_lane_i        (md_req_lane),
    .req_wdata_i       (md_req_wdata),
    .req_tag_i         (md_req_tag),
    .rsp_valid_o       (md_rsp_valid),
    .rsp_ready_i       (md_rsp_ready),
    .rsp_data_o        (md_rsp_data),
    .rsp_version_o     (md_rsp_version),
    .rsp_tag_o         (md_rsp_tag),
    .rsp_hit_o         (md_rsp_hit),
    .rsp_error_o       (md_rsp_error),
    .mem_req_valid_o   (meta_mem_req_valid_o),
    .mem_req_ready_i   (meta_mem_req_ready_i),
    .mem_req_write_o   (meta_mem_req_write_o),
    .mem_req_addr_o    (meta_mem_req_addr_o),
    .mem_req_wdata_o   (meta_mem_req_wdata_o),
    .mem_rsp_valid_i   (meta_mem_rsp_valid_i),
    .mem_rsp_data_i    (meta_mem_rsp_data_i),
    .mem_rsp_error_i   (meta_mem_rsp_error_i)
  );

  logic ic_start, ic_ready, ic_valid, ic_pass, ic_corrupt;
  logic [TAG_W-1:0] ic_new_tag;
  logic [VERSION_W-1:0] ic_leaf_version;

  integritychecker_bmt #(
    .PLEN           (PLEN),
    .CACHELINE_BITS (CACHELINE_BITS),
    .VERSION_W      (VERSION_W),
    .TAG_W          (TAG_W),
    .MARY           (MARY),
    .HASH_KEY       (HASH_KEY),
    .HASH_KEYLEN    (HASH_KEYLEN)
  ) u_integritychecker (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .start_i           (ic_start),
    .ready_o           (ic_ready),
    .valid_o           (ic_valid),
    .is_write_i        (write_q),
    .mask_i            (mask_q),
    .base_i            (base_q),
    .addr_i            (addr_q),
    .protected_data_i  (cipher_q),
    .write_version_i   (version_q),
    .pass_o            (ic_pass),
    .corrupt_o         (ic_corrupt),
    .new_tag_o         (ic_new_tag),
    .leaf_version_o    (ic_leaf_version),
    .meta_req_valid_o  (ic_meta_req_valid),
    .meta_req_ready_i  (ic_meta_req_ready),
    .meta_req_op_o     (ic_meta_req_op),
    .meta_req_addr_o   (ic_meta_req_addr),
    .meta_req_lane_o   (ic_meta_req_lane),
    .meta_req_wdata_o  (ic_meta_req_wdata),
    .meta_req_tag_o    (ic_meta_req_tag),
    .meta_rsp_valid_i  (ic_meta_rsp_valid),
    .meta_rsp_ready_o  (ic_meta_rsp_ready),
    .meta_rsp_data_i   (ic_meta_rsp_data),
    .meta_rsp_version_i(ic_meta_rsp_version),
    .meta_rsp_tag_i    (ic_meta_rsp_tag),
    .meta_rsp_error_i  (ic_meta_rsp_error)
  );

  logic meu_start, meu_ready, meu_valid;
  logic [CACHELINE_BITS-1:0] meu_data_out;

  meu_ctr_datapath #(
    .ADDR_W     (PLEN),
    .DATA_W     (CACHELINE_BITS),
    .VERSION_W  (VERSION_W),
    .AES_KEY    (ENC_KEY),
    .AES_KEYLEN (ENC_KEYLEN)
  ) u_meu_ctr (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .start_i  (meu_start),
    .ready_o  (meu_ready),
    .valid_o  (meu_valid),
    .addr_i   (addr_q),
    .version_i(version_q),
    .data_i   (data_q),
    .data_o   (meu_data_out)
  );

  assign rsp_valid_o   = (state_q == S_RESPOND);
  assign rsp_rdata_o   = corrupt_q ? '0 : data_q;
  assign rsp_corrupt_o = corrupt_q;
  assign req_ready_o   = (state_q == S_IDLE);

  always_comb begin
    state_n   = state_q;
    addr_n    = addr_q;
    mask_n    = mask_q;
    base_n    = base_q;
    data_n    = data_q;
    cipher_n  = cipher_q;
    version_n = version_q;
    corrupt_n = corrupt_q;
    write_n   = write_q;

    data_mem_req_valid_o = 1'b0;
    data_mem_req_write_o = 1'b0;
    data_mem_req_addr_o  = '0;
    data_mem_req_wdata_o = '0;

    smc_meta_req_valid = 1'b0;
    smc_meta_req_op    = META_ALLOC_VERSION;
    smc_meta_req_addr  = '0;
    smc_meta_req_lane  = '0;
    smc_meta_req_wdata = '0;
    smc_meta_req_tag   = '0;
    smc_meta_rsp_ready = 1'b0;

    ic_start  = 1'b0;
    meu_start = 1'b0;

    unique case (state_q)
      S_IDLE: begin
        if (req_valid_i) begin
          addr_n    = req_addr_i;
          mask_n    = req_mask_i;
          base_n    = req_base_i;
          data_n    = req_wdata_i;
          cipher_n  = '0;
          version_n = '0;
          corrupt_n = 1'b0;
          write_n   = req_write_i;
          state_n   = req_write_i ? S_WRITE_ALLOC_REQ : S_READ_DATA_REQ;
        end
      end

      S_READ_DATA_REQ: begin
        data_mem_req_valid_o = 1'b1;
        data_mem_req_write_o = 1'b0;
        data_mem_req_addr_o  = addr_q;
        if (data_mem_req_ready_i) begin
          state_n = S_READ_DATA_WAIT;
        end
      end

      S_READ_DATA_WAIT: begin
        if (data_mem_rsp_valid_i) begin
          cipher_n  = data_mem_rsp_data_i;
          data_n    = data_mem_rsp_data_i;
          corrupt_n = data_mem_rsp_error_i;
          state_n   = data_mem_rsp_error_i ? S_RESPOND : S_READ_IC_START;
        end
      end

      S_READ_IC_START: begin
        if (ic_ready) begin
          ic_start = 1'b1;
          state_n  = S_READ_IC_WAIT;
        end
      end

      S_READ_IC_WAIT: begin
        if (ic_valid) begin
          corrupt_n = !ic_pass;
          version_n = ic_leaf_version;
          state_n   = ic_pass ? S_READ_DECRYPT_START : S_RESPOND;
        end
      end

      S_READ_DECRYPT_START: begin
        if (meu_ready) begin
          data_n    = cipher_q;
          meu_start = 1'b1;
          state_n   = S_READ_DECRYPT_WAIT;
        end
      end

      S_READ_DECRYPT_WAIT: begin
        if (meu_valid) begin
          data_n  = meu_data_out;
          state_n = S_RESPOND;
        end
      end

      S_WRITE_ALLOC_REQ: begin
        smc_meta_req_valid = 1'b1;
        smc_meta_req_op    = META_ALLOC_VERSION;
        smc_meta_req_addr  = topo_version_addr;
        smc_meta_req_lane  = line_lane64(addr_q);
        if (smc_meta_req_ready) begin
          state_n = S_WRITE_ALLOC_WAIT;
        end
      end

      S_WRITE_ALLOC_WAIT: begin
        smc_meta_rsp_ready = 1'b1;
        if (smc_meta_rsp_valid) begin
          version_n = smc_meta_rsp_version;
          corrupt_n = smc_meta_rsp_error;
          state_n   = smc_meta_rsp_error ? S_RESPOND : S_WRITE_ENCRYPT_START;
        end
      end

      S_WRITE_ENCRYPT_START: begin
        if (meu_ready) begin
          meu_start = 1'b1;
          state_n   = S_WRITE_ENCRYPT_WAIT;
        end
      end

      S_WRITE_ENCRYPT_WAIT: begin
        if (meu_valid) begin
          cipher_n = meu_data_out;
          data_n   = meu_data_out;
          state_n  = S_WRITE_DATA_REQ;
        end
      end

      S_WRITE_DATA_REQ: begin
        data_mem_req_valid_o = 1'b1;
        data_mem_req_write_o = 1'b1;
        data_mem_req_addr_o  = addr_q;
        data_mem_req_wdata_o = cipher_q;
        if (data_mem_req_ready_i) begin
          state_n = S_WRITE_DATA_WAIT;
        end
      end

      S_WRITE_DATA_WAIT: begin
        if (data_mem_rsp_valid_i) begin
          corrupt_n = data_mem_rsp_error_i;
          state_n   = data_mem_rsp_error_i ? S_RESPOND : S_WRITE_IC_START;
        end
      end

      S_WRITE_IC_START: begin
        if (ic_ready) begin
          data_n    = cipher_q;
          ic_start  = 1'b1;
          state_n   = S_WRITE_IC_WAIT;
        end
      end

      S_WRITE_IC_WAIT: begin
        if (ic_valid) begin
          corrupt_n = !ic_pass;
          state_n   = S_RESPOND;
        end
      end

      S_RESPOND: begin
        if (rsp_ready_i) begin
          state_n = S_IDLE;
        end
      end

      default: begin
        state_n = S_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= S_IDLE;
      addr_q    <= '0;
      mask_q    <= '0;
      base_q    <= '0;
      data_q    <= '0;
      cipher_q  <= '0;
      version_q <= '0;
      corrupt_q <= 1'b0;
      write_q   <= 1'b0;
    end else begin
      state_q   <= state_n;
      addr_q    <= addr_n;
      mask_q    <= mask_n;
      base_q    <= base_n;
      data_q    <= data_n;
      cipher_q  <= cipher_n;
      version_q <= version_n;
      corrupt_q <= corrupt_n;
      write_q   <= write_n;
    end
  end

endmodule
