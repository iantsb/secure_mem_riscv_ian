`default_nettype wire

import tilelink::*;

module ztl_fragmenter #(
    parameter int SRC_DATA_BITS  = 512,
    parameter int SINK_DATA_BITS = 64,
    parameter int SIZE_BITS      = 3,
    parameter int SOURCE_BITS    = 8
) (
    input logic clk_i,
    input logic rst_ni,

    // Upstream/source A channel, wide side.
    output logic src_a_ready_o,
    input  logic src_a_valid_i,
    input  ChannelA#(
        .DATA_WIDTH(SRC_DATA_BITS),
        .SIZE_WIDTH(SIZE_BITS),
        .SOURCE_WIDTH(SOURCE_BITS)
    )::a_req_t src_a_req_i,

    // Downstream/sink A channel, narrow side.
    input  logic sink_a_ready_i,
    output logic sink_a_valid_o,
    output ChannelA#(
        .DATA_WIDTH(SINK_DATA_BITS),
        .SIZE_WIDTH(SIZE_BITS),
        .SOURCE_WIDTH(SOURCE_BITS)
    )::a_req_t sink_a_req_o,

    // Upstream/source D channel, wide side.
    input  logic src_d_ready_i,
    output logic src_d_valid_o,
    output ChannelD#(
        .DATA_WIDTH(SRC_DATA_BITS),
        .SIZE_WIDTH(SIZE_BITS),
        .SOURCE_WIDTH(SOURCE_BITS)
    )::d_resp_t src_d_resp_o,

    // Downstream/sink D channel, narrow side.
    output logic sink_d_ready_o,
    input  logic sink_d_valid_i,
    input  ChannelD#(
        .DATA_WIDTH(SINK_DATA_BITS),
        .SIZE_WIDTH(SIZE_BITS),
        .SOURCE_WIDTH(SOURCE_BITS)
    )::d_resp_t sink_d_resp_i
);

    localparam int _check_divisible = 1 / ((SRC_DATA_BITS % SINK_DATA_BITS) == 0 ? 1 : 0);
    localparam int RATIO            = SRC_DATA_BITS / SINK_DATA_BITS;
    localparam int COUNT_WIDTH      = (RATIO <= 2) ? 1 : $clog2(RATIO);

    typedef ChannelA#(
        .DATA_WIDTH(SRC_DATA_BITS),
        .SIZE_WIDTH(SIZE_BITS),
        .SOURCE_WIDTH(SOURCE_BITS)
    )::a_req_t wide_a_t;

    typedef ChannelA#(
        .DATA_WIDTH(SINK_DATA_BITS),
        .SIZE_WIDTH(SIZE_BITS),
        .SOURCE_WIDTH(SOURCE_BITS)
    )::a_req_t narrow_a_t;

    typedef ChannelD#(
        .DATA_WIDTH(SRC_DATA_BITS),
        .SIZE_WIDTH(SIZE_BITS),
        .SOURCE_WIDTH(SOURCE_BITS)
    )::d_resp_t wide_d_t;

    typedef ChannelD#(
        .DATA_WIDTH(SINK_DATA_BITS),
        .SIZE_WIDTH(SIZE_BITS),
        .SOURCE_WIDTH(SOURCE_BITS)
    )::d_resp_t narrow_d_t;

    wide_a_t   req_q, req_n;
    narrow_a_t a_fragment;
    logic [COUNT_WIDTH-1:0] a_idx_q, a_idx_n;
    logic [COUNT_WIDTH:0]   a_total_q, a_total_n;
    logic                   a_busy_q, a_busy_n;
    logic                   sink_a_fire;
    logic                   src_a_fire;

    wide_d_t resp_q, resp_n;
    logic [COUNT_WIDTH-1:0] d_idx_q, d_idx_n;
    logic [COUNT_WIDTH:0]   d_total_q, d_total_n;
    logic                   d_busy_q, d_busy_n;
    logic                   sink_d_fire;
    logic                   src_d_fire;

    function automatic logic [COUNT_WIDTH:0] beats_for_size(input logic [SIZE_BITS-1:0] size);
        int unsigned bytes;
        int unsigned beats;
        begin
            bytes = (1 << size);
            beats = (bytes + (SINK_DATA_BITS/8) - 1) / (SINK_DATA_BITS/8);
            if (beats < 1) beats = 1;
            if (beats > RATIO) beats = RATIO;
            beats_for_size = beats[COUNT_WIDTH:0];
        end
    endfunction

    assign src_a_fire  = src_a_valid_i && src_a_ready_o;
    assign sink_a_fire = sink_a_valid_o && sink_a_ready_i;
    assign sink_d_fire = sink_d_valid_i && sink_d_ready_o;
    assign src_d_fire  = src_d_valid_o  && src_d_ready_i;

    // -------------------------
    // A: fragment wide requests
    // -------------------------
    assign src_a_ready_o = !a_busy_q;
    assign sink_a_valid_o = a_busy_q;

    always_comb begin
        a_fragment         = '0;
        a_fragment.opcode  = req_q.opcode;
        a_fragment.param   = req_q.param;
        a_fragment.size    = req_q.size;
        a_fragment.source  = req_q.source;
        a_fragment.address = req_q.address;
        a_fragment.mask    = req_q.mask[a_idx_q*(SINK_DATA_BITS/8) +: (SINK_DATA_BITS/8)];
        a_fragment.data    = req_q.data[a_idx_q*SINK_DATA_BITS +: SINK_DATA_BITS];
    end

    assign sink_a_req_o = sink_a_valid_o ? a_fragment : '0;

    always_comb begin
        req_n     = req_q;
        a_idx_n   = a_idx_q;
        a_total_n = a_total_q;
        a_busy_n  = a_busy_q;

        if (src_a_fire) begin
            req_n     = src_a_req_i;
            a_idx_n   = '0;
            a_total_n = (src_a_req_i.opcode == tilelink::GET) ? 1 : beats_for_size(src_a_req_i.size);
            a_busy_n  = 1'b1;
        end

        if (sink_a_fire) begin
            if (a_idx_q + 1 >= a_total_q) begin
                req_n     = '0;
                a_idx_n   = '0;
                a_total_n = '0;
                a_busy_n  = 1'b0;
            end else begin
                a_idx_n = a_idx_q + 1'b1;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            req_q     <= '0;
            a_idx_q   <= '0;
            a_total_q <= '0;
            a_busy_q  <= 1'b0;
        end else begin
            req_q     <= req_n;
            a_idx_q   <= a_idx_n;
            a_total_q <= a_total_n;
            a_busy_q  <= a_busy_n;
        end
    end

    // -----------------------------
    // D: assemble narrow responses
    // -----------------------------
    assign sink_d_ready_o = !d_busy_q || (d_busy_q && (d_idx_q + 1 < d_total_q));
    assign src_d_valid_o  = d_busy_q && (d_idx_q + 1 >= d_total_q);
    assign src_d_resp_o   = src_d_valid_o ? resp_q : '0;

    always_comb begin
        resp_n    = resp_q;
        d_idx_n   = d_idx_q;
        d_total_n = d_total_q;
        d_busy_n  = d_busy_q;

        if (sink_d_fire) begin
            if (!d_busy_q) begin
                resp_n          = '0;
                resp_n.opcode   = sink_d_resp_i.opcode;
                resp_n.param    = sink_d_resp_i.param;
                resp_n.size     = sink_d_resp_i.size;
                resp_n.source   = sink_d_resp_i.source;
                resp_n.denied   = sink_d_resp_i.denied;
                resp_n.corrupt  = sink_d_resp_i.corrupt;
                resp_n.data[SINK_DATA_BITS-1:0] = sink_d_resp_i.data;
                d_idx_n         = '0;
                d_total_n       = (sink_d_resp_i.opcode == tilelink::ACCESSACKDATA) ? beats_for_size(sink_d_resp_i.size) : 1;
                d_busy_n        = 1'b1;
            end else begin
                d_idx_n = d_idx_q + 1'b1;
                resp_n.data[(d_idx_q + 1)*SINK_DATA_BITS +: SINK_DATA_BITS] = sink_d_resp_i.data;
                resp_n.denied  = resp_q.denied  | sink_d_resp_i.denied;
                resp_n.corrupt = resp_q.corrupt | sink_d_resp_i.corrupt;
            end
        end

        if (src_d_fire) begin
            resp_n    = '0;
            d_idx_n   = '0;
            d_total_n = '0;
            d_busy_n  = 1'b0;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            resp_q    <= '0;
            d_idx_q   <= '0;
            d_total_q <= '0;
            d_busy_q  <= 1'b0;
        end else begin
            resp_q    <= resp_n;
            d_idx_q   <= d_idx_n;
            d_total_q <= d_total_n;
            d_busy_q  <= d_busy_n;
        end
    end

endmodule
