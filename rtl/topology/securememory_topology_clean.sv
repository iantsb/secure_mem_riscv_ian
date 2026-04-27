`timescale 1ns/1ps

// Address topology for the simple serial secure-memory implementation.
// This keeps the original designer's naming convention:
//   version == counter metadata
//   tag     == integrity tag metadata
// It follows the original securememory_topology formulas, but adds guards around
// variable shifts so synthesis does not see negative/oversized shift amounts.
module securememory_topology_clean #(
  parameter int PLEN           = 56,
  parameter int CACHELINE_BITS = 512,
  parameter int MARY           = 8,
  parameter int CACHELINE_BYTES = CACHELINE_BITS / 8
) (
  input  logic [PLEN-1:0] mask_i,
  input  logic [PLEN-1:0] base_i,
  input  logic [PLEN-1:0] addr_i,
  input  logic [31:0]     level_i,

  output logic [31:0]     metadata_block_count_o,
  output logic [PLEN-1:0] metadata_tag_addr_o,
  output logic [PLEN-1:0] metadata_version_addr_o,
  output logic [31:0]     merkletree_leaf_count_o,
  output logic [31:0]     merkletree_height_o,
  output logic [PLEN-1:0] merkletree_leaf_addr_o
);

  localparam int K = (MARY > 1) ? $clog2(MARY) : 1;

  logic [$clog2(PLEN)-1:0] trail_zeros;
  logic [PLEN-1:0] upper_addr;
  logic [PLEN-1:0] lower_addr;
  logic [PLEN-1:0] md_mask;
  logic [PLEN-1:0] md_index;
  logic [PLEN-1:0] lz_mask;
  logic [PLEN-1:0] ll_mask;
  logic [PLEN-1:0] ll_index;
  logic [PLEN-1:0] mem_bytes;
  logic [PLEN-1:0] pd_bytes;
  logic [31:0]     pd_blocks;
  logic [31:0]     log2_leaves;

  // Counts trailing zeros in ~mask_i. This matches the original topology module.
  lzc #(
    .WIDTH (PLEN),
    .MODE  (1'b0)
  ) i_lzc (
    .in_i    (~mask_i),
    .cnt_o   (trail_zeros),
    .empty_o ()
  );

  function automatic logic [PLEN-1:0] ones_shifted_left(input int unsigned ones, input int unsigned shamt);
    logic [PLEN-1:0] tmp;
    begin
      tmp = '0;
      if (ones >= PLEN) begin
        tmp = '1;
      end else begin
        tmp = ({{(PLEN-1){1'b0}}, 1'b1} << ones) - {{(PLEN-1){1'b0}}, 1'b1};
      end
      if (shamt >= PLEN) begin
        ones_shifted_left = '0;
      end else begin
        ones_shifted_left = tmp << shamt;
      end
    end
  endfunction

  function automatic logic [31:0] ceil_log_m(input logic [31:0] value, input int unsigned radix_log2);
    logic [31:0] v;
    logic [31:0] h;
    begin
      v = (value > 1) ? (value - 1) : 0;
      h = 0;
      for (int n = 0; n < 32; n++) begin
        if (v != 0) begin
          v = v >> radix_log2;
          h = h + 1;
        end
      end
      ceil_log_m = h;
    end
  endfunction

  always_comb begin
    upper_addr = base_i | (~mask_i & addr_i);
    lower_addr = mask_i & addr_i;

    // First-level data metadata locations.
    md_mask = '0;
    if (trail_zeros >= 2) begin
      md_mask = 2'b11 << (trail_zeros - 2);
    end

    md_index = lower_addr >> 9;
    metadata_tag_addr_o     = upper_addr | md_mask | (md_index << 7);
    metadata_version_addr_o = metadata_tag_addr_o;
    metadata_version_addr_o[6] = 1'b1;

    // Bonsai Merkle tree leaf address. MARY=8 means each tree level consumes 3 bits.
    lz_mask = '0;
    if (trail_zeros >= 6) begin
      lz_mask = 6'b11_1111 << (trail_zeros - 6);
    end

    ll_mask = lz_mask;
    if (trail_zeros >= (6 + (K * level_i))) begin
      ll_mask = lz_mask | ones_shifted_left(K * level_i, trail_zeros - 6 - (K * level_i));
    end

    ll_index = lower_addr >> (12 + (K * level_i));
    merkletree_leaf_addr_o = upper_addr | ll_mask | (ll_index << 6);

    mem_bytes = mask_i + {{(PLEN-1){1'b0}}, 1'b1};
    pd_bytes  = (mem_bytes >> 1) | (mem_bytes >> 2);

    pd_blocks = pd_bytes / CACHELINE_BYTES;
    metadata_block_count_o = (MARY != 0) ? (pd_blocks / MARY) : 32'd0;
    merkletree_leaf_count_o = (MARY != 0) ? (metadata_block_count_o / MARY) : 32'd0;

    log2_leaves = ceil_log_m(merkletree_leaf_count_o, K);
    merkletree_height_o = log2_leaves;
  end

endmodule
