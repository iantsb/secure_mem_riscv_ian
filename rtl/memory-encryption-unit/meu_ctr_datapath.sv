`timescale 1ns/1ps

// Single-line AES-CTR transform engine. The controller supplies the already
// fetched/allocated version counter. This block does not fetch metadata.
module meu_ctr_datapath #(
  parameter int ADDR_W    = 56,
  parameter int DATA_W    = 512,
  parameter int VERSION_W = 64,
  parameter logic [255:0] AES_KEY = {
    128'h2b7e151628aed2a6abf7158809cf4f3c,
    128'h00000000000000000000000000000000
  },
  parameter logic AES_KEYLEN = 1'b0
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic                 start_i,
  output logic                 ready_o,
  output logic                 valid_o,

  input  logic [ADDR_W-1:0]    addr_i,
  input  logic [VERSION_W-1:0] version_i,
  input  logic [DATA_W-1:0]    data_i,

  output logic [DATA_W-1:0]    data_o
);

  localparam int CHUNK_W = 128;
  localparam int CHUNKS  = DATA_W / CHUNK_W;
  localparam int CTR_ADDR_W = 42;

  logic [DATA_W-1:0] ctr_blocks;
  logic [DATA_W-1:0] keystream;
  logic              aes_ready;
  logic              aes_valid;
  logic [DATA_W-1:0] data_q, data_n;
  logic              valid_q, valid_n;

  assign ready_o = aes_ready && !valid_q;
  assign valid_o = valid_q;
  assign data_o  = data_q;

  always_comb begin
    ctr_blocks = '0;
    for (int i = 0; i < CHUNKS; i++) begin
      logic [127:0] b;
      b = '0;
      b[127:112] = 16'hC7A0;             // CTR domain separator
      b[111:70]  = addr_i[CTR_ADDR_W-1:0];
      b[69:6]    = version_i;
      b[5:0]     = 6'(i);
      ctr_blocks[i*CHUNK_W +: CHUNK_W] = b;
    end
  end

  aes_ctr_nx128 #(
    .DATA_WIDTH (DATA_W),
    .CHUNK_WIDTH(CHUNK_W),
    .AES_KEY    (AES_KEY),
    .AES_KEYLEN (AES_KEYLEN)
  ) u_ctr (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .start_i          (start_i && ready_o),
    .counter_blocks_i (ctr_blocks),
    .ready_o          (aes_ready),
    .valid_o          (aes_valid),
    .keystream_o      (keystream)
  );

  always_comb begin
    data_n  = data_q;
    valid_n = valid_q;

    if (start_i && ready_o) begin
      valid_n = 1'b0;
    end

    if (aes_valid) begin
      data_n  = data_i ^ keystream;
      valid_n = 1'b1;
    end

    if (valid_q && !start_i) begin
      valid_n = 1'b0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_q  <= '0;
      valid_q <= 1'b0;
    end else begin
      data_q  <= data_n;
      valid_q <= valid_n;
    end
  end

endmodule
