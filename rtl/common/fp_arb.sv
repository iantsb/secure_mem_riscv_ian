
// ----------------------
// Fixed Point Arbiter
// ----------------------

module fp_arb #(
  parameter int unsigned INPUTS      = 4,
  parameter int unsigned DATA_WIDTH  = 64,   // With is only used if dtype is not overritten
  parameter type         dtype       = logic [DATA_WIDTH-1:0],
  // Dependent parameters - do not override
  parameter int unsigned INDEX_WIDTH = INPUTS > 32'd1 ? unsigned'($clog2(INPUTS)) : 32'd1,
  parameter type         itype       = logic [INDEX_WIDTH-1:0]
) (

  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic    [INPUTS-1:0] req_i,  // client requests
  output logic    [INPUTS-1:0] gnt_o,  // grants to client
  input  dtype    [INPUTS-1:0] data_i, // input data
  output logic                 req_o,  // -> downstream valid 
  input  logic                 gnt_i,  // <- downsream ready 
  output dtype                 data_o, // selected data
  output itype                 idx_o   // index of granted input

  // NOTES:
  // This is effectively AXI-style valid/ready:
  // req_o ~ valid
  // gnt_i ~ ready
  // Data flows only when both req_o and gnt_i are high.
);


  if (INPUTS == unsigned'(1)) begin : gen_pass_through
    assign gnt_o[0] = gnt_i;
    assign req_o    = req_i[0];
    assign data_o   = data_i[0];
    assign idx_o    = '0;
  end else begin : gen_arbiter
    always_comb begin
      gnt_o = '0;
      req_o = |req_i;
      data_o = '0;
      idx_o = '0;

      if (req_o && gnt_i)  begin
        for (int i = 0; i < INPUTS; i++) begin
          if (req_i[i])  begin
            gnt_o[i] = 1'b1;
            data_o   = data_i[i];
            idx_o    = itype'(i);
            break;
          end
        end
      end
    end
  end

endmodule
