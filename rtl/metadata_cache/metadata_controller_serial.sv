`timescale 1ns/1ps

import metadata_pkg::*;

// Serial metadata controller/cache front-end for the first functional design.
// It presents one metadata request port to secure_memory_controller/integritychecker.
// Reads are served from metadata_cache when possible and from memory on miss.
// Writes/allocations update the cache and are write-through to backing memory.
module metadata_controller_serial #(
  parameter int PLEN           = 56,
  parameter int CACHELINE_BITS = 512,
  parameter int VERSION_W      = 64,
  parameter int TAG_W          = 128,
  parameter int CACHE_LINES    = 8,
  parameter int NUM_WAYS       = 2
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,

  input  logic                      req_valid_i,
  output logic                      req_ready_o,
  input  meta_op_e                  req_op_i,
  input  logic [PLEN-1:0]           req_addr_i,
  input  logic [2:0]                req_lane_i,
  input  logic [CACHELINE_BITS-1:0] req_wdata_i,
  input  logic [TAG_W-1:0]          req_tag_i,

  output logic                      rsp_valid_o,
  input  logic                      rsp_ready_i,
  output logic [CACHELINE_BITS-1:0] rsp_data_o,
  output logic [VERSION_W-1:0]      rsp_version_o,
  output logic [TAG_W-1:0]          rsp_tag_o,
  output logic                      rsp_hit_o,
  output logic                      rsp_error_o,

  output logic                      mem_req_valid_o,
  input  logic                      mem_req_ready_i,
  output logic                      mem_req_write_o,
  output logic [PLEN-1:0]           mem_req_addr_o,
  output logic [CACHELINE_BITS-1:0] mem_req_wdata_o,

  input  logic                      mem_rsp_valid_i,
  input  logic [CACHELINE_BITS-1:0] mem_rsp_data_i,
  input  logic                      mem_rsp_error_i
);

  typedef enum logic [3:0] {
    MD_IDLE,
    MD_LOOKUP,
    MD_MEM_READ_REQ,
    MD_MEM_READ_WAIT,
    MD_MODIFY,
    MD_MEM_WRITE_REQ,
    MD_RESPOND
  } md_state_e;

  md_state_e state_q, state_n;

  meta_op_e                  op_q, op_n;
  logic [PLEN-1:0]           addr_q, addr_n;
  logic [2:0]                lane_q, lane_n;
  logic [CACHELINE_BITS-1:0] wdata_q, wdata_n;
  logic [TAG_W-1:0]          tag_q, tag_n;
  logic [CACHELINE_BITS-1:0] line_q, line_n;
  logic                      hit_q, hit_n;
  logic                      error_q, error_n;

  logic                      cache_lookup_valid;
  logic [PLEN-1:0]           cache_lookup_addr;
  logic                      cache_lookup_hit;
  logic [CACHELINE_BITS-1:0] cache_lookup_data;
  logic                      cache_fill_valid;
  logic [PLEN-1:0]           cache_fill_addr;
  logic [CACHELINE_BITS-1:0] cache_fill_data;
  logic                      cache_update_valid;
  logic [PLEN-1:0]           cache_update_addr;
  logic [CACHELINE_BITS-1:0] cache_update_data;

  metadata_cache #(
    .ADDR_WIDTH  (PLEN),
    .DATA_WIDTH  (CACHELINE_BITS),
    .CACHE_LINES (CACHE_LINES),
    .NUM_WAYS    (NUM_WAYS)
  ) u_cache (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .lookup_valid_i (cache_lookup_valid),
    .lookup_addr_i  (cache_lookup_addr),
    .lookup_hit_o   (cache_lookup_hit),
    .lookup_data_o  (cache_lookup_data),
    .fill_valid_i   (cache_fill_valid),
    .fill_addr_i    (cache_fill_addr),
    .fill_data_i    (cache_fill_data),
    .update_valid_i (cache_update_valid),
    .update_addr_i  (cache_update_addr),
    .update_data_i  (cache_update_data)
  );

  function automatic logic [VERSION_W-1:0] get_version_lane;
    input logic [CACHELINE_BITS-1:0] line;
    input logic [2:0] lane;
    begin
      get_version_lane = line[lane*VERSION_W +: VERSION_W];
    end
  endfunction

  function automatic logic [TAG_W-1:0] get_tag_lane;
    input logic [CACHELINE_BITS-1:0] line;
    input logic [2:0] lane;
    logic [1:0] idx;
    begin
      idx = lane[1:0];
      get_tag_lane = line[idx*TAG_W +: TAG_W];
    end
  endfunction

  function automatic logic [CACHELINE_BITS-1:0] set_version_lane;
    input logic [CACHELINE_BITS-1:0] line;
    input logic [2:0] lane;
    input logic [VERSION_W-1:0] value;
    logic [CACHELINE_BITS-1:0] tmp;
    begin
      tmp = line;
      tmp[lane*VERSION_W +: VERSION_W] = value;
      set_version_lane = tmp;
    end
  endfunction

  function automatic logic [CACHELINE_BITS-1:0] set_tag_lane;
    input logic [CACHELINE_BITS-1:0] line;
    input logic [2:0] lane;
    input logic [TAG_W-1:0] value;
    logic [CACHELINE_BITS-1:0] tmp;
    logic [1:0] idx;
    begin
      idx = lane[1:0];
      tmp = line;
      tmp[idx*TAG_W +: TAG_W] = value;
      set_tag_lane = tmp;
    end
  endfunction

  assign rsp_data_o    = line_q;
  assign rsp_version_o = get_version_lane(line_q, lane_q);
  assign rsp_tag_o     = get_tag_lane(line_q, lane_q);
  assign rsp_hit_o     = hit_q;
  assign rsp_error_o   = error_q;

  always_comb begin
    state_n = state_q;
    op_n    = op_q;
    addr_n  = addr_q;
    lane_n  = lane_q;
    wdata_n = wdata_q;
    tag_n   = tag_q;
    line_n  = line_q;
    hit_n   = hit_q;
    error_n = error_q;

    req_ready_o = 1'b0;
    rsp_valid_o = 1'b0;

    cache_lookup_valid = 1'b0;
    cache_lookup_addr  = '0;
    cache_fill_valid   = 1'b0;
    cache_fill_addr    = '0;
    cache_fill_data    = '0;
    cache_update_valid = 1'b0;
    cache_update_addr  = '0;
    cache_update_data  = '0;

    mem_req_valid_o = 1'b0;
    mem_req_write_o = 1'b0;
    mem_req_addr_o  = '0;
    mem_req_wdata_o = '0;

    unique case (state_q)
      MD_IDLE: begin
        req_ready_o = 1'b1;
        if (req_valid_i) begin
          op_n    = req_op_i;
          addr_n  = req_addr_i;
          lane_n  = req_lane_i;
          wdata_n = req_wdata_i;
          tag_n   = req_tag_i;
          hit_n   = 1'b0;
          error_n = 1'b0;
          state_n = MD_LOOKUP;
        end
      end

      MD_LOOKUP: begin
        cache_lookup_valid = 1'b1;
        cache_lookup_addr  = addr_q;
        if (cache_lookup_hit) begin
          line_n = cache_lookup_data;
          hit_n  = 1'b1;
          if (op_q == META_READ_VERSION || op_q == META_READ_TAG) begin
            state_n = MD_RESPOND;
          end else begin
            state_n = MD_MODIFY;
          end
        end else begin
          state_n = MD_MEM_READ_REQ;
        end
      end

      MD_MEM_READ_REQ: begin
        mem_req_valid_o = 1'b1;
        mem_req_write_o = 1'b0;
        mem_req_addr_o  = addr_q;
        if (mem_req_ready_i) begin
          state_n = MD_MEM_READ_WAIT;
        end
      end

      MD_MEM_READ_WAIT: begin
        if (mem_rsp_valid_i) begin
          line_n  = mem_rsp_data_i;
          error_n = mem_rsp_error_i;
          if (!mem_rsp_error_i) begin
            cache_fill_valid = 1'b1;
            cache_fill_addr  = addr_q;
            cache_fill_data  = mem_rsp_data_i;
          end
          if (op_q == META_READ_VERSION || op_q == META_READ_TAG || mem_rsp_error_i) begin
            state_n = MD_RESPOND;
          end else begin
            state_n = MD_MODIFY;
          end
        end
      end

      MD_MODIFY: begin
        if (op_q == META_ALLOC_VERSION) begin
          line_n = set_version_lane(line_q, lane_q, get_version_lane(line_q, lane_q) + 1'b1);
        end else if (op_q == META_WRITE_TAG) begin
          line_n = set_tag_lane(line_q, lane_q, tag_q);
        end else begin
          line_n = wdata_q;
        end
        state_n = MD_MEM_WRITE_REQ;
      end

      MD_MEM_WRITE_REQ: begin
        cache_update_valid = 1'b1;
        cache_update_addr  = addr_q;
        cache_update_data  = line_q;

        mem_req_valid_o = 1'b1;
        mem_req_write_o = 1'b1;
        mem_req_addr_o  = addr_q;
        mem_req_wdata_o = line_q;
        if (mem_req_ready_i) begin
          state_n = MD_RESPOND;
        end
      end

      MD_RESPOND: begin
        rsp_valid_o = 1'b1;
        if (rsp_ready_i) begin
          state_n = MD_IDLE;
          line_n  = '0;
          error_n = 1'b0;
          hit_n   = 1'b0;
        end
      end

      default: begin
        state_n = MD_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= MD_IDLE;
      op_q    <= META_READ_VERSION;
      addr_q  <= '0;
      lane_q  <= '0;
      wdata_q <= '0;
      tag_q   <= '0;
      line_q  <= '0;
      hit_q   <= 1'b0;
      error_q <= 1'b0;
    end else begin
      state_q <= state_n;
      op_q    <= op_n;
      addr_q  <= addr_n;
      lane_q  <= lane_n;
      wdata_q <= wdata_n;
      tag_q   <= tag_n;
      line_q  <= line_n;
      hit_q   <= hit_n;
      error_q <= error_n;
    end
  end

endmodule
