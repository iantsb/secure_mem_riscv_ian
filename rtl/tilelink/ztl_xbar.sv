 `default_nettype wire  // read up more on this - it impact the default behavior for ports

import tilelink::*;

module ztl_xbar #(
    parameter INPUTS                      = 4,
    parameter SIZE_WIDTH                  = 8,
    parameter SOURCE_WIDTH                = 8,
    parameter DATA_WIDTH                  = 64,
  
    parameter int unsigned INDEX_WIDTH    = INPUTS > 1 ? unsigned'($clog2(INPUTS)) : 32'd1,
    parameter type itype                  = logic [INDEX_WIDTH-1:0],
    parameter type channel_a_up_t         = ChannelA#(
      .SIZE_WIDTH(SIZE_WIDTH),
      .SOURCE_WIDTH(SOURCE_WIDTH),
      .DATA_WIDTH(DATA_WIDTH))::channel_a_t,
    parameter type channel_a_dn_t         = ChannelA#(
      .SIZE_WIDTH(SIZE_WIDTH),
      .SOURCE_WIDTH(SOURCE_WIDTH + INDEX_WIDTH),
      .DATA_WIDTH(DATA_WIDTH))::channel_a_t,
    parameter type channel_d_up_t         = ChannelD#(
       .SIZE_WIDTH(SIZE_WIDTH),
      .SOURCE_WIDTH(SOURCE_WIDTH),
      .DATA_WIDTH(DATA_WIDTH))::channel_d_t,
    parameter type channel_d_dn_t         = ChannelD#(
      .SIZE_WIDTH(SIZE_WIDTH),
      .SOURCE_WIDTH(SOURCE_WIDTH + INDEX_WIDTH),
      .DATA_WIDTH(DATA_WIDTH))::channel_d_t

) (
    input logic clk_i,
    input logic rst_ni,

    // TLChannel A
    output logic          [INPUTS-1:0] a_up_ready_o,
    input  logic          [INPUTS-1:0] a_up_valid_i,
    input  channel_a_up_t [INPUTS-1:0] a_up_i,
    input  logic                       a_dn_ready_i,
    output logic                       a_dn_valid_o,
    output channel_a_dn_t              a_dn_o,

    // TLChannel D
    input  logic          [INPUTS-1:0] d_up_ready_i,
    output logic          [INPUTS-1:0] d_up_valid_o,
    output channel_d_up_t [INPUTS-1:0] d_up_o,
    output logic                       d_dn_ready_o,
    input  logic                       d_dn_valid_i,
    input  channel_d_dn_t              d_dn_i
);

  channel_a_dn_t [INPUTS-1:0] a_up_tag;
  logic [INDEX_WIDTH-1:0] idx; 

  always_comb begin: tranpose_gen
    for (int i = 0; i < INPUTS; i++) begin   
      a_up_tag[i].opcode  = a_up_i[i].opcode;
      a_up_tag[i].param   = a_up_i[i].param;
      a_up_tag[i].size    = a_up_i[i].size;
      a_up_tag[i].source  = {itype'(i),a_up_i[i].source};
      a_up_tag[i].address = a_up_i[i].address;
      a_up_tag[i].mask    = a_up_i[i].mask;
      a_up_tag[i].data    = a_up_i[i].data;
    end
  end
  

  
  always_comb begin: route_gen
      logic [INDEX_WIDTH-1:0] uidx; 
      
      uidx = d_dn_i.source[SOURCE_WIDTH+INDEX_WIDTH-1:SOURCE_WIDTH];
      for (int i = 0; i < INPUTS; i++) begin      
        
        if (d_dn_valid_i && i == uidx) begin
          d_up_valid_o[i]   = 1'b1;
          d_up_o[i].opcode  = d_dn_i.opcode;
          d_up_o[i].param   = d_dn_i.param;
          d_up_o[i].source  = d_dn_i.source[SOURCE_WIDTH-1:0];
          d_up_o[i].corrupt = d_dn_i.corrupt;
          d_up_o[i].data    = d_dn_i.data;
          d_up_o[i].denied  = d_dn_i.denied;
        end else begin  
          d_up_valid_o[i] = 1'b0;
          d_up_o[i]       = '0;
        end
      end 
      
      d_dn_ready_o = d_up_ready_i[uidx]; // is this correct?
  end: route_gen

  fp_arb #(
    .INPUTS(INPUTS),
    .dtype(channel_a_dn_t)
  ) arb_i (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .req_i(a_up_valid_i),
      .gnt_o(a_up_ready_o),
      .data_i(a_up_tag),
      .req_o(a_dn_valid_o),
      .gnt_i(a_dn_ready_i),
      .data_o(a_dn_o),
      .idx_o(idx)
    );
    
   
endmodule
