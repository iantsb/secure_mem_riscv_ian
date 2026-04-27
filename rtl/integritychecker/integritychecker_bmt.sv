`timescale 1ns/1ps

import metadata_pkg::*;

// Serial Bonsai Merkle Tree integrity checker.
//
// The checker owns BMT validation and tag generation. It uses securememory_topology
// to derive version/counter and tag metadata addresses. The first implementation is
// intentionally serial: it fetches metadata, runs one AES-based hash compare, then
// advances to the next BMT level.
//
// Naming convention preserved from the original code/paper:
//   version == counter
//   tag     == integrity tag
module integritychecker_bmt #(
  parameter int PLEN           = 56,
  parameter int CACHELINE_BITS = 512,
  parameter int VERSION_W      = 64,
  parameter int TAG_W          = 128,
  parameter int MARY           = 8,
  parameter int MAX_LEVELS     = 8,
  parameter logic [255:0] HASH_KEY = {
    128'h603deb1015ca71be2b73aef0857d7781,
    128'h1f352c073b6108d72d9810a30914dff4
  },
  parameter logic HASH_KEYLEN = 1'b1
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,

  input  logic                      start_i,
  output logic                      ready_o,
  output logic                      valid_o,

  input  logic                      is_write_i,
  input  logic [PLEN-1:0]           mask_i,
  input  logic [PLEN-1:0]           base_i,
  input  logic [PLEN-1:0]           addr_i,
  input  logic [CACHELINE_BITS-1:0] protected_data_i,

  // For writes, the secure controller allocates the new version/counter first
  // and supplies it here. Reads fetch the version through metadata.
  input  logic [VERSION_W-1:0]      write_version_i,

  output logic                      pass_o,
  output logic                      corrupt_o,
  output logic [TAG_W-1:0]          new_tag_o,
  output logic [VERSION_W-1:0]      leaf_version_o,

  // Metadata request/response port.
  output logic                      meta_req_valid_o,
  input  logic                      meta_req_ready_i,
  output meta_op_e                  meta_req_op_o,
  output logic [PLEN-1:0]           meta_req_addr_o,
  output logic [2:0]                meta_req_lane_o,
  output logic [CACHELINE_BITS-1:0] meta_req_wdata_o,
  output logic [TAG_W-1:0]          meta_req_tag_o,

  input  logic                      meta_rsp_valid_i,
  output logic                      meta_rsp_ready_o,
  input  logic [CACHELINE_BITS-1:0] meta_rsp_data_i,
  input  logic [VERSION_W-1:0]      meta_rsp_version_i,
  input  logic [TAG_W-1:0]          meta_rsp_tag_i,
  input  logic                      meta_rsp_error_i
);

  typedef enum logic [4:0] {
    IC_IDLE,
    IC_READ_VERSION_REQ,
    IC_READ_VERSION_WAIT,
    IC_READ_TAG_REQ,
    IC_READ_TAG_WAIT,
    IC_HASH_START,
    IC_HASH_WAIT,
    IC_WRITE_TAG_REQ,
    IC_WRITE_TAG_WAIT,
    IC_NEXT_LEVEL,
    IC_DONE
  } ic_state_e;

  ic_state_e state_q, state_n;

  logic [31:0]              level_q, level_n;
  logic [31:0]              tree_height;
  logic [PLEN-1:0]          topo_tag_addr;
  logic [PLEN-1:0]          topo_version_addr;
  logic [PLEN-1:0]          topo_leaf_addr;
  logic [31:0]              topo_metadata_blocks;
  logic [31:0]              topo_leaf_count;
  logic [CACHELINE_BITS-1:0] data_q, data_n;
  logic [PLEN-1:0]          node_addr_q, node_addr_n;
  logic [CACHELINE_BITS-1:0] version_line_q, version_line_n;
  logic [CACHELINE_BITS-1:0] tag_line_q, tag_line_n;
  logic [VERSION_W-1:0]     version_q, version_n;
  logic [TAG_W-1:0]         expected_tag_q, expected_tag_n;
  logic [TAG_W-1:0]         new_tag_q, new_tag_n;
  logic                     pass_q, pass_n;
  logic                     is_write_q, is_write_n;

  logic hash_start;
  logic hash_ready;
  logic hash_valid;
  logic hash_pass;
  logic [TAG_W-1:0] hash_tag;

  assign ready_o        = (state_q == IC_IDLE);
  assign valid_o        = (state_q == IC_DONE);
  assign pass_o         = pass_q;
  assign corrupt_o      = valid_o && !pass_q;
  assign new_tag_o      = new_tag_q;
  assign leaf_version_o = version_q;

  securememory_topology_clean #(
    .PLEN           (PLEN),
    .CACHELINE_BITS (CACHELINE_BITS),
    .MARY           (MARY)
  ) u_topology (
    .mask_i                 (mask_i),
    .base_i                 (base_i),
    .addr_i                 (node_addr_q),
    .level_i                (level_q),
    .metadata_block_count_o (topo_metadata_blocks),
    .metadata_tag_addr_o    (topo_tag_addr),
    .metadata_version_addr_o(topo_version_addr),
    .merkletree_leaf_count_o(topo_leaf_count),
    .merkletree_height_o    (tree_height),
    .merkletree_leaf_addr_o (topo_leaf_addr)
  );

  bmt_hash_compare #(
    .ADDR_W     (PLEN),
    .DATA_W     (CACHELINE_BITS),
    .VERSION_W  (VERSION_W),
    .TAG_W      (TAG_W),
    .HASH_KEY   (HASH_KEY),
    .HASH_KEYLEN(HASH_KEYLEN)
  ) u_hash_compare (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .start_i        (hash_start),
    .ready_o        (hash_ready),
    .valid_o        (hash_valid),
    .addr_i         (node_addr_q),
    .data_i         (data_q),
    .version_i      (version_q),
    .level_i        (level_q),
    .expected_tag_i (expected_tag_q),
    .pass_o         (hash_pass),
    .computed_tag_o (hash_tag)
  );

  function automatic logic [2:0] line_lane64;
    input logic [PLEN-1:0] addr;
    begin
      // 512b line / 64b versions = 8 lanes. Use line offset bits [8:6].
      line_lane64 = addr[8:6];
    end
  endfunction

  function automatic logic [2:0] line_lane128;
    input logic [PLEN-1:0] addr;
    begin
      // 512b line / 128b tags = 4 lanes. Keep 3-bit port, upper value unused.
      line_lane128 = {1'b0, addr[7:6]};
    end
  endfunction

  always_comb begin
    state_n        = state_q;
    level_n        = level_q;
    data_n         = data_q;
    node_addr_n    = node_addr_q;
    version_line_n = version_line_q;
    tag_line_n     = tag_line_q;
    version_n      = version_q;
    expected_tag_n = expected_tag_q;
    new_tag_n      = new_tag_q;
    pass_n         = pass_q;
    is_write_n     = is_write_q;

    meta_req_valid_o = 1'b0;
    meta_req_op_o    = META_READ_VERSION;
    meta_req_addr_o  = '0;
    meta_req_lane_o  = '0;
    meta_req_wdata_o = '0;
    meta_req_tag_o   = '0;
    meta_rsp_ready_o = 1'b0;

    hash_start = 1'b0;

    unique case (state_q)
      IC_IDLE: begin
        if (start_i) begin
          level_n        = '0;
          node_addr_n    = addr_i;
          data_n         = protected_data_i;
          version_line_n = '0;
          tag_line_n     = '0;
          version_n      = write_version_i;
          expected_tag_n = '0;
          new_tag_n      = '0;
          pass_n         = 1'b0;
          is_write_n     = is_write_i;

          // Writes generate a fresh tag using the newly allocated version.
          // Reads must fetch version + expected tag first.
          state_n = is_write_i ? IC_HASH_START : IC_READ_VERSION_REQ;
        end
      end

      IC_READ_VERSION_REQ: begin
        meta_req_valid_o = 1'b1;
        meta_req_op_o    = META_READ_VERSION;
        meta_req_addr_o  = (level_q == 0) ? topo_version_addr : topo_leaf_addr;
        meta_req_lane_o  = line_lane64(node_addr_q);
        if (meta_req_ready_i) begin
          state_n = IC_READ_VERSION_WAIT;
        end
      end

      IC_READ_VERSION_WAIT: begin
        meta_rsp_ready_o = 1'b1;
        if (meta_rsp_valid_i) begin
          version_line_n = meta_rsp_data_i;
          version_n      = meta_rsp_version_i;
          if (meta_rsp_error_i) begin
            pass_n  = 1'b0;
            state_n = IC_DONE;
          end else begin
            state_n = IC_READ_TAG_REQ;
          end
        end
      end

      IC_READ_TAG_REQ: begin
        meta_req_valid_o = 1'b1;
        meta_req_op_o    = META_READ_TAG;
        meta_req_addr_o  = topo_tag_addr;
        meta_req_lane_o  = line_lane128(node_addr_q);
        if (meta_req_ready_i) begin
          state_n = IC_READ_TAG_WAIT;
        end
      end

      IC_READ_TAG_WAIT: begin
        meta_rsp_ready_o = 1'b1;
        if (meta_rsp_valid_i) begin
          tag_line_n     = meta_rsp_data_i;
          expected_tag_n = meta_rsp_tag_i;
          if (meta_rsp_error_i) begin
            pass_n  = 1'b0;
            state_n = IC_DONE;
          end else begin
            state_n = IC_HASH_START;
          end
        end
      end

      IC_HASH_START: begin
        if (hash_ready) begin
          hash_start = 1'b1;
          state_n    = IC_HASH_WAIT;
        end
      end

      IC_HASH_WAIT: begin
        if (hash_valid) begin
          new_tag_n = hash_tag;
          if (is_write_q) begin
            pass_n  = 1'b1;
            state_n = IC_WRITE_TAG_REQ;
          end else if (!hash_pass) begin
            pass_n  = 1'b0;
            state_n = IC_DONE;
          end else begin
            pass_n  = 1'b1;
            state_n = IC_NEXT_LEVEL;
          end
        end
      end

      IC_WRITE_TAG_REQ: begin
        meta_req_valid_o = 1'b1;
        meta_req_op_o    = META_WRITE_TAG;
        meta_req_addr_o  = topo_tag_addr;
        meta_req_lane_o  = line_lane128(node_addr_q);
        meta_req_tag_o   = new_tag_q;
        if (meta_req_ready_i) begin
          state_n = IC_WRITE_TAG_WAIT;
        end
      end

      IC_WRITE_TAG_WAIT: begin
        meta_rsp_ready_o = 1'b1;
        if (meta_rsp_valid_i) begin
          pass_n  = !meta_rsp_error_i;
          state_n = IC_DONE;
        end
      end

      IC_NEXT_LEVEL: begin
        // Serial BMT traversal. The verified version block becomes the protected
        // data for the next level. topo_leaf_addr points to the parent counter line.
        if (level_q >= tree_height || level_q >= MAX_LEVELS-1) begin
          state_n = IC_DONE;
        end else begin
          data_n      = version_line_q;
          node_addr_n = topo_leaf_addr;
          level_n     = level_q + 1'b1;
          state_n     = IC_READ_VERSION_REQ;
        end
      end

      IC_DONE: begin
        if (!start_i) begin
          state_n = IC_IDLE;
        end
      end

      default: begin
        state_n = IC_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= IC_IDLE;
      level_q        <= '0;
      data_q         <= '0;
      node_addr_q    <= '0;
      version_line_q <= '0;
      tag_line_q     <= '0;
      version_q      <= '0;
      expected_tag_q <= '0;
      new_tag_q      <= '0;
      pass_q         <= 1'b0;
      is_write_q     <= 1'b0;
    end else begin
      state_q        <= state_n;
      level_q        <= level_n;
      data_q         <= data_n;
      node_addr_q    <= node_addr_n;
      version_line_q <= version_line_n;
      tag_line_q     <= tag_line_n;
      version_q      <= version_n;
      expected_tag_q <= expected_tag_n;
      new_tag_q      <= new_tag_n;
      pass_q         <= pass_n;
      is_write_q     <= is_write_n;
    end
  end

endmodule
