  `timescale 1ns / 1ps
  
package config_pkg;
  typedef struct packed {
    // General Purpose Register Size (in bits)
    int unsigned XLEN;
    int unsigned PLEN;
    
    int unsigned                 CACHELINE_WIDTH;
    int unsigned                 TL_DATA_WIDTH;
    int unsigned                 TL_SIZE_WIDTH;
    int unsigned                 TL_ADDRESS_WIDTH;
    // PMP entries number
    int unsigned                 NrPMPEntries;
    // PMP CSR configuration reset values
    logic [63:0][63:0]           PMPCfgRstVal;
    // PMP CSR address reset values
    logic [63:0][63:0]           PMPAddrRstVal;
    // PMP CSR read-only bits
    bit [63:0]                   PMPEntryReadOnly;
    // PMP NA4 and NAPOT mode enable
    bit                          PMPNapotEn;
    
    
  } rocket_cfg_t;

  localparam rocket_cfg_t rocket_cfg_empty = rocket_cfg_t'(0);

endpackage
