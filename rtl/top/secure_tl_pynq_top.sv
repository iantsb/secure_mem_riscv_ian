`timescale 1ns/1ps
`default_nettype wire

import tilelink::*;

module secure_tl_pynq_top #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = build_config_pkg::build_config,

    // Internal downstream RAM depth = 2^MEM_AW 64-bit beats.
    parameter int MEM_AW = 10
) (
    input  logic       clock,
    input  logic       reset,

    // Board/debug controls.
    input  logic       start_i,
    input  logic       write_i,
    input  logic       cfg_i,
    input  logic [7:0] sw_i,

    output logic [7:0] led_o
);

    localparam int TL_DATA_W  = ROCKETCfg.TL_DATA_WIDTH;
    localparam int TL_BYTES   = TL_DATA_W / 8;

    // -------------------------------------------------------------------------
    // Input synchronizers
    // -------------------------------------------------------------------------
    logic       start_meta, start_sync, start_sync_q;
    logic       write_meta, write_sync;
    logic       cfg_meta, cfg_sync;
    logic [7:0] sw_meta, sw_sync;

    always_ff @(posedge clock) begin
        if (reset) begin
            start_meta  <= 1'b0;
            start_sync  <= 1'b0;
            start_sync_q<= 1'b0;
            write_meta  <= 1'b0;
            write_sync  <= 1'b0;
            cfg_meta    <= 1'b0;
            cfg_sync    <= 1'b0;
            sw_meta     <= '0;
            sw_sync     <= '0;
        end else begin
            start_meta   <= start_i;
            start_sync   <= start_meta;
            start_sync_q <= start_sync;

            write_meta   <= write_i;
            write_sync   <= write_meta;

            cfg_meta     <= cfg_i;
            cfg_sync     <= cfg_meta;

            sw_meta      <= sw_i;
            sw_sync      <= sw_meta;
        end
    end

    wire start_pulse = start_sync && !start_sync_q;

    // -------------------------------------------------------------------------
    // Flattened TileLink wires into MemoryControllerWrapperTL
    // -------------------------------------------------------------------------

    // Control TileLink A input
    logic        auto_ctl_in_a_ready;
    logic        auto_ctl_in_a_valid;
    logic [2:0]  auto_ctl_in_a_bits_opcode;
    logic [1:0]  auto_ctl_in_a_bits_size;
    logic [9:0]  auto_ctl_in_a_bits_source;
    logic [25:0] auto_ctl_in_a_bits_address;
    logic [7:0]  auto_ctl_in_a_bits_mask;
    logic [63:0] auto_ctl_in_a_bits_data;

    // Control TileLink D output
    logic        auto_ctl_in_d_ready;
    logic        auto_ctl_in_d_valid;
    logic [2:0]  auto_ctl_in_d_bits_opcode;
    logic [2:0]  auto_ctl_in_d_bits_param;
    logic [1:0]  auto_ctl_in_d_bits_size;
    logic [9:0]  auto_ctl_in_d_bits_source;
    logic        auto_ctl_in_d_bits_denied;
    logic [TL_DATA_W-1:0] auto_ctl_in_d_bits_data;
    logic        auto_ctl_in_d_bits_corrupt;

    // Source TileLink A input from synthetic board request generator
    logic        auto_in_a_ready;
    logic        auto_in_a_valid;
    logic [2:0]  auto_in_a_bits_opcode;
    logic [2:0]  auto_in_a_bits_size;
    logic [7:0]  auto_in_a_bits_source;
    logic [33:0] auto_in_a_bits_address;
    logic [7:0]  auto_in_a_bits_mask;
    logic [TL_DATA_W-1:0] auto_in_a_bits_data;

    // Source TileLink D output back to synthetic board requester
    logic        auto_in_d_ready;
    logic        auto_in_d_valid;
    logic [2:0]  auto_in_d_bits_opcode;
    logic [2:0]  auto_in_d_bits_param;
    logic [2:0]  auto_in_d_bits_size;
    logic [7:0]  auto_in_d_bits_source;
    logic        auto_in_d_bits_denied;
    logic [TL_DATA_W-1:0] auto_in_d_bits_data;
    logic        auto_in_d_bits_corrupt;

    // Sink TileLink A output toward internal RAM
    logic        auto_out_a_ready;
    logic        auto_out_a_valid;
    logic [2:0]  auto_out_a_bits_opcode;
    logic [2:0]  auto_out_a_bits_param;
    logic [2:0]  auto_out_a_bits_size;
    logic [9:0]  auto_out_a_bits_source;
    logic [33:0] auto_out_a_bits_address;
    logic [7:0]  auto_out_a_bits_mask;
    logic [TL_DATA_W-1:0] auto_out_a_bits_data;

    // Sink TileLink D input from internal RAM
    logic        auto_out_d_ready;
    logic        auto_out_d_valid;
    logic [2:0]  auto_out_d_bits_opcode;
    logic [2:0]  auto_out_d_bits_param;
    logic [2:0]  auto_out_d_bits_size;
    logic [9:0]  auto_out_d_bits_source;
    logic        auto_out_d_bits_denied;
    logic [TL_DATA_W-1:0] auto_out_d_bits_data;
    logic        auto_out_d_bits_corrupt;

    MemoryControllerWrapperTL #(
        .ROCKETCfg(ROCKETCfg)
    ) u_tl_wrapper (
        .clock(clock),
        .reset(reset),

        .auto_ctl_in_a_ready        (auto_ctl_in_a_ready),
        .auto_ctl_in_a_valid        (auto_ctl_in_a_valid),
        .auto_ctl_in_a_bits_opcode  (auto_ctl_in_a_bits_opcode),
        .auto_ctl_in_a_bits_size    (auto_ctl_in_a_bits_size),
        .auto_ctl_in_a_bits_source  (auto_ctl_in_a_bits_source),
        .auto_ctl_in_a_bits_address (auto_ctl_in_a_bits_address),
        .auto_ctl_in_a_bits_mask    (auto_ctl_in_a_bits_mask),
        .auto_ctl_in_a_bits_data    (auto_ctl_in_a_bits_data),

        .auto_ctl_in_d_ready        (auto_ctl_in_d_ready),
        .auto_ctl_in_d_valid        (auto_ctl_in_d_valid),
        .auto_ctl_in_d_bits_opcode  (auto_ctl_in_d_bits_opcode),
        .auto_ctl_in_d_bits_param   (auto_ctl_in_d_bits_param),
        .auto_ctl_in_d_bits_size    (auto_ctl_in_d_bits_size),
        .auto_ctl_in_d_bits_source  (auto_ctl_in_d_bits_source),
        .auto_ctl_in_d_bits_denied  (auto_ctl_in_d_bits_denied),
        .auto_ctl_in_d_bits_data    (auto_ctl_in_d_bits_data),
        .auto_ctl_in_d_bits_corrupt (auto_ctl_in_d_bits_corrupt),

        .auto_in_a_ready            (auto_in_a_ready),
        .auto_in_a_valid            (auto_in_a_valid),
        .auto_in_a_bits_opcode      (auto_in_a_bits_opcode),
        .auto_in_a_bits_size        (auto_in_a_bits_size),
        .auto_in_a_bits_source      (auto_in_a_bits_source),
        .auto_in_a_bits_address     (auto_in_a_bits_address),
        .auto_in_a_bits_mask        (auto_in_a_bits_mask),
        .auto_in_a_bits_data        (auto_in_a_bits_data),

        .auto_in_d_ready            (auto_in_d_ready),
        .auto_in_d_valid            (auto_in_d_valid),
        .auto_in_d_bits_opcode      (auto_in_d_bits_opcode),
        .auto_in_d_bits_param       (auto_in_d_bits_param),
        .auto_in_d_bits_size        (auto_in_d_bits_size),
        .auto_in_d_bits_source      (auto_in_d_bits_source),
        .auto_in_d_bits_denied      (auto_in_d_bits_denied),
        .auto_in_d_bits_data        (auto_in_d_bits_data),
        .auto_in_d_bits_corrupt     (auto_in_d_bits_corrupt),

        .auto_out_a_ready           (auto_out_a_ready),
        .auto_out_a_valid           (auto_out_a_valid),
        .auto_out_a_bits_opcode     (auto_out_a_bits_opcode),
        .auto_out_a_bits_param      (auto_out_a_bits_param),
        .auto_out_a_bits_size       (auto_out_a_bits_size),
        .auto_out_a_bits_source     (auto_out_a_bits_source),
        .auto_out_a_bits_address    (auto_out_a_bits_address),
        .auto_out_a_bits_mask       (auto_out_a_bits_mask),
        .auto_out_a_bits_data       (auto_out_a_bits_data),

        .auto_out_d_ready           (auto_out_d_ready),
        .auto_out_d_valid           (auto_out_d_valid),
        .auto_out_d_bits_opcode     (auto_out_d_bits_opcode),
        .auto_out_d_bits_param      (auto_out_d_bits_param),
        .auto_out_d_bits_size       (auto_out_d_bits_size),
        .auto_out_d_bits_source     (auto_out_d_bits_source),
        .auto_out_d_bits_denied     (auto_out_d_bits_denied),
        .auto_out_d_bits_data       (auto_out_d_bits_data),
        .auto_out_d_bits_corrupt    (auto_out_d_bits_corrupt)
    );

    // -------------------------------------------------------------------------
    // Board request FSM
    //
    // cfg_i = 0:
    //   start_i issues a memory GET/PUT through auto_in_*
    //
    // cfg_i = 1:
    //   start_i issues one control-port CSR-like write through auto_ctl_in_*
    //
    // This keeps the control path dynamic so the secure path is less likely to be
    // optimized away during implementation.
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        TOP_IDLE,
        TOP_MEM_ISSUE,
        TOP_MEM_WAIT,
        TOP_CTL_ISSUE,
        TOP_CTL_WAIT,
        TOP_DONE
    } top_state_e;

    top_state_e top_state_q, top_state_n;

    logic [TL_DATA_W-1:0] rsp_data_q, rsp_data_n;
    logic                 rsp_denied_q, rsp_denied_n;
    logic                 rsp_corrupt_q, rsp_corrupt_n;
    logic [31:0]          op_count_q, op_count_n;

    always_comb begin
        top_state_n  = top_state_q;
        rsp_data_n   = rsp_data_q;
        rsp_denied_n = rsp_denied_q;
        rsp_corrupt_n= rsp_corrupt_q;
        op_count_n   = op_count_q;

        // Default no control request.
        auto_ctl_in_a_valid        = 1'b0;
        auto_ctl_in_a_bits_opcode  = tilelink::PUTFULLDATA;
        auto_ctl_in_a_bits_size    = 2'd3;
        auto_ctl_in_a_bits_source  = 10'h001;
        auto_ctl_in_a_bits_address = {18'h0, sw_sync};
        auto_ctl_in_a_bits_mask    = 8'hff;
        auto_ctl_in_a_bits_data    = {56'h0, sw_sync};
        auto_ctl_in_d_ready        = 1'b1;

        // Default no memory request.
        auto_in_a_valid        = 1'b0;
        auto_in_a_bits_opcode  = write_sync ? tilelink::PUTFULLDATA : tilelink::GET;
        auto_in_a_bits_size    = 3'd3;                 // 8 bytes
        auto_in_a_bits_source  = 8'h01;
        auto_in_a_bits_address = {23'h0, sw_sync, 3'b000};
        auto_in_a_bits_mask    = 8'hff;
        auto_in_a_bits_data    = {8{sw_sync}};
        auto_in_d_ready        = 1'b1;

        unique case (top_state_q)
            TOP_IDLE: begin
                if (start_pulse) begin
                    if (cfg_sync) begin
                        top_state_n = TOP_CTL_ISSUE;
                    end else begin
                        top_state_n = TOP_MEM_ISSUE;
                    end
                end
            end

            TOP_CTL_ISSUE: begin
                auto_ctl_in_a_valid = 1'b1;
                if (auto_ctl_in_a_ready) begin
                    top_state_n = TOP_CTL_WAIT;
                end
            end

            TOP_CTL_WAIT: begin
                if (auto_ctl_in_d_valid) begin
                    rsp_data_n    = auto_ctl_in_d_bits_data;
                    rsp_denied_n  = auto_ctl_in_d_bits_denied;
                    rsp_corrupt_n = auto_ctl_in_d_bits_corrupt;
                    op_count_n    = op_count_q + 1'b1;
                    top_state_n   = TOP_DONE;
                end
            end

            TOP_MEM_ISSUE: begin
                auto_in_a_valid = 1'b1;
                if (auto_in_a_ready) begin
                    top_state_n = TOP_MEM_WAIT;
                end
            end

            TOP_MEM_WAIT: begin
                if (auto_in_d_valid) begin
                    rsp_data_n    = auto_in_d_bits_data;
                    rsp_denied_n  = auto_in_d_bits_denied;
                    rsp_corrupt_n = auto_in_d_bits_corrupt;
                    op_count_n    = op_count_q + 1'b1;
                    top_state_n   = TOP_DONE;
                end
            end

            TOP_DONE: begin
                if (!start_sync) begin
                    top_state_n = TOP_IDLE;
                end
            end

            default: begin
                top_state_n = TOP_IDLE;
            end
        endcase
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            top_state_q   <= TOP_IDLE;
            rsp_data_q    <= '0;
            rsp_denied_q  <= 1'b0;
            rsp_corrupt_q <= 1'b0;
            op_count_q    <= '0;
        end else begin
            top_state_q   <= top_state_n;
            rsp_data_q    <= rsp_data_n;
            rsp_denied_q  <= rsp_denied_n;
            rsp_corrupt_q <= rsp_corrupt_n;
            op_count_q    <= op_count_n;
        end
    end

    // -------------------------------------------------------------------------
    // Internal downstream TileLink RAM
    //
    // This is a simple one-cycle response memory for implementation/debug.
    // It replaces the external TL-to-AXI/RAM path for the PYNQ implementation
    // target.
    // -------------------------------------------------------------------------
    (* ram_style = "block" *)
    logic [TL_DATA_W-1:0] ram [0:(1 << MEM_AW)-1];

    logic [MEM_AW-1:0] ram_idx;
    logic              out_a_fire;

    assign ram_idx          = auto_out_a_bits_address[MEM_AW+2:3];
    assign out_a_fire       = auto_out_a_valid && auto_out_a_ready;
    assign auto_out_a_ready = !auto_out_d_valid || auto_out_d_ready;

    always_ff @(posedge clock) begin
        if (reset) begin
            auto_out_d_valid        <= 1'b0;
            auto_out_d_bits_opcode  <= tilelink::ACCESSACKDATA;
            auto_out_d_bits_param   <= 3'b000;
            auto_out_d_bits_size    <= '0;
            auto_out_d_bits_source  <= '0;
            auto_out_d_bits_denied  <= 1'b0;
            auto_out_d_bits_data    <= '0;
            auto_out_d_bits_corrupt <= 1'b0;
        end else begin
            if (auto_out_d_valid && auto_out_d_ready && !out_a_fire) begin
                auto_out_d_valid <= 1'b0;
            end

            if (out_a_fire) begin
                auto_out_d_valid        <= 1'b1;
                auto_out_d_bits_param   <= 3'b000;
                auto_out_d_bits_size    <= auto_out_a_bits_size;
                auto_out_d_bits_source  <= auto_out_a_bits_source;
                auto_out_d_bits_denied  <= 1'b0;
                auto_out_d_bits_corrupt <= 1'b0;

                unique case (auto_out_a_bits_opcode)
                    tilelink::GET: begin
                        auto_out_d_bits_opcode <= tilelink::ACCESSACKDATA;
                        auto_out_d_bits_data   <= ram[ram_idx];
                    end

                    tilelink::PUTFULLDATA,
                    tilelink::PUTPARTIALDATA: begin
                        auto_out_d_bits_opcode <= tilelink::ACCESSACK;
                        auto_out_d_bits_data   <= '0;

                        for (int b = 0; b < TL_BYTES; b++) begin
                            if (auto_out_a_bits_mask[b]) begin
                                ram[ram_idx][8*b +: 8] <= auto_out_a_bits_data[8*b +: 8];
                            end
                        end
                    end

                    default: begin
                        auto_out_d_bits_opcode  <= tilelink::ACCESSACKDATA;
                        auto_out_d_bits_data    <= '0;
                        auto_out_d_bits_denied  <= 1'b1;
                        auto_out_d_bits_corrupt <= 1'b1;
                    end
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Compact LED/status output
    // -------------------------------------------------------------------------
    wire busy = (top_state_q != TOP_IDLE) && (top_state_q != TOP_DONE);
    wire done = (top_state_q == TOP_DONE);

    assign led_o = {
        rsp_corrupt_q,       // LED7
        rsp_denied_q,        // LED6
        done,                // LED5
        busy,                // LED4
        cfg_sync,            // LED3
        write_sync,          // LED2
        top_state_q[1],      // LED1
        rsp_data_q[0]        // LED0
    };

endmodule