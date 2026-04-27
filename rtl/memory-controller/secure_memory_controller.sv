`default_nettype wire

import tilelink::*;

module secure_memory_controller #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (
    input logic clk_i,
    input logic rst_ni,
    
    // Config Port
    output logic                                                     ctl_a_ready_o,
    input  logic                                                     ctl_a_valid_i,
    input  ChannelA#(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  ctl_a_req_i,
    input  logic                                                     ctl_d_ready_i,
    output logic                                                     ctl_d_valid_o,
    output ChannelD#(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t ctl_d_resp_o,

    // Memory Port
    output logic                                                     src_a_ready_o,
    input  logic                                                     src_a_valid_i,
    input  ChannelA#(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  src_a_req_i,
    input  logic                                                     src_d_ready_i,
    output logic                                                     src_d_valid_o,
    output ChannelD#(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t src_d_resp_o,

    input  logic                                                  sink_a_ready_i,
    output logic                                                  sink_a_valid_o,
    output ChannelA#(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  sink_a_req_o,
    output logic                                                  sink_d_ready_o,
    input  logic                                                  sink_d_valid_i,
    input  ChannelD#(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t sink_d_resp_i
);


  // -------------
  // VAR - GLOBAL
  //--------------
  localparam int TL_IN_SOURCE_WIDTH  = 8;
  localparam int TL_OUT_SOURCE_WIDTH = 10;
  logic ctl_a_fire;
  logic [ROCKETCfg.XLEN-1:0] csr_rdata;
  
  // ------------------------
  // VAR - CSR Register File
  // ------------------------
  riscv_::pmpcfg_t [ROCKETCfg.NrPMPEntries-1:0]          csr_pmpcfg;
  logic [ROCKETCfg.NrPMPEntries-1:0][ROCKETCfg.PLEN-3:0] csr_pmpaddr;

  // -----------
  // VAR - ePMP
  // -----------
 
  typedef enum logic {
    SF_NONE = 1'b0,
    SF_EE   = 1'b1
  } security_feature_t;

  typedef enum logic {
    BYPASS = 1'b0,  // FW_PATHWAY  = 1'b0,
    MEU = 1'b1      // MEC_PATHWAY = 1'b1
  } pathway_t;

  logic              pmp_allow;
  security_feature_t pmp_security_features;


  pathway_t          req_pathway;
  pathway_t          resp_pathway;

  // -----------------------------
  // VAR - Memory Encryption Unit
  // -----------------------------

  logic                                                   meu_src_a_ready;
  logic                                                   meu_src_a_valid;
  ChannelA #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  meu_src_a_req;

  logic                                                   meu_src_d_ready;
  logic                                                   meu_src_d_valid;
  ChannelD #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t meu_src_d_resp;

  logic                                                   meu_sink_a_ready;
  logic                                                   meu_sink_a_valid;
  ChannelA #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  meu_sink_a_req;

  logic                                                   meu_sink_d_ready;
  logic                                                   meu_sink_d_valid;
  ChannelD #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t meu_sink_d_resp;
  
  // -------------------
  // ASSIGNMNETS - THIS
  // -------------------

  assign ctl_a_fire = ctl_a_ready_o && ctl_a_valid_i;

  // -------------------------------
  // PORT ASSIGNMENT - Control Port 
  // -------------------------------

  assign ctl_a_ready_o        = ctl_d_ready_i;
  assign ctl_d_valid_o        = ctl_a_valid_i;
  assign ctl_d_resp_o.opcode  = ctl_a_req_i.opcode == tilelink::GET ?  ACCESSACKDATA: tilelink::ACCESSACK;
  assign ctl_d_resp_o.param   = 3'b0;
  assign ctl_d_resp_o.size    = ctl_a_req_i.size;
  assign ctl_d_resp_o.source  = ctl_a_req_i.source;
  assign ctl_d_resp_o.denied  = 1'b0;
  assign ctl_d_resp_o.data    = ctl_a_req_i.opcode == tilelink::GET ? csr_rdata : 64'h0;  // Currently only write is supported
  assign ctl_d_resp_o.corrupt = 1'b0;

  // -------------------
  // CSR Register File
  // -------------------

  logic         [              11:0] csr_bits;
  riscv_::csr_t                      csr_addr;
  logic         [ROCKETCfg.XLEN-1:0] csr_wdata;
  
  


  csr_regfile #(
      .ROCKETCfg(ROCKETCfg)
  ) csr_reg_file_i (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .addr_i(csr_addr),
      .we_i(ctl_a_req_i.opcode == tilelink::GET ? 1'b0 : ctl_a_fire),
      .wdata_i(csr_wdata),
      .rdata_o(csr_rdata),
      .pmpcfg_o(csr_pmpcfg),
      .pmpaddr_o(csr_pmpaddr)
  );

  always_comb begin: csr
    // default values
    csr_bits = '0;
    csr_addr  = '0;
    csr_wdata = '0;
    if (ctl_a_valid_i ) begin 
      csr_bits  = {4'b0011, 8'b1010_0000 + ctl_a_req_i.address[10:3]};
      csr_addr  = riscv_::csr_t'(csr_bits);
      csr_wdata = ctl_a_req_i;
    end
  end: csr
  
  
  // -----
  // ePMP
  // -----
  localparam int ADDR_PAD = ROCKETCfg.PLEN - ROCKETCfg.TL_ADDRESS_WIDTH;
  //NOTES: this should only be done when we have valid data
  epmp #(
      .ROCKETCfg(ROCKETCfg)
  ) epmp_i (
      .pmpcfg_i(csr_pmpcfg),
      .pmpaddr_i(csr_pmpaddr),
      .addr_i({{(ADDR_PAD){1'b0}}, src_a_req_i.address}), // TODO FIX THIS - DONE CHECK
      .allow_o(pmp_allow),
      .ee_o(pmp_security_features)
  );

  // ----------------------------
  // Memory Encryption Unit(MEU)
  // ----------------------------
`ifdef DEBUG_SMCME  
  ztl_passthrough_width_adapter #(
    .OUTER_DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH),
    .INNER_DATA_WIDTH(ROCKETCfg.CACHELINE_WIDTH)
  

  ) tlz_passthrought_i (
 `else
   memory_encryption_unit #(
    .OUTER_DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH),
    .INNER_DATA_WIDTH(ROCKETCfg.CACHELINE_WIDTH),
    .SIZE_WIDTH      (3),
    .SOURCE_WIDTH    (TL_OUT_SOURCE_WIDTH),
    .ROCKETCfg       (ROCKETCfg)
   ) meu_i (
 `endif
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .src_a_ready_o(meu_src_a_ready),
      .src_a_valid_i(meu_src_a_valid),
      .src_a_req_i(meu_src_a_req),
      .src_d_ready_i(meu_src_d_ready),
      .src_d_valid_o(meu_src_d_valid),
      .src_d_resp_o(meu_src_d_resp),
      .sink_a_ready_i(meu_sink_a_ready),
      .sink_a_valid_o(meu_sink_a_valid),
      .sink_a_req_o(meu_sink_a_req),
      .sink_d_ready_o(meu_sink_d_ready),
      .sink_d_valid_i(meu_sink_d_valid),
      .sink_d_resp_i(meu_sink_d_resp),
      .pmpcfg_i(csr_pmpcfg),
      .pmpaddr_i(csr_pmpaddr)
  );

  // SMC - Secure Memory Controller
  // Routes TileLink requests and responses either through the MEU (Memory Encryption Unit)
  // or the bypass pathway, based on ePMP configuration and the request address.
  // The TileLink source field is extended by 1 bit to tag requests, allowing responses
  // to be routed back correctly through the MEU when needed.
  //
  always_comb begin: route_request_comb
  
    ChannelA #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  a_req_tag;
 
    if (pmp_security_features == SF_EE || ( meu_sink_a_valid && ~src_a_valid_i)) begin
      req_pathway  = MEU;
    end else begin
      req_pathway  = BYPASS;
    end
    
    // Request: Secuirty Featues depend on the address. 
    if (req_pathway == BYPASS) begin
        src_a_ready_o = sink_a_ready_i;
        sink_a_valid_o = src_a_valid_i;
        a_req_tag = src_a_req_i;
        a_req_tag.source = {2'b00, src_a_req_i.source[7:0]};
        sink_a_req_o = a_req_tag;
        
        // Disable MEU
        meu_src_a_valid = '0;
        meu_src_a_req = '0;
        meu_sink_a_ready = '0;
      end else begin  //  implies (~src_a_valid_i && sink_meu_valid_o)
        src_a_ready_o = meu_src_a_ready;
        meu_src_a_valid = src_a_valid_i;
        meu_src_a_req = src_a_req_i;
        meu_src_a_req.source = {src_a_valid_i ? 2'b10: 2'b00, src_a_req_i.source[7:0]};
        
        meu_sink_a_ready = sink_a_ready_i;
        sink_a_valid_o = meu_sink_a_valid;
        sink_a_req_o = meu_sink_a_req;  
     end

  end: route_request_comb
    
  always_comb begin: route_resp_comb
  
    ChannelD #(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t d_resp_untag;
        
    if (sink_d_valid_i && sink_d_resp_i.source[9] == '1 ? '1 : '0 || (meu_src_d_valid && ~sink_d_valid_i )) begin
      resp_pathway  = MEU;
    end else begin
      resp_pathway  = BYPASS;
    end
     
    if (resp_pathway == BYPASS) begin
      sink_d_ready_o = src_d_ready_i;
      src_d_valid_o = sink_d_valid_i;
      src_d_resp_o = sink_d_resp_i;
      
      meu_src_d_ready = '0;
      meu_sink_d_valid = '0;
      meu_sink_d_resp = '0;
        
     end else begin   
        meu_src_d_ready = src_d_ready_i;
        src_d_valid_o = meu_src_d_valid;
        d_resp_untag = meu_src_d_resp;
        d_resp_untag.source =  {2'b00, meu_src_d_resp.source[7:0]};
        src_d_resp_o = d_resp_untag;
        
        sink_d_ready_o   = meu_sink_d_ready;
        meu_sink_d_valid = sink_d_valid_i;
        meu_sink_d_resp  = sink_d_resp_i;
      
    end
    
    
    
    
  end : route_resp_comb
  
  
   always_comb begin: init_pmp_region
   if (ctl_a_req_i.opcode != tilelink::GET && ctl_a_fire) begin
       if (ctl_a_req_i.address[15:0] == 16'h280) begin
         // TODO!
       end     
     end
   end: init_pmp_region
   
   
   
endmodule
