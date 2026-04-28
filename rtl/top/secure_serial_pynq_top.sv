`timescale 1ns/1ps

module secure_serial_pynq_top #(
    // Keep internal address width at 56 unless all submodules are parameter-safe
    // for smaller PLEN values.
    parameter int PLEN           = 56,
    parameter int CACHELINE_BITS = 512,
    parameter int VERSION_W      = 64,
    parameter int TAG_W          = 128,
    parameter int MARY           = 8,

    // Internal RAM depth = 2^MEM_AW cache lines.
    // MEM_AW=6 gives 64 lines × 512b = 32768 bits per RAM.
    parameter int MEM_AW         = 6
) (
    input  logic       clk_i,
    input  logic       rst_ni,

    input  logic       start_i,
    input  logic       write_i,
    input  logic [7:0] sw_i,

    output logic [7:0] led_o
);

    localparam logic [PLEN-1:0] DEFAULT_MASK = {PLEN{1'b1}};
    localparam logic [PLEN-1:0] DEFAULT_BASE = '0;

    typedef enum logic [2:0] {
        TOP_IDLE,
        TOP_ISSUE,
        TOP_WAIT,
        TOP_DONE
    } top_state_e;

    top_state_e state_q, state_n;

    logic [7:0]  addr_i;
    logic [31:0] wdata_seed_i;

    assign addr_i       = sw_i;
    assign wdata_seed_i = {24'h0, sw_i};

    logic                      req_valid;
    logic                      req_ready;
    logic                      req_write;
    logic [PLEN-1:0]           req_addr;
    logic [PLEN-1:0]           req_mask;
    logic [PLEN-1:0]           req_base;
    logic [CACHELINE_BITS-1:0] req_wdata;

    logic                      rsp_valid;
    logic                      rsp_ready;
    logic [CACHELINE_BITS-1:0] rsp_rdata;
    logic                      rsp_corrupt;

    logic [CACHELINE_BITS-1:0] rsp_rdata_q, rsp_rdata_n;
    logic                      rsp_corrupt_q, rsp_corrupt_n;
    logic [31:0]               op_count_q, op_count_n;

    // -------------------------------------------------------------------------
    // Internal protected data memory interface
    // -------------------------------------------------------------------------
    logic                      data_mem_req_valid;
    logic                      data_mem_req_ready;
    logic                      data_mem_req_write;
    logic [PLEN-1:0]           data_mem_req_addr;
    logic [CACHELINE_BITS-1:0] data_mem_req_wdata;
    logic                      data_mem_rsp_valid;
    logic [CACHELINE_BITS-1:0] data_mem_rsp_data;
    logic                      data_mem_rsp_error;

    // -------------------------------------------------------------------------
    // Internal metadata memory interface
    // -------------------------------------------------------------------------
    logic                      meta_mem_req_valid;
    logic                      meta_mem_req_ready;
    logic                      meta_mem_req_write;
    logic [PLEN-1:0]           meta_mem_req_addr;
    logic [CACHELINE_BITS-1:0] meta_mem_req_wdata;
    logic                      meta_mem_rsp_valid;
    logic [CACHELINE_BITS-1:0] meta_mem_rsp_data;
    logic                      meta_mem_rsp_error;

    secure_memory_controller_serial_bmt #(
        .PLEN           (PLEN),
        .CACHELINE_BITS (CACHELINE_BITS),
        .VERSION_W      (VERSION_W),
        .TAG_W          (TAG_W),
        .MARY           (MARY)
    ) u_secure_controller (
        .clk_i                 (clk_i),
        .rst_ni                (rst_ni),

        .req_valid_i           (req_valid),
        .req_ready_o           (req_ready),
        .req_write_i           (req_write),
        .req_addr_i            (req_addr),
        .req_mask_i            (req_mask),
        .req_base_i            (req_base),
        .req_wdata_i           (req_wdata),

        .rsp_valid_o           (rsp_valid),
        .rsp_ready_i           (rsp_ready),
        .rsp_rdata_o           (rsp_rdata),
        .rsp_corrupt_o         (rsp_corrupt),

        .data_mem_req_valid_o  (data_mem_req_valid),
        .data_mem_req_ready_i  (data_mem_req_ready),
        .data_mem_req_write_o  (data_mem_req_write),
        .data_mem_req_addr_o   (data_mem_req_addr),
        .data_mem_req_wdata_o  (data_mem_req_wdata),
        .data_mem_rsp_valid_i  (data_mem_rsp_valid),
        .data_mem_rsp_data_i   (data_mem_rsp_data),
        .data_mem_rsp_error_i  (data_mem_rsp_error),

        .meta_mem_req_valid_o  (meta_mem_req_valid),
        .meta_mem_req_ready_i  (meta_mem_req_ready),
        .meta_mem_req_write_o  (meta_mem_req_write),
        .meta_mem_req_addr_o   (meta_mem_req_addr),
        .meta_mem_req_wdata_o  (meta_mem_req_wdata),
        .meta_mem_rsp_valid_i  (meta_mem_rsp_valid),
        .meta_mem_rsp_data_i   (meta_mem_rsp_data),
        .meta_mem_rsp_error_i  (meta_mem_rsp_error)
    );

    // -------------------------------------------------------------------------
    // Internal protected data RAM
    //
    // BRAM-safe style:
    //   - synchronous process only
    //   - no async reset sensitivity on the memory process
    //   - reset only response registers, not the RAM array
    // -------------------------------------------------------------------------
    (* ram_style = "block" *)
    logic [CACHELINE_BITS-1:0] data_ram [0:(1 << MEM_AW)-1];

    logic [MEM_AW-1:0] data_idx;

    assign data_idx = data_mem_req_addr[MEM_AW+5:6];

    assign data_mem_req_ready = 1'b1;
    assign data_mem_rsp_error = 1'b0;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            data_mem_rsp_valid <= 1'b0;
            data_mem_rsp_data  <= '0;
        end else begin
            data_mem_rsp_valid <= 1'b0;

            if (data_mem_req_valid && data_mem_req_ready) begin
                data_mem_rsp_valid <= 1'b1;

                if (data_mem_req_write) begin
                    data_ram[data_idx] <= data_mem_req_wdata;
                    data_mem_rsp_data  <= '0;
                end else begin
                    data_mem_rsp_data <= data_ram[data_idx];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Internal metadata RAM
    //
    // Same BRAM-safe style as data RAM.
    // -------------------------------------------------------------------------
    (* ram_style = "block" *)
    logic [CACHELINE_BITS-1:0] meta_ram [0:(1 << MEM_AW)-1];

    logic [MEM_AW-1:0] meta_idx;

    assign meta_idx = meta_mem_req_addr[MEM_AW+5:6];

    assign meta_mem_req_ready = 1'b1;
    assign meta_mem_rsp_error = 1'b0;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            meta_mem_rsp_valid <= 1'b0;
            meta_mem_rsp_data  <= '0;
        end else begin
            meta_mem_rsp_valid <= 1'b0;

            if (meta_mem_req_valid && meta_mem_req_ready) begin
                meta_mem_rsp_valid <= 1'b1;

                if (meta_mem_req_write) begin
                    meta_ram[meta_idx] <= meta_mem_req_wdata;
                    meta_mem_rsp_data  <= '0;
                end else begin
                    meta_mem_rsp_data <= meta_ram[meta_idx];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Board-facing request generator
    //
    // sw_i selects:
    //   addr_i       = sw_i
    //   wdata_seed_i = zero-extended sw_i
    //
    // start_i pulses/holds request issue.
    // write_i selects write/read.
    // -------------------------------------------------------------------------
    always_comb begin
        state_n       = state_q;
        rsp_rdata_n   = rsp_rdata_q;
        rsp_corrupt_n = rsp_corrupt_q;
        op_count_n    = op_count_q;

        req_valid = 1'b0;
        req_write = write_i;

        // sw_i selects a 64-byte cache line.
        // Low 6 address bits are zero because 512b = 64B.
        req_addr = {{(PLEN-14){1'b0}}, addr_i, 6'b0};

        req_mask = DEFAULT_MASK;
        req_base = DEFAULT_BASE;

        // Expand a 32-bit seed into the 512-bit cache line.
        req_wdata = {16{wdata_seed_i}};

        rsp_ready = 1'b1;

        unique case (state_q)
            TOP_IDLE: begin
                if (start_i) begin
                    state_n = TOP_ISSUE;
                end
            end

            TOP_ISSUE: begin
                req_valid = 1'b1;
                if (req_ready) begin
                    state_n = TOP_WAIT;
                end
            end

            TOP_WAIT: begin
                if (rsp_valid) begin
                    rsp_rdata_n   = rsp_rdata;
                    rsp_corrupt_n = rsp_corrupt;
                    op_count_n    = op_count_q + 1'b1;
                    state_n       = TOP_DONE;
                end
            end

            TOP_DONE: begin
                if (!start_i) begin
                    state_n = TOP_IDLE;
                end
            end

            default: begin
                state_n = TOP_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q       <= TOP_IDLE;
            rsp_rdata_q   <= '0;
            rsp_corrupt_q <= 1'b0;
            op_count_q    <= '0;
        end else begin
            state_q       <= state_n;
            rsp_rdata_q   <= rsp_rdata_n;
            rsp_corrupt_q <= rsp_corrupt_n;
            op_count_q    <= op_count_n;
        end
    end

    // -------------------------------------------------------------------------
    // Compact LED/status output
    // -------------------------------------------------------------------------
    logic busy;
    logic done;

    assign busy = (state_q != TOP_IDLE) && (state_q != TOP_DONE);
    assign done = (state_q == TOP_DONE);

    assign led_o = {
        rsp_corrupt_q,      // LED7: integrity/memory error/corrupt
        done,               // LED6: operation complete
        busy,               // LED5: operation in progress
        write_i,            // LED4: current requested op type
        state_q[2:0],       // LED3:1: wrapper FSM state
        rsp_rdata_q[0]      // LED0: readback/debug data bit
    };

endmodule