`default_nettype wire

import riscv_::*;
import tilelink::*;

// TileLink wrapper around secure_memory_controller.
// This is based on the original MemoryControllerWrapper, with the missing
// TileLink D/A fields exposed as top-level ports for Vivado synthesis.
// It sits between the RocketChip memory bus and the downstream TL-to-AXI path.
module MemoryControllerWrapperTL #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = build_config_pkg::build_config
) (
    input  logic clock,
    input  logic reset,

    // Control TileLink A input
    output logic auto_ctl_in_a_ready,
    input  logic auto_ctl_in_a_valid,
    input  logic [2:0] auto_ctl_in_a_bits_opcode,
    input  logic [1:0] auto_ctl_in_a_bits_size,
    input  logic [9:0] auto_ctl_in_a_bits_source,
    input  logic [25:0] auto_ctl_in_a_bits_address,
    input  logic [7:0] auto_ctl_in_a_bits_mask,
    input  logic [63:0] auto_ctl_in_a_bits_data,

    // Control TileLink D output
    input  logic auto_ctl_in_d_ready,
    output logic auto_ctl_in_d_valid,
    output logic [2:0] auto_ctl_in_d_bits_opcode,
    output logic [2:0] auto_ctl_in_d_bits_param,
    output logic [1:0] auto_ctl_in_d_bits_size,
    output logic [9:0] auto_ctl_in_d_bits_source,
    output logic       auto_ctl_in_d_bits_denied,
    output logic [ROCKETCfg.TL_DATA_WIDTH-1:0] auto_ctl_in_d_bits_data,
    output logic       auto_ctl_in_d_bits_corrupt,

    // Source TileLink A input from RocketChip memory bus
    output logic auto_in_a_ready,
    input  logic auto_in_a_valid,
    input  logic [2:0] auto_in_a_bits_opcode,
    input  logic [2:0] auto_in_a_bits_size,
    input  logic [7:0] auto_in_a_bits_source,
    input  logic [33:0] auto_in_a_bits_address,
    input  logic [7:0] auto_in_a_bits_mask,
    input  logic [ROCKETCfg.TL_DATA_WIDTH-1:0] auto_in_a_bits_data,

    // Source TileLink D output back to RocketChip memory bus
    input  logic auto_in_d_ready,
    output logic auto_in_d_valid,
    output logic [2:0] auto_in_d_bits_opcode,
    output logic [2:0] auto_in_d_bits_param,
    output logic [2:0] auto_in_d_bits_size,
    output logic [7:0] auto_in_d_bits_source,
    output logic       auto_in_d_bits_denied,
    output logic [ROCKETCfg.TL_DATA_WIDTH-1:0] auto_in_d_bits_data,
    output logic       auto_in_d_bits_corrupt,

    // Sink TileLink A output toward downstream TL-to-AXI/RAM path
    input  logic auto_out_a_ready,
    output logic auto_out_a_valid,
    output logic [2:0] auto_out_a_bits_opcode,
    output logic [2:0] auto_out_a_bits_param,
    output logic [2:0] auto_out_a_bits_size,
    output logic [9:0] auto_out_a_bits_source,
    output logic [33:0] auto_out_a_bits_address,
    output logic [7:0] auto_out_a_bits_mask,
    output logic [ROCKETCfg.TL_DATA_WIDTH-1:0] auto_out_a_bits_data,

    // Sink TileLink D input from downstream TL-to-AXI/RAM path
    output logic auto_out_d_ready,
    input  logic auto_out_d_valid,
    input  logic [2:0] auto_out_d_bits_opcode,
    input  logic [2:0] auto_out_d_bits_param,
    input  logic [2:0] auto_out_d_bits_size,
    input  logic [9:0] auto_out_d_bits_source,
    input  logic       auto_out_d_bits_denied,
    input  logic [ROCKETCfg.TL_DATA_WIDTH-1:0] auto_out_d_bits_data,
    input  logic       auto_out_d_bits_corrupt
);

  ChannelA #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  ctl_a_req;
  ChannelD #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t ctl_d_resp;

  ChannelA #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  src_a_data;
  ChannelD #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t src_d_data;
  ChannelA #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  sink_a_data;
  ChannelD #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t sink_d_data;

  // Control D output
  assign auto_ctl_in_d_bits_opcode  = ctl_d_resp.opcode;
  assign auto_ctl_in_d_bits_param   = ctl_d_resp.param;
  assign auto_ctl_in_d_bits_size    = ctl_d_resp.size[1:0];
  assign auto_ctl_in_d_bits_source  = ctl_d_resp.source;
  assign auto_ctl_in_d_bits_denied  = ctl_d_resp.denied;
  assign auto_ctl_in_d_bits_data    = ctl_d_resp.data;
  assign auto_ctl_in_d_bits_corrupt = ctl_d_resp.corrupt;

  // Downstream A output
  assign auto_out_a_bits_opcode  = sink_a_data.opcode;
  assign auto_out_a_bits_param   = sink_a_data.param;
  assign auto_out_a_bits_size    = sink_a_data.size;
  assign auto_out_a_bits_source  = sink_a_data.source;
  assign auto_out_a_bits_address = sink_a_data.address;
  assign auto_out_a_bits_mask    = sink_a_data.mask;
  assign auto_out_a_bits_data    = sink_a_data.data;

  // Source D output
  assign auto_in_d_bits_opcode  = src_d_data.opcode;
  assign auto_in_d_bits_param   = src_d_data.param;
  assign auto_in_d_bits_size    = src_d_data.size;
  assign auto_in_d_bits_source  = src_d_data.source;
  assign auto_in_d_bits_denied  = src_d_data.denied;
  assign auto_in_d_bits_data    = src_d_data.data;
  assign auto_in_d_bits_corrupt = src_d_data.corrupt;

  // Control A input
  assign ctl_a_req.opcode  = auto_ctl_in_a_bits_opcode;
  assign ctl_a_req.param   = 3'b000;
  assign ctl_a_req.size    = {1'b0, auto_ctl_in_a_bits_size};
  assign ctl_a_req.source  = auto_ctl_in_a_bits_source;
  assign ctl_a_req.address = auto_ctl_in_a_bits_address;
  assign ctl_a_req.mask    = auto_ctl_in_a_bits_mask;
  assign ctl_a_req.data    = auto_ctl_in_a_bits_data;

  // Source A input
  assign src_a_data.opcode  = auto_in_a_bits_opcode;
  assign src_a_data.param   = 3'b000;
  assign src_a_data.size    = auto_in_a_bits_size;
  assign src_a_data.source  = auto_in_a_bits_source;
  assign src_a_data.address = auto_in_a_bits_address;
  assign src_a_data.mask    = auto_in_a_bits_mask;
  assign src_a_data.data    = auto_in_a_bits_data;

  // Downstream D input
  assign sink_d_data.opcode  = auto_out_d_bits_opcode;
  assign sink_d_data.param   = auto_out_d_bits_param;
  assign sink_d_data.size    = auto_out_d_bits_size;
  assign sink_d_data.source  = auto_out_d_bits_source;
  assign sink_d_data.denied  = auto_out_d_bits_denied;
  assign sink_d_data.data    = auto_out_d_bits_data;
  assign sink_d_data.corrupt = auto_out_d_bits_corrupt;

  secure_memory_controller #(
      .ROCKETCfg(ROCKETCfg)
  ) secure_memory_controller_i (
      .clk_i(clock),
      .rst_ni(~reset),

      .ctl_a_ready_o(auto_ctl_in_a_ready),
      .ctl_a_valid_i(auto_ctl_in_a_valid),
      .ctl_a_req_i(ctl_a_req),
      .ctl_d_ready_i(auto_ctl_in_d_ready),
      .ctl_d_valid_o(auto_ctl_in_d_valid),
      .ctl_d_resp_o(ctl_d_resp),

      .src_a_ready_o(auto_in_a_ready),
      .src_a_valid_i(auto_in_a_valid),
      .src_a_req_i(src_a_data),
      .sink_a_ready_i(auto_out_a_ready),
      .sink_a_valid_o(auto_out_a_valid),
      .sink_a_req_o(sink_a_data),

      .src_d_ready_i(auto_in_d_ready),
      .src_d_valid_o(auto_in_d_valid),
      .src_d_resp_o(src_d_data),
      .sink_d_ready_o(auto_out_d_ready),
      .sink_d_valid_i(auto_out_d_valid),
      .sink_d_resp_i(sink_d_data)
  );

endmodule
