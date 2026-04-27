   `default_nettype wire  // read up more on this - it impact the default behavior for ports


import tilelink::*;

module tlbuffer_a #(
    //parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
    parameter SRC_DATA_WIDTH  = 512,
    parameter SINK_DATA_WIDTH = 64
) (

    input logic clk_i,
    input logic rst_ni,

    //Source side
    output logic                                          src_a_ready_o,
    input  logic                                          src_a_valid_i,
    input  ChannelA#(SINK_DATA_WIDTH)::a_req_t                  src_a_req_i,

    //Sink side
    input  logic                                          sink_a_ready_i,
    output logic                                          sink_a_valid_o,
    output ChannelA#(SRC_DATA_WIDTH)::a_req_t                   sink_a_req_o


);
  localparam BEATS_LEFT_WIDTH = $clog2(SRC_DATA_WIDTH / SINK_DATA_WIDTH);
  localparam size_t_0 =SRC_DATA_WIDTH >> 3;  // 512 / 8 = 64 
  localparam size_t_1 = $clog2(size_t_0);  // 6
  localparam beats_count = (SRC_DATA_WIDTH / SINK_DATA_WIDTH);  // Round up or shoud DATA_WDITH BE CORRECT


  logic [BEATS_LEFT_WIDTH-1:0] beats_left_q, beats_left_n;
  logic [BEATS_LEFT_WIDTH-1:0] beats_index;
  ChannelA #(SRC_DATA_WIDTH)::a_req_t req_q, req_n;


  // -----------
  // THIS - VAR
  // -----------
 
  logic gated_clock;
  logic idle;
  //logic valid;
  //logic src_a_ready;
  logic src_a_fire;
  //logic sink_a_fire;


  // PORTS
  assign src_a_ready_o = idle;


  // GLOBAL
  assign idle = req_q == '0 || beats_left_q > 0;

  //assign sink_a_fire = sink_a_ready_i && valid ;
  assign src_a_fire = src_a_valid_i && idle;

  always_comb begin
    beats_left_n = beats_left_q;
    req_n = req_q;
    sink_a_valid_o = 1'b0;
    sink_a_req_o = req_q;
    gated_clock = 1'b0;  // Always update, unless last beat on sink-valid

    if (src_a_fire && req_q == '0) begin  // first beat
        req_n.opcode = src_a_req_i.opcode;
        req_n.size = src_a_req_i.size;
        req_n.source = src_a_req_i.source;
        req_n.address = src_a_req_i.address;
        req_n.mask = src_a_req_i.mask;
        req_n.data[SINK_DATA_WIDTH-1:0] = {{'0}, {src_a_req_i.data}};  // beat
        
        beats_left_n = beats_count - 1; 
        if (src_a_req_i.opcode == tilelink::GET) begin
          beats_left_n = 0;   // when read nothing to buffer 
        end else begin
          beats_left_n = beats_count - 1;
        end
        
        // pass-though
        if  (beats_left_n == 0 && sink_a_ready_i) begin
           gated_clock = 1'b1;
           sink_a_req_o = req_n;
           sink_a_valid_o = 1'b1;
        end
        
      end else if (src_a_fire) begin  // 2n,... beats
        beats_left_n = beats_left_q > 0 ? beats_left_q - 1 : '0;
        //beats_index = BEATS_LEFT_WIDTH'(beats_count - beats_left_q);
        beats_index = (beats_count - beats_left_q);
        req_n.data[beats_index* SINK_DATA_WIDTH+:SINK_DATA_WIDTH] = src_a_req_i.data;
        
        // pass-though
        if (beats_left_n == 0 && sink_a_ready_i) begin
           req_n = '0;
           sink_a_req_o = req_q; // make sure it on d as welll
           sink_a_valid_o = 1'b1;
           sink_a_req_o.data = {src_a_req_i.data,req_q.data[beats_count* SINK_DATA_WIDTH - SINK_DATA_WIDTH-1:0]};
        end
       
    end
    
    if (req_q != '0 && beats_left_q == 0 && sink_a_ready_i) begin
      req_n = '0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      beats_left_q <= '0;
      req_q <= '0;
    end else begin
      if (!gated_clock) begin   
        beats_left_q <= beats_left_n;
        req_q <= req_n;
      end
    end
  end
endmodule





