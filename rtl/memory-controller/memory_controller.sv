`default_nettype wire
;  //  read up more on this - it impact the default behavior for ports

import tilelink::*;

module memory_controller #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (
    // Sybstem clock
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,

    // CSR
    input riscv_::pmpcfg_t [ROCKETCfg.NrPMPEntries-1:0] pmpcfg_i, 
    input logic [ROCKETCfg.NrPMPEntries-1:0][ROCKETCfg.PLEN-3:0] pmpaddr_i,

    // Tilelink
    output logic                                                  src_a_ready_o,
    input  logic                                                  src_a_valid_i,
    input  ChannelA#(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::a_req_t  src_a_req_i,
    input  logic                                                  sink_a_ready_i,
    output logic                                                  sink_a_valid_o,
    output ChannelA#(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::a_req_t  sink_a_req_o,
    
    input  logic                                                  src_d_ready_i,
    output logic                                                  src_d_valid_o,
    output ChannelD#(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::d_resp_t src_d_resp_o,
    output logic                                                  sink_d_ready_o,
    input  logic                                                  sink_d_valid_i,
    input  ChannelD#(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::d_resp_t sink_d_resp_i
);

  typedef enum logic {
    FW_PATHWAY  = 1'b0,
    MEC_PATHWAY = 1'b1
  } pathway_t;


  // -----------
  // VAR - ePMP
  // -----------
  logic                                              pmp_allow;


  logic                                              req_mec;
  logic                                              resp_mec;
  pathway_t                                          req_pathway;
  pathway_t                                          resp_pathway;

  // ----------------------------------
  // VAR- Memory Encryption Controller
  // ----------------------------------


  logic                                                  mec_src_a_ready;
  logic                                                  mec_src_a_valid;
  ChannelA #(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::a_req_t mec_src_a_data;

  logic                                                   mec_src_d_ready;
  logic                                                   mec_src_d_valid;
  ChannelD #(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::d_resp_t mec_src_d_data;

  logic                                                  mec_sink_a_ready;
  logic                                                  mec_sink_a_valid;
  ChannelA #(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::a_req_t mec_sink_a_data;

  logic                                                   mec_sink_d_ready;
  logic                                                   mec_sink_d_valid;
  ChannelD #(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::d_resp_t mec_sink_d_data;


  // ------------------
  // VAR - Conditional
  // Conditional(con) src/sink ports, if not encrypted then assigb src/sink ports, if encrypted assingn mec ports 
  // ------------------



  // ----------------
  // PORT ASSIGMENTS
  // ----------------


  // set the source to indicate it is encrypted,  the source is used to route trafic coming back from 
  // external memeory
  always_comb begin : assignments
  
    ChannelA #(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::a_req_t a_data_extend_width;
    ChannelD #(.DATA_WIDTH(ROCKETCfg.DATA_WIDTH))::d_resp_t untag_data_d;
    req_pathway  = pathway_t'(mec_sink_a_valid && ~src_a_valid_i);
    resp_pathway = pathway_t'(mec_src_d_valid && ~sink_d_valid_i);
    
    
    if (req_mec) begin
      src_a_ready_o = mec_src_a_ready;
      mec_src_a_valid = src_a_valid_i;
      mec_src_a_data = src_a_req_i;
      mec_src_a_data.source = {src_a_valid_i ? 2'b10: 2'b00, src_a_req_i.source[7:0]};
      
      
      mec_sink_a_ready = sink_a_ready_i;
      sink_a_valid_o = mec_sink_a_valid;
      sink_a_req_o = mec_sink_a_data;
    end else begin
      // can add an arbirator but for now prioritize forward req
      if (req_pathway == FW_PATHWAY) begin
        src_a_ready_o = sink_a_ready_i;
        sink_a_valid_o = src_a_valid_i;
        a_data_extend_width = src_a_req_i;
        a_data_extend_width.source = {2'b00,src_a_req_i.source[7:0]};
        sink_a_req_o = a_data_extend_width;

        mec_src_a_valid = '0;
        mec_src_a_data = '0;
        mec_sink_a_ready = '0;
      end else begin  //  implies (~src_a_valid_i && sink_mec_valid_o)
        mec_sink_a_ready = sink_a_ready_i;
        sink_a_valid_o = mec_sink_a_valid;
        sink_a_req_o = mec_sink_a_data;

        src_a_ready_o = mec_src_a_ready;
        mec_src_a_valid = src_a_valid_i;
        mec_src_a_data = src_a_req_i;
        mec_src_a_data.source = {2'b10, src_a_req_i.source[7:0]};
        
      end

    end
    
    
    resp_mec = sink_d_valid_i && sink_d_resp_i.source[9] == '1 ? '1 : '0;
    
    
    if (resp_mec) begin
      sink_d_ready_o = mec_sink_d_ready;
      mec_sink_d_valid = sink_d_valid_i;
//      untag_data_d_tmp = sink_d_data_i;
//      untag_data_d_tmp.source[9] = 1'b0;
      mec_sink_d_data = sink_d_resp_i;
    

      mec_src_d_ready = src_d_ready_i;
      src_d_valid_o = mec_src_d_valid;
      untag_data_d = mec_src_d_data;
      untag_data_d.source = {2'b00, mec_src_d_data.source[7:0]};
      src_d_resp_o = untag_data_d;

    end else begin  // forword path

      // can add an arbirator but for now prioritize forward req
      if (resp_pathway == FW_PATHWAY) begin
        sink_d_ready_o = src_d_ready_i;
        src_d_valid_o = sink_d_valid_i;
        src_d_resp_o = sink_d_resp_i;

        mec_sink_d_valid = '0;
        mec_sink_d_data = '0;
        mec_src_d_ready = '0;
      end else begin  //  implies (~src_a_valid_i && sink_mec_valid_o)
        mec_src_d_ready = src_d_ready_i;
        src_d_valid_o = mec_src_d_valid;
        untag_data_d = mec_src_d_data;
        untag_data_d.source =  {2'b00, mec_src_d_data.source[7:0]};
        src_d_resp_o = untag_data_d;



        sink_d_ready_o = mec_sink_d_ready;
        mec_sink_d_valid = sink_d_valid_i;
        
        
        mec_sink_d_data = sink_d_resp_i;
        
                             
      end
    end

  end : assignments

  // ----
  // ePMP
  // ----

  //NOTES: this should only be done when we have valid data
  epmp #(
      .ROCKETCfg(ROCKETCfg)
  ) epmp_i (
      .pmpcfg_i (pmpcfg_i),
      .pmpaddr_i(pmpaddr_i),
      .addr_i   ({22'b0, src_a_req_i.address}), // TODO FIX THIS
      .allow_o(pmp_allow),
      .ee_o   (req_mec)
  );

  // -----------------------
  // Memory Encryption UNIT
  // -----------------------

  ztl_passthrough_width_adapter #(
     .OUTER_DATA_WIDTH(ROCKETCfg.DATA_WIDTH),
     .INNER_DATA_WIDTH(ROCKETCfg.CACHELINE_WIDTH)
 
 // mec #(
  //    .ROCKETCfg(ROCKETCfg)
  //) mec_i (
  ) tlz_passthrought_i (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .src_a_ready_o(mec_src_a_ready),
      .src_a_valid_i(mec_src_a_valid),
      .src_a_req_i(mec_src_a_data),
      .src_d_ready_i(mec_src_d_ready),
      .src_d_valid_o(mec_src_d_valid),
      .src_d_resp_o(mec_src_d_data),
      .sink_a_ready_i(mec_sink_a_ready),
      .sink_a_valid_o(mec_sink_a_valid),
      .sink_a_req_o(mec_sink_a_data),
      .sink_d_ready_o(mec_sink_d_ready),
      .sink_d_valid_i(mec_sink_d_valid),
      .sink_d_resp_i(mec_sink_d_data)
  );

endmodule
