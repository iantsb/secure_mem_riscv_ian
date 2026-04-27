`default_nettype wire
//  read up more on this - it impact the default behavior for ports

import tilelink::*;

module ztl_passthrough_width_adapter #( 
	parameter OUTER_DATA_WIDTH = 64,
	parameter INNER_DATA_WIDTH = 512,
	parameter SIZE_WIDTH = 3
) (
    input logic clk_i,
    input logic rst_ni,

    // TLChannel A
    output logic                           src_a_ready_o, 
    input logic                            src_a_valid_i,
    input  ChannelA#(
       .DATA_WIDTH(OUTER_DATA_WIDTH),
       .SIZE_WIDTH(SIZE_WIDTH))::a_req_t   src_a_req_i,
    input  logic                           sink_a_ready_i, 
    output logic                           sink_a_valid_o,
    output ChannelA #(
        .DATA_WIDTH(OUTER_DATA_WIDTH),
 	.SIZE_WIDTH(SIZE_WIDTH))::a_req_t  sink_a_req_o,

    // TLChannel D
    input logic                            src_d_ready_i,
    output logic                           src_d_valid_o,
    output ChannelD#(
        .DATA_WIDTH(OUTER_DATA_WIDTH),
	.SIZE_WIDTH(SIZE_WIDTH))::d_resp_t src_d_resp_o,
    output logic                           sink_d_ready_o,
    input logic                            sink_d_valid_i,
    input ChannelD#(
        .DATA_WIDTH(OUTER_DATA_WIDTH),
        .SIZE_WIDTH(SIZE_WIDTH))::d_resp_t sink_d_resp_i

);

  // --------------------
  // ZTL Assembler - VAR 
  // -------------------

  logic                                    assembler_a_valid;
  ChannelA #(
        .DATA_WIDTH(INNER_DATA_WIDTH),
 	.SIZE_WIDTH(SIZE_WIDTH))::a_req_t  assembler_a_req;
 
  logic                                    assembler_d_ready;
 
  // ---------------------
  // ZTL Fragmenter - VAR 
  // ---------------------

  logic                                    fragmenter_a_ready;
  
  logic                                    fragmenter_d_valid;
  ChannelD #(
        .DATA_WIDTH(INNER_DATA_WIDTH),
 	.SIZE_WIDTH(SIZE_WIDTH))::d_resp_t  fragmenter_d_resp;


ztlassembler #(
       .SRC_DATA_WIDTH(OUTER_DATA_WIDTH),
       .SINK_DATA_WIDTH(INNER_DATA_WIDTH),
       .SIZE_WIDTH(3)
  ) ztlassembler_i (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .src_a_ready_o(src_a_ready_o),
      .src_a_valid_i(src_a_valid_i),
      .src_a_req_i(src_a_req_i),
      .sink_a_ready_i(fragmenter_a_ready),
      .sink_a_valid_o(assembler_a_valid),
      .sink_a_req_o(assembler_a_req),
     
      .src_d_ready_i(src_d_ready_i),
      .src_d_valid_o(src_d_valid_o),
      .src_d_resp_o(src_d_resp_o),
      .sink_d_ready_o(assembler_d_ready),
      .sink_d_valid_i(fragmenter_d_valid),
      .sink_d_resp_i(fragmenter_d_resp)
  );

 ztlfragmenter #(
       .SRC_DATA_WIDTH(INNER_DATA_WIDTH),
       .SINK_DATA_WIDTH(OUTER_DATA_WIDTH),
       .SIZE_WIDTH(3)
  ) ztlfragmenter_i (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .src_a_ready_o(fragmenter_a_ready),
      .src_a_valid_i(assembler_a_valid),
      .src_a_req_i(assembler_a_req),
      .sink_a_ready_i(sink_a_ready_i),
      .sink_a_valid_o(sink_a_valid_o),
      .sink_a_req_o(sink_a_req_o),
      
      .src_d_ready_i(assembler_d_ready),
      .src_d_valid_o(fragmenter_d_valid),
      .src_d_resp_o(fragmenter_d_resp),
      .sink_d_ready_o(sink_d_ready_o),
      .sink_d_valid_i(sink_d_valid_i),
      .sink_d_resp_i(sink_d_resp_i)
  );

endmodule



