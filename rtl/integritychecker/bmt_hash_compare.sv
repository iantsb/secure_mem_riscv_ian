`timescale 1ns/1ps

// AES-CBC-MAC style Bonsai Merkle Tree node hash/compare.
// This is not a placeholder XOR fold. It uses the secworks aes_core as a keyed
// compression primitive:
//   chain_0 = AES_K(header_block)
//   chain_i = AES_K(chain_{i-1} ^ data_block_i)
//   tag     = chain_last
//
// Read/verify: compare computed tag against expected_tag_i.
// Write/update: computed_tag_o is the new metadata tag to store.
module bmt_hash_compare #(
  parameter int ADDR_W    = 56,
  parameter int DATA_W    = 512,
  parameter int VERSION_W = 64,
  parameter int TAG_W     = 128,
  parameter int LEVEL_W   = 32,
  parameter logic [255:0] HASH_KEY = {
    128'h2b7e151628aed2a6abf7158809cf4f3c,
    128'h00000000000000000000000000000000
  },
  parameter logic HASH_KEYLEN = 1'b0
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic                 start_i,
  output logic                 ready_o,
  output logic                 valid_o,

  input  logic [ADDR_W-1:0]    addr_i,
  input  logic [DATA_W-1:0]    data_i,
  input  logic [VERSION_W-1:0] version_i,
  input  logic [LEVEL_W-1:0]   level_i,
  input  logic [TAG_W-1:0]     expected_tag_i,

  output logic                 pass_o,
  output logic [TAG_W-1:0]     computed_tag_o
);

  localparam int AES_BLOCK_W = 128;
  localparam int DATA_BLOCKS = DATA_W / AES_BLOCK_W;
  localparam int TOTAL_BLOCKS = DATA_BLOCKS + 1; // header + data chunks

  localparam logic [15:0] DOMAIN_BMT = 16'hB047;

  typedef enum logic [2:0] {
    HC_INIT_START,
    HC_INIT_WAIT,
    HC_READY,
    HC_LAUNCH,
    HC_WAIT,
    HC_DONE
  } hc_state_e;

  hc_state_e state_q, state_n;

  logic [$clog2(TOTAL_BLOCKS+1)-1:0] block_idx_q, block_idx_n;
  logic [AES_BLOCK_W-1:0]            chain_q, chain_n;
  logic [AES_BLOCK_W-1:0]            aes_block;
  logic [AES_BLOCK_W-1:0]            aes_result;
  logic                              aes_ready;
  logic                              aes_valid;
  logic                              aes_init;
  logic                              aes_next;
  logic [TAG_W-1:0]                  computed_tag_q, computed_tag_n;
  logic                              pass_q, pass_n;

  assign ready_o        = (state_q == HC_READY);
  assign valid_o        = (state_q == HC_DONE);
  assign computed_tag_o = computed_tag_q;
  assign pass_o         = pass_q;

  aes_core u_aes_core (
    .clk          (clk_i),
    .reset_n      (rst_ni),
    .encdec       (1'b1),
    .init         (aes_init),
    .next         (aes_next),
    .ready        (aes_ready),
    .key          (HASH_KEY),
    .keylen       (HASH_KEYLEN),
    .block        (aes_block),
    .result       (aes_result),
    .result_valid (aes_valid)
  );

  function automatic logic [AES_BLOCK_W-1:0] header_block;
  input logic [ADDR_W-1:0]    addr;
  input logic [VERSION_W-1:0] version;
  input logic [LEVEL_W-1:0]   level;

  logic [AES_BLOCK_W-1:0] h;
  logic [55:0]            addr56;

  begin
    h = '0;

    if (ADDR_W >= 56) begin
      addr56 = addr[55:0];
    end else begin
      addr56 = {{(56-ADDR_W){1'b0}}, addr};
    end

    h[127:112] = DOMAIN_BMT;
    h[111:80]  = level;
    h[79:24]   = addr56;
    h[23:0]    = version[23:0];

    // The full version is also mixed into the lower VERSION_W bits.
    header_block = h ^ {{(AES_BLOCK_W-VERSION_W){1'b0}}, version};
  end
endfunction

  function automatic logic [AES_BLOCK_W-1:0] data_block_at;
    input logic [$clog2(TOTAL_BLOCKS+1)-1:0] idx;
    begin
      if (idx == '0) begin
        data_block_at = header_block(addr_i, version_i, level_i);
      end else begin
        data_block_at = data_i[(idx-1)*AES_BLOCK_W +: AES_BLOCK_W];
      end
    end
  endfunction

  always_comb begin
    state_n        = state_q;
    block_idx_n    = block_idx_q;
    chain_n        = chain_q;
    computed_tag_n = computed_tag_q;
    pass_n         = pass_q;

    aes_init = 1'b0;
    aes_next = 1'b0;
    aes_block = chain_q ^ data_block_at(block_idx_q);

    unique case (state_q)
      HC_INIT_START: begin
        aes_init = 1'b1;
        state_n  = HC_INIT_WAIT;
      end

      HC_INIT_WAIT: begin
        if (aes_ready) begin
          state_n = HC_READY;
        end
      end

      HC_READY: begin
        if (start_i) begin
          block_idx_n    = '0;
          chain_n        = '0;
          computed_tag_n = '0;
          pass_n         = 1'b0;
          state_n        = HC_LAUNCH;
        end
      end

      HC_LAUNCH: begin
        aes_next = 1'b1;
        state_n  = HC_WAIT;
      end

      HC_WAIT: begin
        if (aes_valid) begin
          chain_n = aes_result;
          if (block_idx_q == TOTAL_BLOCKS-1) begin
            computed_tag_n = aes_result[TAG_W-1:0];
            pass_n         = (aes_result[TAG_W-1:0] == expected_tag_i);
            state_n        = HC_DONE;
          end else begin
            block_idx_n = block_idx_q + 1'b1;
            state_n     = HC_LAUNCH;
          end
        end
      end

      HC_DONE: begin
        if (!start_i) begin
          state_n = HC_READY;
        end
      end

      default: begin
        state_n = HC_INIT_START;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= HC_INIT_START;
      block_idx_q    <= '0;
      chain_q        <= '0;
      computed_tag_q <= '0;
      pass_q         <= 1'b0;
    end else begin
      state_q        <= state_n;
      block_idx_q    <= block_idx_n;
      chain_q        <= chain_n;
      computed_tag_q <= computed_tag_n;
      pass_q         <= pass_n;
    end
  end

endmodule
