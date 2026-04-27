module epmp_entry #(
    parameter config_pkg::rocket_cfg_t ROCKETCfg = config_pkg::rocket_cfg_empty
) (
    // Input
    input  logic                   [ROCKETCfg.PLEN-1:0] addr_i,
    input  logic                   [ROCKETCfg.PLEN-3:0] conf_addr_i,
    input  logic                   [ROCKETCfg.PLEN-3:0] conf_addr_prev_i,
    input  riscv_::pmp_addr_mode_t                      conf_addr_mode_i,
    // Output
    output logic                                        match_o,
    output logic                   [ROCKETCfg.PLEN-1:0] mask_o,
    output logic                   [ROCKETCfg.PLEN-1:0] base_addr_o,
    output logic                   [ROCKETCfg.PLEN-1:0] tag_addr_o,
    output logic                   [ROCKETCfg.PLEN-1:0] version_addr_o
);

  timeunit 1ns; timeprecision 1ps;
  logic        [        ROCKETCfg.PLEN-1:0] conf_addr_n;
  logic        [$clog2(ROCKETCfg.PLEN)-1:0] trail_ones;
  logic        [        ROCKETCfg.PLEN-1:0] base;
  logic        [        ROCKETCfg.PLEN-1:0] mask;
  int unsigned                              size;

  assign conf_addr_n = {2'b11, ~conf_addr_i};  // count the trailing 1's

  lzc #(
      .WIDTH(ROCKETCfg.PLEN),
      .MODE(1'b0)  // Mode counts the trailing zeros
  ) i_lzc (
      .in_i   (conf_addr_n),
      .cnt_o  (trail_ones),  // because we ~pmpaddr
      .empty_o()
  );

  always_comb begin
  // Defaults prevent latch inference.
  match_o        = 1'b0;
  mask_o         = '0;
  base_addr_o    = '0;
  tag_addr_o     = '0;
  version_addr_o = '0;

  base = '0;
  mask = '0;
  size = 0;

  unique case (conf_addr_mode_i)

    riscv_::TOR: begin
      base = '0;
      size = 0;
      mask = '0;

      if ((addr_i >= ({2'b0, conf_addr_prev_i} << 2)) &&
          (addr_i <  ({2'b0, conf_addr_i}      << 2))) begin

        mask = '1 << size;

        match_o     = 1'b1;
        mask_o      = mask;
        base_addr_o = base;

        tag_addr_o =
            base
          | ({{(ROCKETCfg.PLEN-2){1'b0}}, 2'b11} << (size - 2))
          | (((addr_i & ~mask) >> 9) << 7);

        version_addr_o =
            tag_addr_o
          | ({{(ROCKETCfg.PLEN-1){1'b0}}, 1'b1} << 6);
      end

      // synthesis translate_off
      if (match_o == 0) begin
        assert (addr_i >= ({2'b0, conf_addr_i} << 2) ||
                addr_i <  ({2'b0, conf_addr_prev_i} << 2));
      end else begin
        assert (addr_i <  ({2'b0, conf_addr_i} << 2) &&
                addr_i >= ({2'b0, conf_addr_prev_i} << 2));
      end
      // synthesis translate_on
    end

    riscv_::NAPOT: begin
      size = {{(32 - $clog2(ROCKETCfg.PLEN)){1'b0}}, trail_ones} + 3;
      mask = '1 << size;
      base = ({2'b0, conf_addr_i} << 2) & mask;

      match_o = ((addr_i & mask) == base);

      mask_o      = mask;
      base_addr_o = base;

      tag_addr_o =
          base
        | ({{(ROCKETCfg.PLEN-2){1'b0}}, 2'b11} << (size - 2))
        | (((addr_i & ~mask) >> 9) << 7);

      version_addr_o =
          tag_addr_o
        | ({{(ROCKETCfg.PLEN-1){1'b0}}, 1'b1} << 6);

      // synthesis translate_off
      assert (size >= 2);
      if (conf_addr_mode_i == riscv_::NAPOT) begin
        assert (size > 2);
        if (size < ROCKETCfg.PLEN - 2) assert (conf_addr_i[size-3] == 0);
        for (int i = 0; i < ROCKETCfg.PLEN - 2; i++) begin
          if (size > 3 && i <= size - 4) begin
            assert (conf_addr_i[i] == 1);
          end
        end
      end

      if (size < ROCKETCfg.PLEN - 1) begin
        if (base + 2 ** size > base) begin
          if (match_o == 0) begin
            assert (addr_i >= base + 2 ** size || addr_i < base);
          end else begin
            assert (addr_i < base + 2 ** size && addr_i >= base);
          end
        end else begin
          if (match_o == 0) begin
            assert (addr_i - 2 ** size >= base || addr_i < base);
          end else begin
            assert (addr_i - 2 ** size < base && addr_i >= base);
          end
        end
      end
      // synthesis translate_on
    end

    riscv_::OFF: begin
      // Defaults already set all outputs to zero.
    end

    default: begin
      // Defaults already set all outputs to zero.
    end

  endcase
end
endmodule
