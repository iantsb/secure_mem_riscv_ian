`timescale 1ns/1ps

module tb_metadata_counter_allocator;
  localparam int CACHELINE_BITS = 512;
  localparam int VERSION_W      = 64;

  logic [CACHELINE_BITS-1:0] line_i;
  logic [2:0]                lane_i;
  logic                      alloc_i;
  logic [CACHELINE_BITS-1:0] line_o;
  logic [VERSION_W-1:0]      old_version_o;
  logic [VERSION_W-1:0]      new_version_o;
  logic                      overflow_o;

  metadata_counter_allocator #(
    .CACHELINE_BITS(CACHELINE_BITS),
    .VERSION_W(VERSION_W)
  ) dut (
    .line_i(line_i),
    .lane_i(lane_i),
    .alloc_i(alloc_i),
    .line_o(line_o),
    .old_version_o(old_version_o),
    .new_version_o(new_version_o),
    .overflow_o(overflow_o)
  );

  initial begin
    line_i  = '0;
    lane_i  = 3'd0;
    alloc_i = 1'b1;
    #1;
    if (old_version_o !== 64'd0 || new_version_o !== 64'd1 || overflow_o) begin
      $fatal(1, "Initial allocation failed");
    end
    if (line_o[63:0] !== 64'd1) $fatal(1, "Lane 0 was not updated to 1");

    line_i = line_o;
    #1;
    if (old_version_o !== 64'd1 || new_version_o !== 64'd2 || overflow_o) begin
      $fatal(1, "Second allocation failed");
    end

    line_i = '0;
    lane_i = 3'd3;
    line_i[3*64 +: 64] = {64{1'b1}};
    #1;
    if (!overflow_o) $fatal(1, "Overflow was not detected");
    if (line_o !== line_i) $fatal(1, "Line changed on overflow");

    alloc_i = 1'b0;
    line_i = '0;
    lane_i = 3'd2;
    #1;
    if (line_o !== line_i) $fatal(1, "Line changed while alloc_i=0");

    $display("PASS: tb_metadata_counter_allocator completed");
    $finish;
  end
endmodule
