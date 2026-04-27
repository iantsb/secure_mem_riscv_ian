module csr_regfile #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (
    input  logic                                                             clk_i,
    input  logic                                                             rst_ni,
    input  logic            [                      11:0]                     addr_i,
    // Operation
    //input  fu_op       csr_op_i,
    input  logic                                                             we_i,
    input  logic            [        ROCKETCfg.XLEN-1:0]                     wdata_i,
    output logic            [        ROCKETCfg.XLEN-1:0]                     rdata_o,
    //PMP
    output riscv_::pmpcfg_t [ROCKETCfg.NrPMPEntries-1:0]                     pmpcfg_o,
    output logic            [ROCKETCfg.NrPMPEntries-1:0][ROCKETCfg.PLEN-3:0] pmpaddr_o
    //counters
);

  // internal signal to keep track of access exceptions
  logic read_access_exception, update_access_exception;
  logic csr_we, csr_read;
  logic [ROCKETCfg.XLEN-1:0] csr_wdata, csr_rdata;

  riscv_::csr_t csr_addr;
  riscv_::csr_t conv_csr_addr;

  riscv_::pmpcfg_t [63:0]
      pmpcfg_q,
      pmpcfg_d,
      pmpcfg_next;  // Core can have to 64 pmp entries, why not use NrPMPEntries?
  logic [63:0][ROCKETCfg.PLEN-3:0] pmpaddr_q, pmpaddr_d, pmpaddr_next;  // ..

  assign pmpcfg_o = pmpcfg_q[(ROCKETCfg.NrPMPEntries>0?ROCKETCfg.NrPMPEntries-1 : 0):0];
  assign pmpaddr_o = pmpaddr_q[(ROCKETCfg.NrPMPEntries>0?ROCKETCfg.NrPMPEntries-1 : 0):0];
  //--------------
  // Assingnments
  //--------------

  assign csr_addr = riscv_::csr_t'(addr_i);
  assign conv_csr_addr = csr_addr;  //redundent


  //---------------
  // CSR Read logic
  //----------------
  always_comb begin : csr_read_process
    csr_rdata             = '0;
    read_access_exception = 1'b0;

    if (csr_read) begin
      unique case (conv_csr_addr[11:0])
        riscv_::CSR_PMPCFG0,
                 riscv_::CSR_PMPCFG1,
                 riscv_::CSR_PMPCFG2,
                 riscv_::CSR_PMPCFG3,
                 riscv_::CSR_PMPCFG4,
                 riscv_::CSR_PMPCFG5,
                 riscv_::CSR_PMPCFG6,
                 riscv_::CSR_PMPCFG7,
                 riscv_::CSR_PMPCFG8,
                 riscv_::CSR_PMPCFG9,
                 riscv_::CSR_PMPCFG10,
                 riscv_::CSR_PMPCFG11,
                 riscv_::CSR_PMPCFG12,
                 riscv_::CSR_PMPCFG13,
                 riscv_::CSR_PMPCFG14,
                 riscv_::CSR_PMPCFG15: begin
          // index is calculated using PMPCFG0
          automatic logic [3:0] index = csr_addr.address[11:0] - riscv_::CSR_PMPCFG0;
          if (ROCKETCfg.XLEN == 64 && index[0] == 1'b1) read_access_exception = 1'b1;
          else begin
            // The following line has no effect. It's here just to prevent the synthesizer from crashing
            if (ROCKETCfg.XLEN == 64) index = (index >> 1) << 1;
            csr_rdata = pmpcfg_q[index*4+:ROCKETCfg.XLEN/8];
          end
        end

        riscv_::CSR_PMPADDR0,
            riscv_::CSR_PMPADDR1,
            riscv_::CSR_PMPADDR2,
            riscv_::CSR_PMPADDR3,
            riscv_::CSR_PMPADDR4,
            riscv_::CSR_PMPADDR5,
            riscv_::CSR_PMPADDR6,
            riscv_::CSR_PMPADDR7,
            riscv_::CSR_PMPADDR8,
            riscv_::CSR_PMPADDR9,
            riscv_::CSR_PMPADDR10,
            riscv_::CSR_PMPADDR11,
            riscv_::CSR_PMPADDR12,
            riscv_::CSR_PMPADDR13,
            riscv_::CSR_PMPADDR14,
            riscv_::CSR_PMPADDR15,
            riscv_::CSR_PMPADDR16,
            riscv_::CSR_PMPADDR17,
            riscv_::CSR_PMPADDR18,
            riscv_::CSR_PMPADDR19,
            riscv_::CSR_PMPADDR20,
            riscv_::CSR_PMPADDR21,
            riscv_::CSR_PMPADDR22,
            riscv_::CSR_PMPADDR23,
            riscv_::CSR_PMPADDR24,
            riscv_::CSR_PMPADDR25,
            riscv_::CSR_PMPADDR26,
            riscv_::CSR_PMPADDR27,
            riscv_::CSR_PMPADDR28,
            riscv_::CSR_PMPADDR29,
            riscv_::CSR_PMPADDR30,
            riscv_::CSR_PMPADDR31,
            riscv_::CSR_PMPADDR32,
            riscv_::CSR_PMPADDR33,
            riscv_::CSR_PMPADDR34,
            riscv_::CSR_PMPADDR35,
            riscv_::CSR_PMPADDR36,
            riscv_::CSR_PMPADDR37,
            riscv_::CSR_PMPADDR38,
            riscv_::CSR_PMPADDR39,
            riscv_::CSR_PMPADDR40,
            riscv_::CSR_PMPADDR41,
            riscv_::CSR_PMPADDR42,
            riscv_::CSR_PMPADDR43,
            riscv_::CSR_PMPADDR44,
            riscv_::CSR_PMPADDR45,
            riscv_::CSR_PMPADDR46,
            riscv_::CSR_PMPADDR47,
            riscv_::CSR_PMPADDR48,
            riscv_::CSR_PMPADDR49,
            riscv_::CSR_PMPADDR50,
            riscv_::CSR_PMPADDR51,
            riscv_::CSR_PMPADDR52,
            riscv_::CSR_PMPADDR53,
            riscv_::CSR_PMPADDR54,
            riscv_::CSR_PMPADDR55,
            riscv_::CSR_PMPADDR56,
            riscv_::CSR_PMPADDR57,
            riscv_::CSR_PMPADDR58,
            riscv_::CSR_PMPADDR59,
            riscv_::CSR_PMPADDR60,
            riscv_::CSR_PMPADDR61,
            riscv_::CSR_PMPADDR62,
            riscv_::CSR_PMPADDR63: begin
          //index is calculated using PMPADDR0 as the offset
          automatic logic [11:0] index = csr_addr.address[11:0] - riscv_::CSR_PMPADDR0;
          // Important: we only support granularity 8 bytes (G=1)
          // -> last bit of pmpaddr must be set 0/1 based on the mode:
          // NA4, NAPOT: 1
          // TOR, OFF: 0
          if (pmpcfg_q[index].addr_mode[1] == 1'b1)
            csr_rdata = {pmpaddr_q[index][ROCKETCfg.PLEN-3:1], 1'b1};
          else csr_rdata = {pmpaddr_q[index][ROCKETCfg.PLEN-3:1], 1'b0};
        end
        default: read_access_exception = 1'b1;
      endcase
    end
  end
  //---------------------------
  // CSR Write and upate logic
  //---------------------------
  always_comb begin : csr_update
    update_access_exception = 1'b0;
    pmpcfg_d = pmpcfg_q;
    pmpaddr_d = pmpaddr_q;

    if (we_i) begin
      unique case (conv_csr_addr.address)
        riscv_::CSR_PMPCFG0,
                 riscv_::CSR_PMPCFG1,
                 riscv_::CSR_PMPCFG2,
                 riscv_::CSR_PMPCFG3,
                 riscv_::CSR_PMPCFG4,
                 riscv_::CSR_PMPCFG5,
                 riscv_::CSR_PMPCFG6,
                 riscv_::CSR_PMPCFG7,
                 riscv_::CSR_PMPCFG8,
                 riscv_::CSR_PMPCFG9,
                 riscv_::CSR_PMPCFG10,
                 riscv_::CSR_PMPCFG11,
                 riscv_::CSR_PMPCFG12,
                 riscv_::CSR_PMPCFG13,
                 riscv_::CSR_PMPCFG14,
                 riscv_::CSR_PMPCFG15: begin
          // index is calculated using PMPCFG0 as the offset
          automatic logic [3:0] index = csr_addr.address[11:0] - riscv_::CSR_PMPCFG0;
          // if index is not even and XLEN==64, raise exception
          if (ROCKETCfg.XLEN == 64 && index[0] == 1'b1) update_access_exception = 1'b1;
          else begin
            for (int i = 0; i < ROCKETCfg.XLEN / 8; i++) begin
              if (!pmpcfg_q[index*4+i].locked) begin
                pmpcfg_d[index*4+i] = csr_wdata[i*8+:8];
              end
            end
          end
        end
        riscv_::CSR_PMPADDR0,
                riscv_::CSR_PMPADDR1,
                riscv_::CSR_PMPADDR2,
                riscv_::CSR_PMPADDR3,
                riscv_::CSR_PMPADDR4,
                riscv_::CSR_PMPADDR5,
                riscv_::CSR_PMPADDR6,
                riscv_::CSR_PMPADDR7,
                riscv_::CSR_PMPADDR8,
                riscv_::CSR_PMPADDR9,
                riscv_::CSR_PMPADDR10,
                riscv_::CSR_PMPADDR11,
                riscv_::CSR_PMPADDR12,
                riscv_::CSR_PMPADDR13,
                riscv_::CSR_PMPADDR14,
                riscv_::CSR_PMPADDR15,
                riscv_::CSR_PMPADDR16,
                riscv_::CSR_PMPADDR17,
                riscv_::CSR_PMPADDR18,
                riscv_::CSR_PMPADDR19,
                riscv_::CSR_PMPADDR20,
                riscv_::CSR_PMPADDR21,
                riscv_::CSR_PMPADDR22,
                riscv_::CSR_PMPADDR23,
                riscv_::CSR_PMPADDR24,
                riscv_::CSR_PMPADDR25,
                riscv_::CSR_PMPADDR26,
                riscv_::CSR_PMPADDR27,
                riscv_::CSR_PMPADDR28,
                riscv_::CSR_PMPADDR29,
                riscv_::CSR_PMPADDR30,
                riscv_::CSR_PMPADDR31,
                riscv_::CSR_PMPADDR32,
                riscv_::CSR_PMPADDR33,
                riscv_::CSR_PMPADDR34,
                riscv_::CSR_PMPADDR35,
                riscv_::CSR_PMPADDR36,
                riscv_::CSR_PMPADDR37,
                riscv_::CSR_PMPADDR38,
                riscv_::CSR_PMPADDR39,
                riscv_::CSR_PMPADDR40,
                riscv_::CSR_PMPADDR41,
                riscv_::CSR_PMPADDR42,
                riscv_::CSR_PMPADDR43,
                riscv_::CSR_PMPADDR44,
                riscv_::CSR_PMPADDR45,
                riscv_::CSR_PMPADDR46,
                riscv_::CSR_PMPADDR47,
                riscv_::CSR_PMPADDR48,
                riscv_::CSR_PMPADDR49,
                riscv_::CSR_PMPADDR50,
                riscv_::CSR_PMPADDR51,
                riscv_::CSR_PMPADDR52,
                riscv_::CSR_PMPADDR53,
                riscv_::CSR_PMPADDR54,
                riscv_::CSR_PMPADDR55,
                riscv_::CSR_PMPADDR56,
                riscv_::CSR_PMPADDR57,
                riscv_::CSR_PMPADDR58,
                riscv_::CSR_PMPADDR59,
                riscv_::CSR_PMPADDR60,
                riscv_::CSR_PMPADDR61,
                riscv_::CSR_PMPADDR62,
                riscv_::CSR_PMPADDR63: begin
          // index is calculated using PMPADDR0 as the offset
          automatic logic [11:0] index = csr_addr.address[11:0] - riscv_::CSR_PMPADDR0;
          // check if the entry or the enty above is locked
          if (!pmpcfg_q[index].locked == 1'b1 && !(pmpcfg_q[index+1].locked && pmpcfg_q[index+1].addr_mode == riscv_::TOR)) begin
            pmpaddr_d[index] = csr_wdata[ROCKETCfg.PLEN-3:0];
          end
        end
        default: update_access_exception = 1'b1;
      endcase
    end
  end

  //---------------------
  // CSR OP Select Logic
  //---------------------
  always_comb begin : csr_op_logic
    csr_wdata = wdata_i;
    csr_we = we_i;
    csr_read = ~we_i;
  end

  //--------------------
  // Output Assignments
  // -------------------
  always_comb begin
    rdata_o = csr_rdata;
  end

  // sequential process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      // pmp
      for (int i = 0; i < 64; i++) begin
        if (i < ROCKETCfg.NrPMPEntries) begin
          pmpcfg_q[i]  <= riscv_::pmpcfg_t'(ROCKETCfg.PMPCfgRstVal[i]);
          pmpaddr_q[i] <= ROCKETCfg.PMPAddrRstVal[i][ROCKETCfg.PLEN-3:0];
        end else begin
          pmpcfg_q[i]  <= '0;
          pmpaddr_q[i] <= '0;
        end
      end
    end else begin
      // pmp
      pmpcfg_q  <= pmpcfg_next;
      pmpaddr_q <= pmpaddr_next;
    end
  end

  // write logic pmp
  always_comb begin : write
    for (int i = 0; i < 64; i++) begin
      if (i < ROCKETCfg.NrPMPEntries) begin
        if (!ROCKETCfg.PMPEntryReadOnly[i]) begin
          // PMP locked logic is handled in the CSR write process above
          pmpcfg_next[i] = pmpcfg_d[i];
          // We only support >=8-byte granularity, NA4 is not supported
          if ((!ROCKETCfg.PMPNapotEn && pmpcfg_d[i].addr_mode == riscv_::NAPOT) ||pmpcfg_d[i].addr_mode == riscv_::NA4) begin
            pmpcfg_next[i].addr_mode = pmpcfg_q[i].addr_mode;
          end
          // Follow collective WARL spec for RWX fields
          if (pmpcfg_d[i].access_type.r == '0 && pmpcfg_d[i].access_type.w == '1) begin
            pmpcfg_next[i].access_type = pmpcfg_q[i].access_type;
          end
        end else begin
          pmpcfg_next[i] = pmpcfg_q[i];
        end
        if (!ROCKETCfg.PMPEntryReadOnly[i]) begin
          pmpaddr_next[i] = pmpaddr_d[i];
        end else begin
          pmpaddr_next[i] = pmpaddr_q[i];
        end
      end else begin
        pmpcfg_next[i]  = '0;
        pmpaddr_next[i] = '0;
      end
    end
  end

endmodule
