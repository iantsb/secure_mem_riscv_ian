`default_nettype wire //  read up more on this - it impact the default behavior for ports


import tilelink::*;

module tldispatcher_d #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (

  input logic clk_i,
  input logic rst_ni, 
  
  // Source
  input logic                                               src_d_ready_i, 
  output logic                                              src_d_valid_o,
  output ChannelD #(.WIDTH(ROCKETCfg.BEAT_WIDTH))::d_data_t src_d_data_o,
  
  // Sink
  output logic                                                  sink_d_ready_o, 
  input logic                                                   sink_d_valid_i,
  input ChannelD #(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::d_data_t sink_d_data_i
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
  ChannelD #(.WIDTH(ROCKETCfg.BEAT_WIDTH))::d_data_t fifo_enq_data, fifo_deq_data;

  
  // -----------
  // THIS - VAR
  // -----------  

  ChannelD #(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::d_data_t resp_q, resp_n;     
  logic [BEATS_LEFT_WIDTH-1:0]                            beats_left_q, beats_left_n;
  logic [BEATS_LEFT_WIDTH-1:0]                            beats_index;

  logic idle;   
  logic src_d_fire; 
  logic sink_d_fire;
 
  
  // ------------
  // Fifo - IMPL
  // ------------
      
  fifo_v3 #(
      .FALL_THROUGH(1'b1),
      .DATA_WIDTH($bits(ChannelD #(ROCKETCfg.BEAT_WIDTH)::d_data_t)),
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
  assign sink_d_ready_o = idle;
  assign src_d_valid_o =  sink_d_valid_i || ~fifo_empty;
  assign src_d_data_o = src_d_valid_o ? fifo_deq_data: '0; //  Validate ?
  
  
  // Global
  assign idle = resp_q == '0;
  assign src_d_fire = src_d_ready_i && src_d_valid_o; 
  assign sink_d_fire = sink_d_ready_o && sink_d_valid_i;  
  
  always_comb begin: sink_a_req
    fifo_push = 1'b0;
    fifo_pop = 1'b0;
    fifo_enq_data = '0;
    beats_index = 1'b0;
   
    beats_left_n = beats_left_q;
    resp_n = resp_q;
   
    if (sink_d_fire && idle) begin  // First beat and only beat
      fifo_push = 1'b1;
      fifo_enq_data.opcode = sink_d_data_i.opcode;
      fifo_enq_data.param = sink_d_data_i.param;
      fifo_enq_data.size = size_t_1;
      fifo_enq_data.source = sink_d_data_i.source;
      fifo_enq_data.denied = sink_d_data_i.denied;
      fifo_enq_data.data = sink_d_data_i.data[0+:ROCKETCfg.BEAT_WIDTH];
      fifo_enq_data.corrupt = sink_d_data_i.corrupt;
      resp_n = sink_d_data_i;
      if (sink_d_data_i.opcode != tilelink::ACCESSACKDATA) begin
        beats_left_n = 0;   // when read nothing to buffer 
      end else begin
        beats_left_n = beats_count - 1;
      end
    end if (beats_left_q > 0) begin // Second,... beats
      fifo_push = 1'b1;
      beats_left_n = beats_left_q - 1;  
      fifo_enq_data.opcode = resp_q.opcode;
      fifo_enq_data.param = resp_q.param;
      fifo_enq_data.size = size_t_1;
      fifo_enq_data.source = resp_q.source;
      fifo_enq_data.denied = resp_q.denied;
      //beats_index = BEATS_LEFT_WIDTH'(beats_count - beats_left_q);
      beats_index = (beats_count - beats_left_q);
      fifo_enq_data.data = resp_q.data[beats_index*ROCKETCfg.BEAT_WIDTH+:ROCKETCfg.BEAT_WIDTH];
      fifo_enq_data.corrupt = resp_q.corrupt;
    end
       
   if (src_d_fire) begin    
      if (fifo_push || fifo_usage > 0) begin
        fifo_pop = 1'b1;
        
        if (beats_left_n == 0) begin
          resp_n = '0;
        end
      end else begin
        //ERROR
      end 
    end
  end : sink_a_req
    
  always_ff @(posedge clk_i or negedge rst_ni) begin: resp_d_req_ff
    if (~rst_ni) begin
      beats_left_q <= '0;
      resp_q <= '0;
    end else begin
      resp_q <= resp_n;
      beats_left_q <= beats_left_n;
    end
  end : resp_d_req_ff
  
  endmodule