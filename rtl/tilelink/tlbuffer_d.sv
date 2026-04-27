`default_nettype wire  // read up more on this - it impact the default behavior for ports


import tilelink::*;

// Note: DChannel is the response, forward sink to source  
module tlbuffer_d #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (
    input logic clk_i,
    input logic rst_ni,
    
    //Source side
    input  logic                                                       src_d_ready_i,
    output logic                                                       src_d_valid_o,
    output ChannelD#(.DATA_WIDTH(ROCKETCfg.CACHELINE_WIDTH))::d_resp_t src_d_resp_o,

    //Sink side
    output logic                                                  sink_d_ready_o,
    input  logic                                                  sink_d_valid_i,
    input  ChannelD#(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::d_resp_t sink_d_resp_i
);
  
  localparam BEATS_LEFT_WIDTH_t_0 = $clog2(ROCKETCfg.CACHELINE_WIDTH / ROCKETCfg.DATA_WIDTH);
  localparam BEATS_LEFT_WIDTH = BEATS_LEFT_WIDTH_t_0 > 1 ? BEATS_LEFT_WIDTH_t_0 : 1;
  localparam size_t_0 = ROCKETCfg.CACHELINE_WIDTH >> 3;  // 512 / 8 = 64 
  localparam size_t_1 = $clog2(size_t_0);  // 6
  localparam beats_count = (ROCKETCfg.CACHELINE_WIDTH / ROCKETCfg.DATA_WIDTH);  // Round up or shoud DATA_WDITH BE CORRECT


  logic [BEATS_LEFT_WIDTH-1:0] beats_left_q, beats_left_n;
  logic [BEATS_LEFT_WIDTH-1:0] beats_index;
  ChannelD #(ROCKETCfg.CACHELINE_WIDTH)::d_resp_t resp_q, resp_n;  // Is width correct

  // -----------
  // THIS - VAR
  // -----------
 
  logic gated_clock;
  logic idle;
  logic sink_d_fire;

  // -----
  // THIS
  // -----

  // PORTS

  assign sink_d_ready_o = idle; 
  
  // GLOBAL 
  assign idle = resp_q == '0 || beats_left_q > 0;
  assign sink_d_fire = sink_d_valid_i && idle;
  
  always_comb begin
    beats_left_n = beats_left_q;
    resp_n = resp_q;
    src_d_valid_o = 1'b0;
    src_d_resp_o = resp_q;
    gated_clock = 1'b0;
    
    if (sink_d_fire && resp_q == '0) begin // first beat
      
      resp_n.opcode = sink_d_resp_i.opcode;
      resp_n.param = sink_d_resp_i.param;
      resp_n.size = sink_d_resp_i.size;
      resp_n.source = sink_d_resp_i.source;
      resp_n.denied = sink_d_resp_i.denied;
      resp_n.corrupt = sink_d_resp_i.corrupt;
     
      resp_n.data[ROCKETCfg.DATA_WIDTH-1:0] = {{'0}, {sink_d_resp_i.data}};  // first beat  
      
      if (sink_d_resp_i.opcode != tilelink::ACCESSACKDATA) begin
        beats_left_n = 0;  
      end else begin
        beats_left_n = beats_count - 1;
      end
        
      // pass-though
      if  (beats_left_n == 0 && src_d_ready_i) begin
         gated_clock = 1'b1;
         src_d_resp_o = resp_n;
         src_d_valid_o = 1'b1;
      end
    
    end else if (sink_d_fire) begin  // 2n,... beats
      beats_left_n = beats_left_q > 0 ? beats_left_q - 1 : '0;
      beats_index = BEATS_LEFT_WIDTH'(beats_count - beats_left_q);
      resp_n.data[beats_index*ROCKETCfg.DATA_WIDTH+:ROCKETCfg.DATA_WIDTH] = sink_d_resp_i.data;
      
       // pass-though
      if  (beats_left_n == 0 && src_d_ready_i) begin
     
        resp_n = '0;
        src_d_resp_o = resp_q; // make sure it on d as welll
        src_d_resp_o.data = {sink_d_resp_i.data,resp_q.data[beats_count*ROCKETCfg.DATA_WIDTH-ROCKETCfg.DATA_WIDTH-1:0]};
        src_d_valid_o = 1'b1;
        
      end
    end

    if (resp_q != '0 && beats_left_q == 0 && src_d_ready_i) begin
      resp_n = '0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (~rst_ni) begin
      beats_left_q <= '0;
      resp_q <= '0;
    end else begin
      if (!gated_clock) begin   
        beats_left_q <= beats_left_n;
        resp_q <= resp_n;
      end 
    end
  end

endmodule
