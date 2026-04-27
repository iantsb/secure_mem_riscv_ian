`default_nettype wire


import tilelink::*;

module sm_addr_mapper#(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
  )
  
  (
    input logic            [                            ROCKETCfg.PLEN-1:0] addr_i, // USE FULL ADDRESS  that is padded
    input riscv_::pmpcfg_t [                    ROCKETCfg.NrPMPEntries-1:0] pmpcfg_i,
    input logic            [ROCKETCfg.NrPMPEntries-1:0][ROCKETCfg.PLEN-3:0] pmpaddr_i,

    output logic           [                            ROCKETCfg.PLEN-1:0] tag_addr_o,      // tag address
    output logic           [                            ROCKETCfg.PLEN-1:0] version_addr_o,  // version
    output logic           [                                           2:0] index_o          // index into 
);

  timeunit 1ns; timeprecision 1ps;
  


  // If there is no PMPs: disabled this module
  if (ROCKETCfg.NrPMPEntries > 0) begin : gen_pmp
    logic [(ROCKETCfg.NrPMPEntries > 0 ? ROCKETCfg.NrPMPEntries-1 : 0):0]                     match;
    logic [(ROCKETCfg.NrPMPEntries > 0 ? ROCKETCfg.NrPMPEntries-1 : 0):0][ROCKETCfg.PLEN-1:0] mask;
    logic [(ROCKETCfg.NrPMPEntries > 0 ? ROCKETCfg.NrPMPEntries-1 : 0):0][ROCKETCfg.PLEN-1:0] base_addr;
    logic [(ROCKETCfg.NrPMPEntries > 0 ? ROCKETCfg.NrPMPEntries-1 : 0):0][ROCKETCfg.PLEN-1:0] tag_addr;
    logic [(ROCKETCfg.NrPMPEntries > 0 ? ROCKETCfg.NrPMPEntries-1 : 0):0][ROCKETCfg.PLEN-1:0] version_addr;
    
  
    for (genvar i = 0; i < ROCKETCfg.NrPMPEntries; i++) begin
      logic [ROCKETCfg.PLEN-3:0] conf_addr_prev;

      assign conf_addr_prev = (i == 0) ? '0 : pmpaddr_i[i-1];

      epmp_entry #(
          .ROCKETCfg(ROCKETCfg)
      ) i_epmp_entry (
          .addr_i(addr_i),
          .conf_addr_i(pmpaddr_i[i]),
          .conf_addr_prev_i(conf_addr_prev),
          .conf_addr_mode_i(pmpcfg_i[i].addr_mode),
          .match_o(match[i]),
	      .mask_o(mask[i]),
	      .base_addr_o(base_addr[i]),
	      .tag_addr_o(tag_addr[i]),
	      .version_addr_o(version_addr[i])
      );
    end

    always_comb begin
      int i;
      tag_addr_o = '0;
      version_addr_o = '0;
      index_o = '0;
      for (i = 0; i < ROCKETCfg.NrPMPEntries; i++) begin
        if (match[i]) begin 
          tag_addr_o     = tag_addr[i];
          version_addr_o = version_addr[i];
          index_o        = addr_i[8:6];
          break;  // Requred by PMP Priority 
        end
      end
    end
  end else begin
    assign tag_addr_o = '0;
    assign version_addr_o = '0;
    assign index_o = '0;
  end


endmodule

