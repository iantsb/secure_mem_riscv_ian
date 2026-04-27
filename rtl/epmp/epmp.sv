module epmp #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (

    // Input
    input  logic            [        ROCKETCfg.PLEN-1:0]                     addr_i,
    input  riscv_::pmpcfg_t [ROCKETCfg.NrPMPEntries-1:0]                     pmpcfg_i,
    input  logic            [ROCKETCfg.NrPMPEntries-1:0][ROCKETCfg.PLEN-3:0] pmpaddr_i,
    //Output
    output logic                                                             allow_o,
    output logic                                                             ee_o
);
  timeunit 1ns; timeprecision 1ps;
  // If there is no PMPs EE is disabled
  if (ROCKETCfg.NrPMPEntries > 0) begin : gen_pmp
    logic [(ROCKETCfg.NrPMPEntries > 0 ? ROCKETCfg.NrPMPEntries-1 : 0):0] match;
    logic [(ROCKETCfg.NrPMPEntries > 0 ? ROCKETCfg.NrPMPEntries-1 : 0):0] ee;
    logic [ROCKETCfg.PLEN-1:0] unused_mask;
    logic [ROCKETCfg.PLEN-1:0] unused_base_addr;
    logic [ROCKETCfg.PLEN-1:0] unused_tag_addr;
    logic [ROCKETCfg.PLEN-1:0] unused_version_addr;

    for (genvar i = 0; i < ROCKETCfg.NrPMPEntries; i++) begin
      logic [ROCKETCfg.PLEN-3:0] conf_addr_prev;

      assign conf_addr_prev = (i == 0) ? '0 : pmpaddr_i[i-1];
	
     epmp_entry #(
      .ROCKETCfg(ROCKETCfg)
  ) i_epmp_entry (
      .addr_i          (addr_i),
      .conf_addr_i     (pmpaddr_i[i]),
      .conf_addr_prev_i(conf_addr_prev),
      .conf_addr_mode_i(pmpcfg_i[i].addr_mode),

      .match_o        (match[i]),
      .mask_o         (unused_mask),
      .base_addr_o    (unused_base_addr),
      .tag_addr_o     (unused_tag_addr),
      .version_addr_o (unused_version_addr)
  );
    end

    always_comb begin
      int i;

      allow_o = 1'b0;
      ee_o = 1'b0;
      for (i = 0; i < ROCKETCfg.NrPMPEntries; i++) begin
        if (match[i]) begin
          allow_o = 1'b1;
          ee_o = pmpcfg_i[i].ee;
          break;  // Requred by PMP Priority 
        end
      end
    end
  end else begin
    assign allow_o = 1'b1;
    assign ee_o    = 1'b0;
  end

endmodule : epmp


