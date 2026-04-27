`default_nettype wire  //  read up more on this - it impact the default behavior for ports


import tilelink::*;

module tlfrontend #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (

    input logic clk_i,
    input logic rst_ni,

    // Source side
    // Channel A
    output logic                                                  src_a_ready_o,
    input  logic                                                  src_a_valid_i,
    input  ChannelA#(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::a_data_t src_a_data_i,
    // Channel D
    input  logic                                                  src_d_ready_i,
    output logic                                                  src_d_valid_o,
    output ChannelD#(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::d_data_t src_d_data_o,

    // Sink side
    // Channel A
    input  logic                                             sink_a_ready_i,
    output logic                                             sink_a_valid_o,
    output ChannelA#(.WIDTH(ROCKETCfg.BEAT_WIDTH))::a_data_t sink_a_data_o,
    // Channel D
    output logic                                             sink_d_ready_o,
    input  logic                                             sink_d_valid_i,
    input  ChannelD#(.WIDTH(ROCKETCfg.BEAT_WIDTH))::d_data_t sink_d_data_i
);

  // --------------------
  // TLDispatcher  - VAR
  // --------------------

  logic                                             tld_src_a_ready;
  logic                                             tld_sink_a_valid;
  ChannelA#(.WIDTH(ROCKETCfg.BEAT_WIDTH))::a_data_t tld_sink_a_data;

  // -----------------
  // TLBuffer D - VAR
  // -----------------

  logic                                                   tlb_d_flush;

  // Source
  logic                                                   tlb_src_d_ready;
  logic                                                   tlb_src_d_valid;
  ChannelD #(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::d_data_t tlb_src_d_data;
  
  // Sink 
  logic                                                    tlb_sink_d_ready;
  logic                                                    tlb_sink_d_valid;
  ChannelD#(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::d_data_t   tlb_sink_d_data;



  // ------
  // THIS
  // ------
  // Note:  This modlule take a single beat as input. The TLDipatcher will spit it and send request.  TLBuffer Will buffer resp
  
  ChannelA #(.WIDTH(ROCKETCfg.CACHELINE_WIDTH))::a_data_t req_q, req_n;

  logic                        src_a_fire;
  logic                        src_d_fire;
  logic                        sink_a_fire;
  logic                        sink_d_fire;
  logic                        idle;
  // --------------------
  // TLDispatcher  -  IMPL
  // --------------------

  tldispatcher #(
      .ROCKETCfg(ROCKETCfg)
  ) tldispatcher_i (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .src_a_ready_o(tld_src_a_ready), 
      .src_a_valid_i(src_a_valid_i),
      .src_a_data_i(src_a_data_i),
      .sink_a_ready_i(sink_a_ready_i),
      .sink_a_valid_o(tld_sink_a_valid),
      .sink_a_data_o(tld_sink_a_data)
  );
  
  assign tld_src_a_fire = src_a_valid_i && tld_src_a_ready;
 
//   -------------------
//   TLBufferD  -  IMPL
//   -------------------

  tlbuffer_d #(
      .ROCKETCfg(ROCKETCfg)
  ) tlbuffer_d_i (
      .clk_i,
      .rst_ni,
      .flush_i(tlbd_flush),

      // Source side
      .src_d_ready_i(tlb_src_d_ready),  // src is ready and 
      .src_d_valid_o(tlb_src_d_valid),
      .src_d_data_o (tlb_src_d_data),

      // Sink side
      .sink_d_ready_o(tlb_sink_d_ready),
      .sink_d_valid_i(sink_d_valid_i),
      .sink_d_data_i(sink_d_data_i)
  );


  assign tlb_src_d_ready = src_d_ready_i && ~idle;

  // ----------
  // THIS IMPL
  // ----------

  // Ports
  assign src_a_ready_o = tld_src_a_ready && idle;  //  Validate ?
  assign sink_a_valid_o = tld_sink_a_valid;  //  Validate ? ---?
  assign sink_a_data_o = sink_a_valid_o ? tld_sink_a_data : '0;  //  Validate ?
  
  assign sink_d_ready_o = tlb_sink_d_ready;
  assign src_d_valid_o = tlb_src_d_valid;  //  Validate ?
  assign src_d_data_o = src_d_valid_o ? tlb_src_d_data : '0;  //  Validate ?

  // Global

  
  assign idle = req_q == '0;
  assign src_d_fire = src_d_valid_o && src_d_ready_i;
  
 

  //assign src_d_fire = src_d_ready_i && src_d_valid_o;
  // assign sink_d_fire = sink_d_ready_o && sink_d_valid_i;
  //assign sink_ready = fifo_usage == 0 && data_q != '0;

  // ----------
  // SRC_A_REQ
  // ----------

  always_comb begin : src_a_req
    req_n = req_q;  //kepp old value
    if (tld_src_a_fire) begin  // req_q must be = '0 for this to be true
       req_n = src_a_data_i;
    end 
    
    if (src_d_fire) begin
       req_n = '0;
    end
  end : src_a_req

  always_ff @(posedge clk_i or negedge rst_ni) begin : src_a_req_ff
    if (~rst_ni) begin
      req_q <= '0;
    end else begin
      req_q <= req_n;
    end
  end : src_a_req_ff


//  always_comb begin : sink_a_req
//    fifo_pop = 1'b0;

//    // Note: sink_a_fire depends on sink_a_valid  and that depends on =>  fifo_push || fifo_usage > 0
//    if (sink_a_fire) begin
//      fifo_pop = 1'b1;
//    end

//    if (sink_d_fire && data_q != '0) begin
//      if (data_q.source == sink_d_data_i.source) begin // read tilelink protocol for full validation
//        //src_d_valid_o = 1'b1;
//        //src_d_data_o = sink_d_data_i;
//      end
//    end
//  end : sink_a_req

endmodule
