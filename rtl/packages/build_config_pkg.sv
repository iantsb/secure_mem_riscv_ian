
import riscv_::*;
import tilelink::*;

package build_config_pkg;
  `timescale 1ns / 1ps
  function automatic config_pkg::rocket_cfg_t build_config();
    config_pkg::rocket_cfg_t cfg;
    cfg.XLEN             = 64;
    cfg.PLEN             = 56;
    cfg.CACHELINE_WIDTH  = riscv_::CACHELINE_WIDTH;
    cfg.TL_DATA_WIDTH    = riscv_::TL_DATA_WIDTH;
    cfg.TL_SIZE_WIDTH    = riscv_::TL_SIZE_WIDTH;
    cfg.TL_ADDRESS_WIDTH = riscv_::TL_ADDRESS_WIDTH;
    cfg.NrPMPEntries     = 8;
    cfg.PMPCfgRstVal     = {64{64'h0}};
    cfg.PMPAddrRstVal    = {64{64'h0}};
    cfg.PMPEntryReadOnly = 64'd0;
    cfg.PMPNapotEn       = bit'(1);
    return cfg;
  endfunction

endpackage


