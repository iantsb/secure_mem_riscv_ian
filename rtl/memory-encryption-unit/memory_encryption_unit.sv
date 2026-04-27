`default_nettype wire

import tilelink::*;

module memory_encryption_unit #(
    parameter int OUTER_DATA_WIDTH = 64,
    parameter int INNER_DATA_WIDTH = 512,
    parameter int SIZE_WIDTH       = 3,
    parameter int SOURCE_WIDTH     = 8,
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty,
    parameter logic [255:0] AES_KEY = {
        128'h2b7e151628aed2a6abf7158809cf4f3c,
        128'h00000000000000000000000000000000
    },
    parameter logic AES_KEYLEN = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    // CPU/source-side A channel.
    output logic src_a_ready_o,
    input  logic src_a_valid_i,
    input  ChannelA#(
        .DATA_WIDTH(OUTER_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::a_req_t src_a_req_i,

    // Memory/sink-side A channel.
    input  logic sink_a_ready_i,
    output logic sink_a_valid_o,
    output ChannelA#(
        .DATA_WIDTH(OUTER_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::a_req_t sink_a_req_o,

    // CPU/source-side D channel.
    input  logic src_d_ready_i,
    output logic src_d_valid_o,
    output ChannelD#(
        .DATA_WIDTH(OUTER_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::d_resp_t src_d_resp_o,

    // Memory/sink-side D channel.
    output logic sink_d_ready_o,
    input  logic sink_d_valid_i,
    input  ChannelD#(
        .DATA_WIDTH(OUTER_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::d_resp_t sink_d_resp_i,

    // ePMP inputs for secure-memory address mapping.
    input riscv_::pmpcfg_t [ROCKETCfg.NrPMPEntries-1:0] pmpcfg_i,
    input logic [ROCKETCfg.NrPMPEntries-1:0][ROCKETCfg.PLEN-3:0] pmpaddr_i
);

    localparam int CHUNK_WIDTH   = 128;
    localparam int CHUNK_COUNT   = INNER_DATA_WIDTH / CHUNK_WIDTH;
    localparam int ADDR_PAD      = ROCKETCfg.PLEN - ROCKETCfg.TL_ADDRESS_WIDTH;
    localparam int ADDR_IN_CTR_W = (ROCKETCfg.PLEN < 48) ? ROCKETCfg.PLEN : 48;

    localparam int _check_inner_width = 1 / ((INNER_DATA_WIDTH % CHUNK_WIDTH) == 0 ? 1 : 0);

    typedef ChannelA#(
        .DATA_WIDTH(INNER_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::a_req_t inner_a_t;

    typedef ChannelD#(
        .DATA_WIDTH(INNER_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::d_resp_t inner_d_t;

    // --------------------
    // Assembler interface
    // --------------------
    logic     assembler_a_valid;
    logic     assembler_a_ready;
    logic     assembler_a_fire;
    inner_a_t assembler_a_req;

    logic assembler_d_ready;

    // ----------------------
    // Fragmenter interface
    // ----------------------
    logic     fragmenter_a_ready;
    logic     fragmenter_a_valid;
    logic     fragmenter_a_fire;
    inner_a_t fragmenter_a_req;

    logic     fragmenter_d_ready;
    logic     fragmenter_d_valid;
    logic     fragmenter_d_fire;
    inner_d_t fragmenter_d_resp;

    // ----------------------
    // Upstream D interface
    // ----------------------
    logic     meu_d_valid;
    logic     meu_d_fire;
    inner_d_t meu_d_resp;

    // ----------------------
    // MEU state
    // ----------------------
    typedef enum logic [3:0] {
        MEU_IDLE,
        MEU_AES_START,
        MEU_AES_WAIT,
        MEU_GET_SEND_MEM,
        MEU_GET_WAIT_MEM,
        MEU_GET_RESPOND,
        MEU_PUT_SEND_MEM,
        MEU_PUT_WAIT_ACK,
        MEU_PUT_RESPOND,
        MEU_PASS_SEND_MEM,
        MEU_PASS_WAIT_RESP,
        MEU_PASS_RESPOND
    } meu_state_t;

    meu_state_t state_q, state_n;
    inner_a_t   req_q, req_n;
    inner_d_t   resp_q, resp_n;

    logic [INNER_DATA_WIDTH-1:0] keystream_q, keystream_n;
    logic [INNER_DATA_WIDTH-1:0] ctr_blocks;

    // Placeholder until metadata counter fetch is wired in.
    logic [63:0] line_counter_q, line_counter_n;

    logic is_get_q;
    logic is_get_n;
    logic is_put_q;
    logic is_put_n;

    // ----------------------
    // Address mapper outputs
    // ----------------------
    logic [ROCKETCfg.PLEN-1:0] req_addr_full;
    logic [ROCKETCfg.PLEN-1:0] smam_tag_addr;
    logic [ROCKETCfg.PLEN-1:0] smam_version_addr;
    logic [2:0]                smam_index;

    generate
        if (ADDR_PAD > 0) begin : gen_req_addr_pad
            assign req_addr_full = {{ADDR_PAD{1'b0}}, req_q.address};
        end else begin : gen_req_addr_same
            assign req_addr_full = req_q.address;
        end
    endgenerate

    sm_addr_mapper #(
        .ROCKETCfg(ROCKETCfg)
    ) smam_i (
        .addr_i         (req_addr_full),
        .pmpcfg_i       (pmpcfg_i),
        .pmpaddr_i      (pmpaddr_i),
        .tag_addr_o     (smam_tag_addr),
        .version_addr_o (smam_version_addr),
        .index_o        (smam_index)
    );

    // ----------------------
    // Assembler / fragmenter
    // ----------------------
    ztlassembler #(
        .SRC_DATA_WIDTH  (OUTER_DATA_WIDTH),
        .SINK_DATA_WIDTH (INNER_DATA_WIDTH),
        .SIZE_WIDTH      (SIZE_WIDTH),
        .SOURCE_WIDTH    (SOURCE_WIDTH)
    ) ztlassembler_i (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .src_a_ready_o  (src_a_ready_o),
        .src_a_valid_i  (src_a_valid_i),
        .src_a_req_i    (src_a_req_i),
        .sink_a_ready_i (assembler_a_ready),
        .sink_a_valid_o (assembler_a_valid),
        .sink_a_req_o   (assembler_a_req),
        .src_d_ready_i  (src_d_ready_i),
        .src_d_valid_o  (src_d_valid_o),
        .src_d_resp_o   (src_d_resp_o),
        .sink_d_ready_o (assembler_d_ready),
        .sink_d_valid_i (meu_d_valid),
        .sink_d_resp_i  (meu_d_resp)
    );

    ztl_fragmenter #(
        .SRC_DATA_BITS  (INNER_DATA_WIDTH),
        .SINK_DATA_BITS (OUTER_DATA_WIDTH),
        .SIZE_BITS      (SIZE_WIDTH),
        .SOURCE_BITS    (SOURCE_WIDTH)
    ) ztl_fragmenter_i (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .src_a_ready_o  (fragmenter_a_ready),
        .src_a_valid_i  (fragmenter_a_valid),
        .src_a_req_i    (fragmenter_a_req),
        .sink_a_ready_i (sink_a_ready_i),
        .sink_a_valid_o (sink_a_valid_o),
        .sink_a_req_o   (sink_a_req_o),
        .src_d_ready_i  (fragmenter_d_ready),
        .src_d_valid_o  (fragmenter_d_valid),
        .src_d_resp_o   (fragmenter_d_resp),
        .sink_d_ready_o (sink_d_ready_o),
        .sink_d_valid_i (sink_d_valid_i),
        .sink_d_resp_i  (sink_d_resp_i)
    );

    // ----------------------
    // AES CTR keystream
    // ----------------------
    logic aes_start;
    logic aes_ready;
    logic aes_valid;
    logic [INNER_DATA_WIDTH-1:0] aes_keystream;

    aes_ctr_nx128 #(
        .DATA_WIDTH (INNER_DATA_WIDTH),
        .AES_KEY    (AES_KEY),
        .AES_KEYLEN (AES_KEYLEN)
    ) aes_ctr_i (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .start_i          (aes_start),
        .counter_blocks_i (ctr_blocks),
        .ready_o          (aes_ready),
        .valid_o          (aes_valid),
        .keystream_o      (aes_keystream)
    );

    // Build one AES counter block per 128-bit lane of the cache line.
    // Format: {64-bit version/line counter, low address bits, 16-bit AES-lane index}.
    // The real design should assign line_counter_q from metadata memory using
    // smam_version_addr before entering MEU_AES_START. For now it remains a
    // commented integration placeholder and the value is tied to zero in IDLE.
    always_comb begin
        ctr_blocks = '0;
        for (int i = 0; i < CHUNK_COUNT; i++) begin
            logic [127:0] block;
            block = '0;
            block[127:64] = line_counter_q;
            block[16 +: ADDR_IN_CTR_W] = req_addr_full[ADDR_IN_CTR_W-1:0];
            block[15:0] = i[15:0];
            ctr_blocks[i*CHUNK_WIDTH +: CHUNK_WIDTH] = block;
        end
    end

    assign assembler_a_fire  = assembler_a_valid && assembler_a_ready;
    assign fragmenter_a_fire = fragmenter_a_valid && fragmenter_a_ready;
    assign fragmenter_d_fire = fragmenter_d_valid && fragmenter_d_ready;
    assign meu_d_fire        = meu_d_valid && assembler_d_ready;

    assign assembler_a_ready = (state_q == MEU_IDLE);

    always_comb begin
        state_n        = state_q;
        req_n          = req_q;
        resp_n         = resp_q;
        keystream_n    = keystream_q;
        line_counter_n = line_counter_q;
        is_get_n       = is_get_q;
        is_put_n       = is_put_q;

        fragmenter_a_valid = 1'b0;
        fragmenter_a_req   = req_q;
        fragmenter_d_ready = 1'b0;
        meu_d_valid        = 1'b0;
        meu_d_resp         = resp_q;
        aes_start          = 1'b0;

        unique case (state_q)
            MEU_IDLE: begin
                if (assembler_a_fire) begin
                    req_n       = assembler_a_req;
                    resp_n      = '0;
                    keystream_n = '0;
                    is_get_n    = (assembler_a_req.opcode == tilelink::GET);
                    is_put_n    = (assembler_a_req.opcode == tilelink::PUTFULLDATA) ||
                                  (assembler_a_req.opcode == tilelink::PUTPARTIALDATA);

                    // --------------------------------------------------------------
                    // Counter fetch placeholder:
                    //   Issue metadata/cache GET to smam_version_addr.
                    //   Wait for metadata response.
                    //   Assign line_counter_n from metadata response data.
                    // For datapath bring-up only, the line counter is tied to zero.
                    // Do not keep this for a secure repeated-write implementation.
                    // --------------------------------------------------------------
                    line_counter_n = 64'h0;

                    if (assembler_a_req.opcode == tilelink::GET ||
                        assembler_a_req.opcode == tilelink::PUTFULLDATA ||
                        assembler_a_req.opcode == tilelink::PUTPARTIALDATA) begin
                        state_n = MEU_AES_START;
                    end else begin
                        state_n = MEU_PASS_SEND_MEM;
                    end
                end
            end

            // CTR mode uses AES encrypt to generate a keystream for both reads
            // and writes. Encryption/decryption is data XOR keystream.
            MEU_AES_START: begin
                if (aes_ready) begin
                    aes_start = 1'b1;
                    state_n   = MEU_AES_WAIT;
                end
            end

            MEU_AES_WAIT: begin
                if (aes_valid) begin
                    keystream_n = aes_keystream;
                    state_n = is_get_q ? MEU_GET_SEND_MEM : MEU_PUT_SEND_MEM;
                end
            end

            MEU_GET_SEND_MEM: begin
                fragmenter_a_valid = 1'b1;
                fragmenter_a_req   = req_q;
                if (fragmenter_a_fire) begin
                    state_n = MEU_GET_WAIT_MEM;
                end
            end

            MEU_GET_WAIT_MEM: begin
                fragmenter_d_ready = 1'b1;
                if (fragmenter_d_fire) begin
                    resp_n      = fragmenter_d_resp;
                    resp_n.data = fragmenter_d_resp.data ^ keystream_q;
                    state_n     = MEU_GET_RESPOND;
                end
            end

            MEU_GET_RESPOND: begin
                meu_d_valid = 1'b1;
                meu_d_resp  = resp_q;
                if (meu_d_fire) begin
                    state_n        = MEU_IDLE;
                    req_n          = '0;
                    resp_n         = '0;
                    keystream_n    = '0;
                    line_counter_n = '0;
                    is_get_n       = 1'b0;
                    is_put_n       = 1'b0;
                end
            end

            MEU_PUT_SEND_MEM: begin
                fragmenter_a_valid      = 1'b1;
                fragmenter_a_req        = req_q;
                fragmenter_a_req.data   = req_q.data ^ keystream_q;
                if (fragmenter_a_fire) begin
                    state_n = MEU_PUT_WAIT_ACK;
                end
            end

            MEU_PUT_WAIT_ACK: begin
                fragmenter_d_ready = 1'b1;
                if (fragmenter_d_fire) begin
                    resp_n  = fragmenter_d_resp;
                    state_n = MEU_PUT_RESPOND;
                end
            end

            MEU_PUT_RESPOND: begin
                meu_d_valid = 1'b1;
                meu_d_resp  = resp_q;
                if (meu_d_fire) begin
                    state_n        = MEU_IDLE;
                    req_n          = '0;
                    resp_n         = '0;
                    keystream_n    = '0;
                    line_counter_n = '0;
                    is_get_n       = 1'b0;
                    is_put_n       = 1'b0;
                end
            end

            MEU_PASS_SEND_MEM: begin
                fragmenter_a_valid = 1'b1;
                fragmenter_a_req   = req_q;
                if (fragmenter_a_fire) begin
                    state_n = MEU_PASS_WAIT_RESP;
                end
            end

            MEU_PASS_WAIT_RESP: begin
                fragmenter_d_ready = 1'b1;
                if (fragmenter_d_fire) begin
                    resp_n  = fragmenter_d_resp;
                    state_n = MEU_PASS_RESPOND;
                end
            end

            MEU_PASS_RESPOND: begin
                meu_d_valid = 1'b1;
                meu_d_resp  = resp_q;
                if (meu_d_fire) begin
                    state_n        = MEU_IDLE;
                    req_n          = '0;
                    resp_n         = '0;
                    keystream_n    = '0;
                    line_counter_n = '0;
                    is_get_n       = 1'b0;
                    is_put_n       = 1'b0;
                end
            end

            default: begin
                state_n = MEU_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q        <= MEU_IDLE;
            req_q          <= '0;
            resp_q         <= '0;
            keystream_q    <= '0;
            line_counter_q <= '0;
            is_get_q       <= 1'b0;
            is_put_q       <= 1'b0;
        end else begin
            state_q        <= state_n;
            req_q          <= req_n;
            resp_q         <= resp_n;
            keystream_q    <= keystream_n;
            line_counter_q <= line_counter_n;
            is_get_q       <= is_get_n;
            is_put_q       <= is_put_n;
        end
    end

endmodule
