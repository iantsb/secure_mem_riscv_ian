`default_nettype wire

import tilelink::*;

module ztlassembler #(
    parameter int SRC_DATA_WIDTH  = 64,
    parameter int SINK_DATA_WIDTH = 512,
    parameter int SIZE_WIDTH      = 3,
    parameter int SOURCE_WIDTH    = 8
) (
    input logic clk_i,
    input logic rst_ni,

    // Upstream/source A channel, narrow side.
    output logic src_a_ready_o,
    input  logic src_a_valid_i,
    input  ChannelA#(
        .DATA_WIDTH(SRC_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::a_req_t src_a_req_i,

    // Downstream/sink A channel, wide side.
    input  logic sink_a_ready_i,
    output logic sink_a_valid_o,
    output ChannelA#(
        .DATA_WIDTH(SINK_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::a_req_t sink_a_req_o,

    // Upstream/source D channel, narrow side.
    input  logic src_d_ready_i,
    output logic src_d_valid_o,
    output ChannelD#(
        .DATA_WIDTH(SRC_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::d_resp_t src_d_resp_o,

    // Downstream/sink D channel, wide side.
    output logic sink_d_ready_o,
    input  logic sink_d_valid_i,
    input  ChannelD#(
        .DATA_WIDTH(SINK_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::d_resp_t sink_d_resp_i
);

    localparam int _check_divisible = 1 / ((SINK_DATA_WIDTH % SRC_DATA_WIDTH) == 0 ? 1 : 0);
    localparam int RATIO            = SINK_DATA_WIDTH / SRC_DATA_WIDTH;
    localparam int COUNT_WIDTH      = (RATIO <= 2) ? 1 : $clog2(RATIO);

    typedef ChannelA#(
        .DATA_WIDTH(SINK_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::a_req_t wide_a_t;

    typedef ChannelD#(
        .DATA_WIDTH(SINK_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::d_resp_t wide_d_t;

    typedef ChannelD#(
        .DATA_WIDTH(SRC_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH),
        .SOURCE_WIDTH(SOURCE_WIDTH)
    )::d_resp_t narrow_d_t;

    wide_a_t req_q, req_n;
    logic [COUNT_WIDTH-1:0] a_idx_q, a_idx_n;
    logic [COUNT_WIDTH:0]   a_total_q, a_total_n;
    logic                   a_busy_q, a_busy_n;
    logic                   sink_a_fire;

    wide_d_t resp_q, resp_n;
    logic [COUNT_WIDTH-1:0] d_idx_q, d_idx_n;
    logic [COUNT_WIDTH:0]   d_total_q, d_total_n;
    logic                   d_busy_q, d_busy_n;
    narrow_d_t              d_fragment;
    logic                   src_d_fire;
    logic                   sink_d_fire;

    function automatic logic [COUNT_WIDTH:0] beats_for_size(input logic [SIZE_WIDTH-1:0] size);
        int unsigned bytes;
        int unsigned beats;
        begin
            bytes = (1 << size);
            beats = (bytes + (SRC_DATA_WIDTH/8) - 1) / (SRC_DATA_WIDTH/8);
            if (beats < 1) beats = 1;
            if (beats > RATIO) beats = RATIO;
            beats_for_size = beats[COUNT_WIDTH:0];
        end
    endfunction

    assign sink_a_fire = sink_a_valid_o && sink_a_ready_i;
    assign sink_d_fire = sink_d_valid_i && sink_d_ready_o;
    assign src_d_fire  = src_d_valid_o  && src_d_ready_i;

    // -------------------------
    // A: assemble narrow writes
    // -------------------------
    assign src_a_ready_o  = !a_busy_q || (a_busy_q && (a_idx_q + 1 < a_total_q));
    assign sink_a_valid_o = a_busy_q && (a_idx_q + 1 >= a_total_q);
    assign sink_a_req_o   = sink_a_valid_o ? req_q : '0;

    always_comb begin
        req_n     = req_q;
        a_idx_n   = a_idx_q;
        a_total_n = a_total_q;
        a_busy_n  = a_busy_q;

        if (src_a_valid_i && src_a_ready_o) begin
            if (!a_busy_q) begin
                req_n          = '0;
                req_n.opcode   = src_a_req_i.opcode;
                req_n.param    = src_a_req_i.param;
                req_n.size     = src_a_req_i.size;
                req_n.source   = src_a_req_i.source;
                req_n.address  = src_a_req_i.address;
                req_n.mask     = '0;
                req_n.mask[(SRC_DATA_WIDTH/8)-1:0] = src_a_req_i.mask;
                req_n.data[SRC_DATA_WIDTH-1:0] = src_a_req_i.data;
                a_idx_n        = '0;
                a_total_n      = (src_a_req_i.opcode == tilelink::GET) ? 1 : beats_for_size(src_a_req_i.size);
                a_busy_n       = 1'b1;
            end else begin
                a_idx_n = a_idx_q + 1'b1;
                req_n.mask[(a_idx_q + 1)*(SRC_DATA_WIDTH/8) +: (SRC_DATA_WIDTH/8)] = src_a_req_i.mask;
                req_n.data[(a_idx_q + 1)*SRC_DATA_WIDTH +: SRC_DATA_WIDTH] = src_a_req_i.data;
            end
        end

        if (sink_a_fire) begin
            req_n     = '0;
            a_idx_n   = '0;
            a_total_n = '0;
            a_busy_n  = 1'b0;
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

    // ---------------------------
    // D: fragment wide read data
    // ---------------------------
    assign sink_d_ready_o = !d_busy_q;
    assign src_d_valid_o  = d_busy_q;

    always_comb begin
        d_fragment         = '0;
        d_fragment.opcode  = resp_q.opcode;
        d_fragment.param   = resp_q.param;
        d_fragment.size    = resp_q.size;
        d_fragment.source  = resp_q.source;
        d_fragment.denied  = resp_q.denied;
        d_fragment.corrupt = resp_q.corrupt;
        d_fragment.data    = resp_q.data[d_idx_q*SRC_DATA_WIDTH +: SRC_DATA_WIDTH];
    end

    assign src_d_resp_o = src_d_valid_o ? d_fragment : '0;

    always_comb begin
        resp_n    = resp_q;
        d_idx_n   = d_idx_q;
        d_total_n = d_total_q;
        d_busy_n  = d_busy_q;

        if (sink_d_fire) begin
            resp_n    = sink_d_resp_i;
            d_idx_n   = '0;
            d_total_n = (sink_d_resp_i.opcode == tilelink::ACCESSACKDATA) ? beats_for_size(sink_d_resp_i.size) : 1;
            d_busy_n  = 1'b1;
        end

        if (src_d_fire) begin
            if (d_idx_q + 1 >= d_total_q) begin
                resp_n    = '0;
                d_idx_n   = '0;
                d_total_n = '0;
                d_busy_n  = 1'b0;
            end else begin
                d_idx_n = d_idx_q + 1'b1;
            end
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
