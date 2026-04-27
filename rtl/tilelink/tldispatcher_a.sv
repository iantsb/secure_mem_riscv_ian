`default_nettype wire //  read up more on this - it impact the default behavior for ports


import tilelink::*;

module tldispatcher_a #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (

  input logic clk_i,
  input logic  rst_ni, 
  
  // Source
  output logic                                                  src_a_ready_o, 
  input logic                                                   src_a_valid_i,
  input ChannelA #(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::a_data_t src_a_data_i,
  
  // Sink
  input logic                                               sink_a_ready_i, 
  output logic                                              sink_a_valid_o,
  output ChannelA #(.WIDTH(ROCKETCfg.BEAT_WIDTH))::a_data_t sink_a_data_o
);

  localparam size_t_0 = ROCKETCfg.CACHELINE_WIDTH >> 3; // CACHLEINE_WIDTH / 8 = 64 
  localparam size_t_1 = $clog2(size_t_0);
  localparam beats_count = (ROCKETCfg.CACHELINE_WIDTH / ROCKETCfg.BEAT_WIDTH);  // Round up or shoud DATA_WIDTH BE CORRECT
  localparam int unsigned BEATS_LEFT_WIDTH   = (beats_count > 1) ? $clog2(beats_count) : 1;

  // -----------
  // FIFO - VAR
  // -----------
  
  localparam DEPTH = beats_count;
  localparam int unsigned ADDR_DEPTH   = BEATS_LEFT_WIDTH;
 
  logic                                              fifo_flush;
  logic                                              fifo_full;
  logic                                              fifo_empty;
  logic                                              fifo_push;
  logic                                              fifo_pop;
  logic[ADDR_DEPTH-1:0]                              fifo_usage;
  ChannelA #(.WIDTH(ROCKETCfg.BEAT_WIDTH))::a_data_t fifo_enq_data, fifo_deq_data;

  
  // -----------
  // THIS - VAR
  // -----------  

  ChannelA #(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::a_data_t req_q, req_n;     
  logic [BEATS_LEFT_WIDTH-1:0]                            beats_left_q, beats_left_n;
  logic [BEATS_LEFT_WIDTH-1:0]                            beats_index;

  logic idle; 
  logic src_a_fire;;
  logic sink_a_fire;  
  
  // ------------
  // Fifo - IMPL
  // ------------
      
  fifo_v3 #(
      .FALL_THROUGH(1'b1),
      .DATA_WIDTH($bits(ChannelA #(ROCKETCfg.BEAT_WIDTH)::a_data_t)),
      .DEPTH(DEPTH)
  ) fifo_req_o_i (
      .clk_i,
      .rst_ni,
      .testmode_i(),  // not connected
      .flush_i(fifo_flush),
      .full_o(fifo_full),
      .empty_o(fifo_empty),
      .usage_o(fifo_usage),
      .push_i(fifo_push),
      .data_i(fifo_enq_data),
      .pop_i(fifo_pop),
      .data_o(fifo_deq_data)
  );
  
  // -----
  // THIS 
  // -----
  // 
  
  // -------------
  // ASSIGN PORTS
  // -------------
  assign src_a_ready_o = idle; //fifo_usage == 0  idle;// && sink_a_ready_i; //  Validate ? check new sink_a_ready_i

  assign sink_a_valid_o =  src_a_valid_i || ~fifo_empty; //  Validate ?
  assign sink_a_data_o = sink_a_valid_o ? fifo_deq_data: '0; //  Validate ?
  
  // Global
  assign idle = req_q == '0;
  assign src_a_fire = src_a_ready_o && src_a_valid_i;  
  assign sink_a_fire = sink_a_ready_i && sink_a_valid_o;    //come back from axi
 
  
  always_comb begin: src_a_req
    fifo_push = 1'b0;
    fifo_pop = 1'b0;
    fifo_enq_data = '0;
    beats_index = 1'b0;
   
    beats_left_n = beats_left_q;
    req_n = req_q; // keep the same
   
    if (src_a_fire && idle) begin  // First beat and only beat
      fifo_push = 1'b1;
      fifo_enq_data.opcode = src_a_data_i.opcode;
      fifo_enq_data.size = size_t_1;
      fifo_enq_data.source = src_a_data_i.source;
      fifo_enq_data.address = src_a_data_i.address;
      fifo_enq_data.mask = src_a_data_i.mask;
      fifo_enq_data.data = src_a_data_i.data[0+:ROCKETCfg.BEAT_WIDTH];
      req_n = src_a_data_i;
      if (src_a_data_i.opcode == tilelink::GET) begin
        beats_left_n = 0;   // when read nothing to buffer 
      end else begin
        beats_left_n = beats_count - 1;
      end
    end if (beats_left_q > 0) begin // Second,... beats
      fifo_push = 1'b1;
      beats_left_n = beats_left_q - 1;  
      fifo_enq_data.opcode = req_q.opcode;
      fifo_enq_data.size = size_t_1;
      fifo_enq_data.source = req_q.source;
      fifo_enq_data.address = req_q.address;
      fifo_enq_data.mask = req_q.mask;
      //beats_index = BEATS_LEFT_WIDTH'(beats_count - beats_left_q);
       beats_index = (beats_count - beats_left_q);
      fifo_enq_data.data = req_q.data[beats_index*ROCKETCfg.BEAT_WIDTH+:ROCKETCfg.BEAT_WIDTH];
    end
       
   if (sink_a_fire) begin    
      if (fifo_push || fifo_usage > 0) begin
        fifo_pop = 1'b1;
        
        if (beats_left_n == 0) begin
          req_n = '0;
        end
      end else begin
        //ERROR
      end 
    end
  end : src_a_req
    
  always_ff @(posedge clk_i or negedge rst_ni) begin: src_a_req_ff
    if (~rst_ni) begin
      beats_left_q <= '0;
      req_q <= '0;
    end else begin
      req_q <= req_n;
      beats_left_q <= beats_left_n;
    end
  end : src_a_req_ff
  
  endmodule