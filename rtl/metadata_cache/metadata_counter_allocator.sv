`timescale 1ns/1ps

// Allocates the next metadata version/counter value for AES-CTR/BMT use.
//
// Policy for the initial functional implementation:
//   * version == counter
//   * stored value 0 means uninitialized/never allocated
//   * first allocation returns 1
//   * later allocations return old + 1
//   * all-ones old value is overflow and is not allowed to wrap
//
// The allocator operates on one VERSION_W lane inside a CACHELINE_BITS metadata
// line and returns the modified metadata line plus the allocated version.
module metadata_counter_allocator #(
  parameter int CACHELINE_BITS = 512,
  parameter int VERSION_W      = 64
) (
  input  logic [CACHELINE_BITS-1:0] line_i,
  input  logic [2:0]                lane_i,
  input  logic                      alloc_i,

  output logic [CACHELINE_BITS-1:0] line_o,
  output logic [VERSION_W-1:0]      old_version_o,
  output logic [VERSION_W-1:0]      new_version_o,
  output logic                      overflow_o
);

  logic [VERSION_W-1:0] old_version;
  logic [VERSION_W-1:0] new_version;

  always_comb begin
    old_version = line_i[lane_i*VERSION_W +: VERSION_W];
    overflow_o  = alloc_i && (&old_version);

    // If old_version is 0, this also produces 1. Keeping the explicit policy
    // here documents that 0 is reserved for uninitialized metadata.
    if (old_version == '0) begin
      new_version = {{(VERSION_W-1){1'b0}}, 1'b1};
    end else begin
      new_version = old_version + {{(VERSION_W-1){1'b0}}, 1'b1};
    end

    line_o = line_i;
    if (alloc_i && !overflow_o) begin
      line_o[lane_i*VERSION_W +: VERSION_W] = new_version;
    end
  end

  assign old_version_o = old_version;
  assign new_version_o = new_version;

endmodule
