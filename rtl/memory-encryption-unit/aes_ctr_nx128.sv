`default_nettype none

// CTR keystream generator using the secworks/aes aes_core.

module aes_ctr_nx128 #(
    parameter int DATA_WIDTH  = 512,
    parameter int CHUNK_WIDTH = 128,
    parameter logic [255:0] AES_KEY = {
        128'h2b7e151628aed2a6abf7158809cf4f3c,
        128'h00000000000000000000000000000000
    },
    parameter logic AES_KEYLEN = 1'b0  // secworks/aes: 0 = AES-128, 1 = AES-256
) (
    input  wire logic                  clk_i,
    input  wire logic                  rst_ni,

    input  wire logic                  start_i,
    input  wire logic [DATA_WIDTH-1:0] counter_blocks_i,

    output logic                       ready_o,
    output logic                       valid_o,
    output logic [DATA_WIDTH-1:0]      keystream_o
);
    localparam int _check_data_width = 1 / ((DATA_WIDTH % CHUNK_WIDTH) == 0 ? 1 : 0);
    localparam int CHUNK_COUNT = DATA_WIDTH / CHUNK_WIDTH;

    typedef enum logic [1:0] {
        AES_INIT_START,
        AES_INIT_WAIT,
        AES_READY,
        AES_BUSY
    } aes_wrap_state_t;

    aes_wrap_state_t state_q, state_n;

    logic [DATA_WIDTH-1:0] blocks_q, blocks_n;
    logic                  init_core;
    logic                  next_core;
    logic [CHUNK_COUNT-1:0] ready_core;
    logic [CHUNK_COUNT-1:0] valid_core;

    assign ready_o = (state_q == AES_READY);
    assign valid_o = (state_q == AES_BUSY) && (&valid_core);

    genvar i;
    generate
        for (i = 0; i < CHUNK_COUNT; i++) begin : gen_aes_core
            aes_core u_aes_core (
                .clk          (clk_i),
                .reset_n      (rst_ni),
                .encdec       (1'b1),      
                .init         (init_core),
                .next         (next_core),
                .ready        (ready_core[i]),
                .key          (AES_KEY),
                .keylen       (AES_KEYLEN),
                .block        (blocks_q[i*CHUNK_WIDTH +: CHUNK_WIDTH]),
                .result       (keystream_o[i*CHUNK_WIDTH +: CHUNK_WIDTH]),
                .result_valid (valid_core[i])
            );
        end
    endgenerate

    always_comb begin
        state_n   = state_q;
        blocks_n  = blocks_q;
        init_core = 1'b0;
        next_core = 1'b0;

        unique case (state_q)
            AES_INIT_START: begin
                init_core = 1'b1;
                state_n   = AES_INIT_WAIT;
            end

            AES_INIT_WAIT: begin
                if (&ready_core) begin
                    state_n = AES_READY;
                end
            end

            AES_READY: begin
                if (start_i) begin
                    blocks_n  = counter_blocks_i;
                    next_core = 1'b1;
                    state_n   = AES_BUSY;
                end
            end

            AES_BUSY: begin
                if (&valid_core) begin
                    state_n = AES_READY;
                end
            end

            default: begin
                state_n = AES_INIT_START;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q  <= AES_INIT_START;
            blocks_q <= '0;
        end else begin
            state_q  <= state_n;
            blocks_q <= blocks_n;
        end
    end

endmodule

`default_nettype wire
