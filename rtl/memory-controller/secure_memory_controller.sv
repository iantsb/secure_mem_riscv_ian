`default_nettype wire

import tilelink::*;
import metadata_pkg::*;

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

    input  logic                                                     sink_a_ready_i,
    output logic                                                     sink_a_valid_o,
    output ChannelA#(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::a_req_t  sink_a_req_o,
    output logic                                                     sink_d_ready_o,
    input  logic                                                     sink_d_valid_i,
    input  ChannelD#(.DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH))::d_resp_t sink_d_resp_i
);

  localparam int TL_IN_SOURCE_WIDTH  = 8;
  localparam int TL_OUT_SOURCE_WIDTH = 10;
  localparam int META_MEM_AW         = 8;
  localparam int VERSION_W           = 64;
  localparam int TAG_W               = 128;
  localparam int ADDR_PAD            = ROCKETCfg.PLEN - ROCKETCfg.TL_ADDRESS_WIDTH;

  localparam logic [ROCKETCfg.PLEN-1:0] DEFAULT_MASK = {ROCKETCfg.PLEN{1'b1}};
  localparam logic [ROCKETCfg.PLEN-1:0] DEFAULT_BASE = '0;

  logic ctl_a_fire;
  logic [ROCKETCfg.XLEN-1:0] csr_rdata;
  assign ctl_a_fire = ctl_a_ready_o && ctl_a_valid_i;

  // ------------------------
  // CSR Register File
  // ------------------------
  riscv_::pmpcfg_t [ROCKETCfg.NrPMPEntries-1:0]          csr_pmpcfg;
  logic [ROCKETCfg.NrPMPEntries-1:0][ROCKETCfg.PLEN-3:0] csr_pmpaddr;

  logic [11:0]               csr_bits;
  riscv_::csr_t              csr_addr;
  logic [ROCKETCfg.XLEN-1:0] csr_wdata;

  assign ctl_a_ready_o        = ctl_d_ready_i;
  assign ctl_d_valid_o        = ctl_a_valid_i;
  assign ctl_d_resp_o.opcode  = (ctl_a_req_i.opcode == tilelink::GET) ? tilelink::ACCESSACKDATA : tilelink::ACCESSACK;
  assign ctl_d_resp_o.param   = 3'b000;
  assign ctl_d_resp_o.size    = ctl_a_req_i.size;
  assign ctl_d_resp_o.source  = ctl_a_req_i.source;
  assign ctl_d_resp_o.denied  = 1'b0;
  assign ctl_d_resp_o.data    = (ctl_a_req_i.opcode == tilelink::GET) ? csr_rdata : '0;
  assign ctl_d_resp_o.corrupt = 1'b0;

  csr_regfile #(
      .ROCKETCfg(ROCKETCfg)
  ) csr_reg_file_i (
      .clk_i    (clk_i),
      .rst_ni   (rst_ni),
      .addr_i   (csr_addr),
      .we_i     ((ctl_a_req_i.opcode != tilelink::GET) && ctl_a_fire),
      .wdata_i  (csr_wdata),
      .rdata_o  (csr_rdata),
      .pmpcfg_o (csr_pmpcfg),
      .pmpaddr_o(csr_pmpaddr)
  );

  always_comb begin : csr
    csr_bits  = '0;
    csr_addr  = '0;
    csr_wdata = '0;
    if (ctl_a_valid_i) begin
      csr_bits  = {4'b0011, 8'b1010_0000 + ctl_a_req_i.address[10:3]};
      csr_addr  = riscv_::csr_t'(csr_bits);
      csr_wdata = ctl_a_req_i.data[ROCKETCfg.XLEN-1:0];
    end
  end : csr

  // -----
  // ePMP
  // -----
  typedef enum logic {
    SF_NONE = 1'b0,
    SF_EE   = 1'b1
  } security_feature_t;

  logic              pmp_allow;
  security_feature_t pmp_security_features;

  epmp #(
      .ROCKETCfg(ROCKETCfg)
  ) epmp_i (
      .pmpcfg_i(csr_pmpcfg),
      .pmpaddr_i(csr_pmpaddr),
      .addr_i({{ADDR_PAD{1'b0}}, src_a_req_i.address}),
      .allow_o(pmp_allow),
      .ee_o(pmp_security_features)
  );

  // -----------------------------
  // Memory Encryption Unit wires
  // -----------------------------
  logic meu_src_a_ready;
  logic meu_src_a_valid;
  ChannelA #(
    .DATA_WIDTH   (ROCKETCfg.TL_DATA_WIDTH),
    .SOURCE_WIDTH (TL_OUT_SOURCE_WIDTH)
  )::a_req_t meu_src_a_req;

  logic meu_src_d_ready;
  logic meu_src_d_valid;
  ChannelD #(
    .DATA_WIDTH   (ROCKETCfg.TL_DATA_WIDTH),
    .SOURCE_WIDTH (TL_OUT_SOURCE_WIDTH)
  )::d_resp_t meu_src_d_resp;

  logic meu_sink_a_ready;
  logic meu_sink_a_valid;
  ChannelA #(
    .DATA_WIDTH   (ROCKETCfg.TL_DATA_WIDTH),
    .SOURCE_WIDTH (TL_OUT_SOURCE_WIDTH)
  )::a_req_t meu_sink_a_req;

  logic meu_sink_d_ready;
  logic meu_sink_d_valid;
  ChannelD #(
    .DATA_WIDTH   (ROCKETCfg.TL_DATA_WIDTH),
    .SOURCE_WIDTH (TL_OUT_SOURCE_WIDTH)
  )::d_resp_t meu_sink_d_resp;

  logic                      meu_meta_req_valid;
  logic                      meu_meta_req_ready;
  meta_op_e                  meu_meta_req_op;
  logic [ROCKETCfg.PLEN-1:0] meu_meta_req_addr;
  logic [2:0]                meu_meta_req_lane;
  logic                      meu_meta_rsp_valid;
  logic                      meu_meta_rsp_ready;
  logic [63:0]               meu_meta_rsp_version;
  logic                      meu_meta_rsp_error;

  logic                                      meu_used_version_valid;
  logic [63:0]                               meu_used_version;
  logic                                      meu_xform_valid;
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0]      meu_xform_data;

  memory_encryption_unit #(
    .OUTER_DATA_WIDTH(ROCKETCfg.TL_DATA_WIDTH),
    .INNER_DATA_WIDTH(ROCKETCfg.CACHELINE_WIDTH),
    .SIZE_WIDTH      (3),
    .SOURCE_WIDTH    (TL_OUT_SOURCE_WIDTH),
    .ROCKETCfg       (ROCKETCfg)
  ) meu_i (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),

    .src_a_ready_o  (meu_src_a_ready),
    .src_a_valid_i  (meu_src_a_valid),
    .src_a_req_i    (meu_src_a_req),

    .sink_a_ready_i (meu_sink_a_ready),
    .sink_a_valid_o (meu_sink_a_valid),
    .sink_a_req_o   (meu_sink_a_req),

    .src_d_ready_i  (meu_src_d_ready),
    .src_d_valid_o  (meu_src_d_valid),
    .src_d_resp_o   (meu_src_d_resp),

    .sink_d_ready_o (meu_sink_d_ready),
    .sink_d_valid_i (meu_sink_d_valid),
    .sink_d_resp_i  (meu_sink_d_resp),

    .pmpcfg_i       (csr_pmpcfg),
    .pmpaddr_i      (csr_pmpaddr),

    .meta_req_valid_o (meu_meta_req_valid),
    .meta_req_ready_i (meu_meta_req_ready),
    .meta_req_op_o    (meu_meta_req_op),
    .meta_req_addr_o  (meu_meta_req_addr),
    .meta_req_lane_o  (meu_meta_req_lane),

    .meta_rsp_valid_i   (meu_meta_rsp_valid),
    .meta_rsp_ready_o   (meu_meta_rsp_ready),
    .meta_rsp_version_i (meu_meta_rsp_version),
    .meta_rsp_error_i   (meu_meta_rsp_error),

    .used_version_valid_o(meu_used_version_valid),
    .used_version_o      (meu_used_version),
    .xform_valid_o       (meu_xform_valid),
    .xform_data_o        (meu_xform_data)
  );

  // -----------------------------
  // Integrity checker BMT wires
  // -----------------------------
  logic                      ic_start;
  logic                      ic_ready;
  logic                      ic_valid;
  logic                      ic_pass;
  logic                      ic_corrupt;
  logic [TAG_W-1:0]          ic_new_tag;
  logic [VERSION_W-1:0]      ic_leaf_version;

  logic                      ic_meta_req_valid;
  logic                      ic_meta_req_ready;
  meta_op_e                  ic_meta_req_op;
  logic [ROCKETCfg.PLEN-1:0] ic_meta_req_addr;
  logic [2:0]                ic_meta_req_lane;
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0] ic_meta_req_wdata;
  logic [TAG_W-1:0]          ic_meta_req_tag;
  logic                      ic_meta_rsp_valid;
  logic                      ic_meta_rsp_ready;
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0] ic_meta_rsp_data;
  logic [VERSION_W-1:0]      ic_meta_rsp_version;
  logic [TAG_W-1:0]          ic_meta_rsp_tag;
  logic                      ic_meta_rsp_error;

  logic [ROCKETCfg.PLEN-1:0] bmt_addr_q, bmt_addr_n;
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0] bmt_cipher_q, bmt_cipher_n;
  logic [VERSION_W-1:0]      bmt_version_q, bmt_version_n;
  logic                      bmt_write_q, bmt_write_n;
  logic                      bmt_have_cipher_q, bmt_have_cipher_n;
  logic                      bmt_have_version_q, bmt_have_version_n;
  logic                      bmt_pass_q, bmt_pass_n;

  integritychecker_bmt #(
    .PLEN           (ROCKETCfg.PLEN),
    .CACHELINE_BITS (ROCKETCfg.CACHELINE_WIDTH),
    .VERSION_W      (VERSION_W),
    .TAG_W          (TAG_W),
    .MARY           (8)
  ) u_integritychecker (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .start_i           (ic_start),
    .ready_o           (ic_ready),
    .valid_o           (ic_valid),
    .is_write_i        (bmt_write_q),
    .mask_i            (DEFAULT_MASK),
    .base_i            (DEFAULT_BASE),
    .addr_i            (bmt_addr_q),
    .protected_data_i  (bmt_cipher_q),
    .write_version_i   (bmt_version_q),
    .pass_o            (ic_pass),
    .corrupt_o         (ic_corrupt),
    .new_tag_o         (ic_new_tag),
    .leaf_version_o    (ic_leaf_version),
    .meta_req_valid_o  (ic_meta_req_valid),
    .meta_req_ready_i  (ic_meta_req_ready),
    .meta_req_op_o     (ic_meta_req_op),
    .meta_req_addr_o   (ic_meta_req_addr),
    .meta_req_lane_o   (ic_meta_req_lane),
    .meta_req_wdata_o  (ic_meta_req_wdata),
    .meta_req_tag_o    (ic_meta_req_tag),
    .meta_rsp_valid_i  (ic_meta_rsp_valid),
    .meta_rsp_ready_o  (ic_meta_rsp_ready),
    .meta_rsp_data_i   (ic_meta_rsp_data),
    .meta_rsp_version_i(ic_meta_rsp_version),
    .meta_rsp_tag_i    (ic_meta_rsp_tag),
    .meta_rsp_error_i  (ic_meta_rsp_error)
  );

  // -----------------------------
  // Shared metadata controller and backing RAM
  // -----------------------------
  typedef enum logic [1:0] {
    MD_OWNER_NONE,
    MD_OWNER_MEU,
    MD_OWNER_IC
  } md_owner_e;

  md_owner_e md_owner_q, md_owner_n;

  logic                      md_req_valid;
  logic                      md_req_ready;
  meta_op_e                  md_req_op;
  logic [ROCKETCfg.PLEN-1:0] md_req_addr;
  logic [2:0]                md_req_lane;
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0] md_req_wdata;
  logic [TAG_W-1:0]          md_req_tag;
  logic                      md_rsp_valid;
  logic                      md_rsp_ready;
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0] md_rsp_data;
  logic [VERSION_W-1:0]      md_rsp_version;
  logic [TAG_W-1:0]          md_rsp_tag;
  logic                      md_rsp_hit;
  logic                      md_rsp_error;

  logic                                 meta_mem_req_valid;
  logic                                 meta_mem_req_ready;
  logic                                 meta_mem_req_write;
  logic [ROCKETCfg.PLEN-1:0]            meta_mem_req_addr;
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0] meta_mem_req_wdata;
  logic                                 meta_mem_rsp_valid;
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0] meta_mem_rsp_data;
  logic                                 meta_mem_rsp_error;

  wire md_choose_meu = meu_meta_req_valid;
  wire md_choose_ic  = !meu_meta_req_valid && ic_meta_req_valid;

  assign md_req_valid = (md_owner_q == MD_OWNER_NONE) && (meu_meta_req_valid || ic_meta_req_valid);
  assign md_req_op    = md_choose_meu ? meu_meta_req_op    : ic_meta_req_op;
  assign md_req_addr  = md_choose_meu ? meu_meta_req_addr  : ic_meta_req_addr;
  assign md_req_lane  = md_choose_meu ? meu_meta_req_lane  : ic_meta_req_lane;
  assign md_req_wdata = md_choose_meu ? '0                : ic_meta_req_wdata;
  assign md_req_tag   = md_choose_meu ? '0                : ic_meta_req_tag;

  assign meu_meta_req_ready = (md_owner_q == MD_OWNER_NONE) && md_choose_meu && md_req_ready;
  assign ic_meta_req_ready  = (md_owner_q == MD_OWNER_NONE) && md_choose_ic  && md_req_ready;

  assign meu_meta_rsp_valid   = md_rsp_valid && (md_owner_q == MD_OWNER_MEU);
  assign meu_meta_rsp_version = md_rsp_version;
  assign meu_meta_rsp_error   = md_rsp_error;

  assign ic_meta_rsp_valid   = md_rsp_valid && (md_owner_q == MD_OWNER_IC);
  assign ic_meta_rsp_data    = md_rsp_data;
  assign ic_meta_rsp_version = md_rsp_version;
  assign ic_meta_rsp_tag     = md_rsp_tag;
  assign ic_meta_rsp_error   = md_rsp_error;

  assign md_rsp_ready = ((md_owner_q == MD_OWNER_MEU) && meu_meta_rsp_ready) ||
                        ((md_owner_q == MD_OWNER_IC)  && ic_meta_rsp_ready);

  metadata_controller_serial #(
    .PLEN           (ROCKETCfg.PLEN),
    .CACHELINE_BITS (ROCKETCfg.CACHELINE_WIDTH),
    .VERSION_W      (VERSION_W),
    .TAG_W          (TAG_W)
  ) u_metadata_controller (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .req_valid_i     (md_req_valid),
    .req_ready_o     (md_req_ready),
    .req_op_i        (md_req_op),
    .req_addr_i      (md_req_addr),
    .req_lane_i      (md_req_lane),
    .req_wdata_i     (md_req_wdata),
    .req_tag_i       (md_req_tag),
    .rsp_valid_o     (md_rsp_valid),
    .rsp_ready_i     (md_rsp_ready),
    .rsp_data_o      (md_rsp_data),
    .rsp_version_o   (md_rsp_version),
    .rsp_tag_o       (md_rsp_tag),
    .rsp_hit_o       (md_rsp_hit),
    .rsp_error_o     (md_rsp_error),
    .mem_req_valid_o (meta_mem_req_valid),
    .mem_req_ready_i (meta_mem_req_ready),
    .mem_req_write_o (meta_mem_req_write),
    .mem_req_addr_o  (meta_mem_req_addr),
    .mem_req_wdata_o (meta_mem_req_wdata),
    .mem_rsp_valid_i (meta_mem_rsp_valid),
    .mem_rsp_data_i  (meta_mem_rsp_data),
    .mem_rsp_error_i (meta_mem_rsp_error)
  );

  (* ram_style = "block" *)
  logic [ROCKETCfg.CACHELINE_WIDTH-1:0] meta_ram [0:(1 << META_MEM_AW)-1];
  logic [META_MEM_AW-1:0] meta_mem_idx;

  assign meta_mem_idx       = meta_mem_req_addr[META_MEM_AW+5:6];
  assign meta_mem_req_ready = 1'b1;
  assign meta_mem_rsp_error = 1'b0;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      meta_mem_rsp_valid <= 1'b0;
      meta_mem_rsp_data  <= '0;
    end else begin
      meta_mem_rsp_valid <= 1'b0;
      if (meta_mem_req_valid && meta_mem_req_ready) begin
        meta_mem_rsp_valid <= 1'b1;
        if (meta_mem_req_write) begin
          meta_ram[meta_mem_idx] <= meta_mem_req_wdata;
          meta_mem_rsp_data      <= '0;
        end else begin
          meta_mem_rsp_data <= meta_ram[meta_mem_idx];
        end
      end
    end
  end

  // -----------------------------
  // Serialized TileLink+BMT controller
  // -----------------------------
  typedef enum logic [2:0] {
    BMT_IDLE,
    BMT_WAIT_MEU,
    BMT_IC_START,
    BMT_IC_WAIT,
    BMT_RELEASE
  } bmt_state_e;

  bmt_state_e bmt_state_q, bmt_state_n;

  logic secure_active_q, secure_active_n;
  logic src_req_secure;
  logic src_req_write;
  logic secure_req_fire;
  logic downstream_resp_secure;

  assign src_req_secure      = src_a_valid_i && (pmp_security_features == SF_EE) && pmp_allow;
  assign src_req_write       = (src_a_req_i.opcode == tilelink::PUTFULLDATA) ||
                               (src_a_req_i.opcode == tilelink::PUTPARTIALDATA);
  assign secure_req_fire     = src_req_secure && src_a_ready_o;
  assign downstream_resp_secure = sink_d_valid_i && sink_d_resp_i.source[9];

  // Request routing: secure requests enter the MEU; non-secure requests bypass.
  always_comb begin : route_request_comb
    ChannelA #(
      .DATA_WIDTH   (ROCKETCfg.TL_DATA_WIDTH),
      .SOURCE_WIDTH (TL_OUT_SOURCE_WIDTH)
    )::a_req_t a_req_tag;

    src_a_ready_o    = 1'b0;
    sink_a_valid_o   = 1'b0;
    sink_a_req_o     = '0;
    meu_src_a_valid  = 1'b0;
    meu_src_a_req    = '0;
    meu_sink_a_ready = 1'b0;

    if (secure_active_q) begin
      // One secure transaction at a time. The MEU owns the downstream A channel.
      src_a_ready_o    = 1'b0;
      meu_sink_a_ready = sink_a_ready_i;
      sink_a_valid_o   = meu_sink_a_valid;
      sink_a_req_o     = meu_sink_a_req;
    end else if (src_req_secure) begin
      src_a_ready_o       = meu_src_a_ready;
      meu_src_a_valid     = src_a_valid_i;
      meu_src_a_req       = src_a_req_i;
      meu_src_a_req.source= {2'b10, src_a_req_i.source[7:0]};

      meu_sink_a_ready = sink_a_ready_i;
      sink_a_valid_o   = meu_sink_a_valid;
      sink_a_req_o     = meu_sink_a_req;
    end else begin
      src_a_ready_o       = sink_a_ready_i;
      sink_a_valid_o      = src_a_valid_i;
      a_req_tag           = src_a_req_i;
      a_req_tag.source    = {2'b00, src_a_req_i.source[7:0]};
      sink_a_req_o        = a_req_tag;
    end
  end : route_request_comb

  // Response routing. Secure responses are held until BMT verification/update completes.
  always_comb begin : route_resp_comb
    ChannelD #(
      .DATA_WIDTH   (ROCKETCfg.TL_DATA_WIDTH),
      .SOURCE_WIDTH (TL_OUT_SOURCE_WIDTH)
    )::d_resp_t d_resp_untag;

    sink_d_ready_o    = 1'b0;
    src_d_valid_o     = 1'b0;
    src_d_resp_o      = '0;
    meu_src_d_ready   = 1'b0;
    meu_sink_d_valid  = 1'b0;
    meu_sink_d_resp   = '0;

    if (downstream_resp_secure || secure_active_q) begin
      // Downstream D belongs to MEU when source[9] is set.
      sink_d_ready_o   = downstream_resp_secure ? meu_sink_d_ready : 1'b0;
      meu_sink_d_valid = downstream_resp_secure;
      meu_sink_d_resp  = sink_d_resp_i;

      if (bmt_state_q == BMT_RELEASE && meu_src_d_valid) begin
        d_resp_untag        = meu_src_d_resp;
        d_resp_untag.source = {2'b00, meu_src_d_resp.source[7:0]};
        if (!bmt_pass_q) begin
          d_resp_untag.denied  = 1'b1;
          d_resp_untag.corrupt = 1'b1;
          d_resp_untag.data    = '0;
        end
        src_d_valid_o   = 1'b1;
        src_d_resp_o    = d_resp_untag;
        meu_src_d_ready = src_d_ready_i;
      end
    end else begin
      // Bypass response.
      sink_d_ready_o       = src_d_ready_i;
      src_d_valid_o        = sink_d_valid_i;
      d_resp_untag         = sink_d_resp_i;
      d_resp_untag.source  = {2'b00, sink_d_resp_i.source[7:0]};
      src_d_resp_o         = d_resp_untag;
    end
  end : route_resp_comb

  always_comb begin : bmt_fsm_comb
    bmt_state_n        = bmt_state_q;
    secure_active_n    = secure_active_q;
    bmt_addr_n         = bmt_addr_q;
    bmt_cipher_n       = bmt_cipher_q;
    bmt_version_n      = bmt_version_q;
    bmt_write_n        = bmt_write_q;
    bmt_have_cipher_n  = bmt_have_cipher_q;
    bmt_have_version_n = bmt_have_version_q;
    bmt_pass_n         = bmt_pass_q;
    md_owner_n         = md_owner_q;
    ic_start           = 1'b0;

    if (md_owner_q == MD_OWNER_NONE && md_req_valid && md_req_ready) begin
      md_owner_n = md_choose_meu ? MD_OWNER_MEU : MD_OWNER_IC;
    end else if (md_rsp_valid && md_rsp_ready) begin
      md_owner_n = MD_OWNER_NONE;
    end

    unique case (bmt_state_q)
      BMT_IDLE: begin
        if (secure_req_fire) begin
          secure_active_n    = 1'b1;
          bmt_addr_n         = {{ADDR_PAD{1'b0}}, src_a_req_i.address};
          bmt_cipher_n       = '0;
          bmt_version_n      = '0;
          bmt_write_n        = src_req_write;
          bmt_have_cipher_n  = 1'b0;
          bmt_have_version_n = 1'b0;
          bmt_pass_n         = 1'b0;
          bmt_state_n        = BMT_WAIT_MEU;
        end
      end

      BMT_WAIT_MEU: begin
        if (meu_xform_valid) begin
          bmt_cipher_n      = meu_xform_data;
          bmt_have_cipher_n = 1'b1;
        end
        if (meu_used_version_valid) begin
          bmt_version_n      = meu_used_version;
          bmt_have_version_n = 1'b1;
        end

        if (meu_src_d_valid &&
            (bmt_have_cipher_q  || meu_xform_valid) &&
            (bmt_have_version_q || meu_used_version_valid)) begin
          bmt_state_n = BMT_IC_START;
        end
      end

      BMT_IC_START: begin
        if (ic_ready) begin
          ic_start    = 1'b1;
          bmt_state_n = BMT_IC_WAIT;
        end
      end

      BMT_IC_WAIT: begin
        if (ic_valid) begin
          bmt_pass_n  = ic_pass;
          bmt_state_n = BMT_RELEASE;
        end
      end

      BMT_RELEASE: begin
        if (meu_src_d_valid && src_d_ready_i) begin
          secure_active_n    = 1'b0;
          bmt_have_cipher_n  = 1'b0;
          bmt_have_version_n = 1'b0;
          bmt_state_n        = BMT_IDLE;
        end
      end

      default: begin
        bmt_state_n     = BMT_IDLE;
        secure_active_n = 1'b0;
      end
    endcase
  end : bmt_fsm_comb

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bmt_state_q        <= BMT_IDLE;
      secure_active_q    <= 1'b0;
      bmt_addr_q         <= '0;
      bmt_cipher_q       <= '0;
      bmt_version_q      <= '0;
      bmt_write_q        <= 1'b0;
      bmt_have_cipher_q  <= 1'b0;
      bmt_have_version_q <= 1'b0;
      bmt_pass_q         <= 1'b0;
      md_owner_q         <= MD_OWNER_NONE;
    end else begin
      bmt_state_q        <= bmt_state_n;
      secure_active_q    <= secure_active_n;
      bmt_addr_q         <= bmt_addr_n;
      bmt_cipher_q       <= bmt_cipher_n;
      bmt_version_q      <= bmt_version_n;
      bmt_write_q        <= bmt_write_n;
      bmt_have_cipher_q  <= bmt_have_cipher_n;
      bmt_have_version_q <= bmt_have_version_n;
      bmt_pass_q         <= bmt_pass_n;
      md_owner_q         <= md_owner_n;
    end
  end

endmodule
