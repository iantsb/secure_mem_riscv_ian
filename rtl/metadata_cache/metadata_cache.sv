

module metadata_cache #(
  parameter int ADDR_WIDTH  = 35,
  parameter int DATA_WIDTH  = 64,
  parameter int CACHE_LINES = 8,
  parameter int NUM_WAYS    = 2
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic                  lookup_valid_i,
  input  logic [ADDR_WIDTH-1:0] lookup_addr_i,
  output logic                  lookup_hit_o,
  output logic [DATA_WIDTH-1:0] lookup_data_o,

  input  logic                  fill_valid_i,
  input  logic [ADDR_WIDTH-1:0] fill_addr_i,
  input  logic [DATA_WIDTH-1:0] fill_data_i,

  input  logic                  update_valid_i,
  input  logic [ADDR_WIDTH-1:0] update_addr_i,
  input  logic [DATA_WIDTH-1:0] update_data_i
);

  localparam int NUM_SETS    = (CACHE_LINES / NUM_WAYS);
  localparam int INDEX_WIDTH = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1;
  localparam int TAG_WIDTH   = ADDR_WIDTH - INDEX_WIDTH;
  localparam int WAY_W       = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1;

  logic [TAG_WIDTH-1:0]  tag_mem   [NUM_SETS-1:0][NUM_WAYS-1:0];
  logic [DATA_WIDTH-1:0] data_mem  [NUM_SETS-1:0][NUM_WAYS-1:0];
  logic                  valid_mem [NUM_SETS-1:0][NUM_WAYS-1:0];
  logic [WAY_W-1:0]      repl_ptr  [NUM_SETS-1:0];

  logic [INDEX_WIDTH-1:0] lookup_index, fill_index, update_index;
  logic [TAG_WIDTH-1:0]   lookup_tag, fill_tag, update_tag;

  integer i, j;

  assign lookup_index = lookup_addr_i[INDEX_WIDTH-1:0];
  assign lookup_tag   = lookup_addr_i[ADDR_WIDTH-1:INDEX_WIDTH];

  assign fill_index   = fill_addr_i[INDEX_WIDTH-1:0];
  assign fill_tag     = fill_addr_i[ADDR_WIDTH-1:INDEX_WIDTH];

  assign update_index = update_addr_i[INDEX_WIDTH-1:0];
  assign update_tag   = update_addr_i[ADDR_WIDTH-1:INDEX_WIDTH];

  always_comb begin
    lookup_hit_o  = 1'b0;
    lookup_data_o = '0;

    if (lookup_valid_i) begin
      for (int k = 0; k < NUM_WAYS; k++) begin
        if (valid_mem[lookup_index][k] &&
            (tag_mem[lookup_index][k] == lookup_tag)) begin
          lookup_hit_o  = 1'b1;
          lookup_data_o = data_mem[lookup_index][k];
        end
      end
    end
  end

  function automatic [WAY_W-1:0] pick_fill_way(input logic [INDEX_WIDTH-1:0] idx);
    logic found_invalid;
    logic [WAY_W-1:0] way;
    begin
      found_invalid = 1'b0;
      way = repl_ptr[idx];

      for (int k = 0; k < NUM_WAYS; k++) begin
        if (!valid_mem[idx][k] && !found_invalid) begin
          found_invalid = 1'b1;
          way = k[WAY_W-1:0];
        end
      end

      pick_fill_way = way;
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    logic [WAY_W-1:0] fill_way;
    logic found_hit;

    if (!rst_ni) begin
      for (i = 0; i < NUM_SETS; i++) begin
        repl_ptr[i] <= '0;
        for (j = 0; j < NUM_WAYS; j++) begin
          valid_mem[i][j] <= 1'b0;
          tag_mem[i][j]   <= '0;
          data_mem[i][j]  <= '0;
        end
      end
    end else begin
      if (fill_valid_i) begin
        fill_way = pick_fill_way(fill_index);
        valid_mem[fill_index][fill_way] <= 1'b1;
        tag_mem[fill_index][fill_way]   <= fill_tag;
        data_mem[fill_index][fill_way]  <= fill_data_i;
        repl_ptr[fill_index]            <= fill_way + 1'b1;
      end

      if (update_valid_i) begin
        found_hit = 1'b0;
        for (int k = 0; k < NUM_WAYS; k++) begin
          if (valid_mem[update_index][k] &&
              (tag_mem[update_index][k] == update_tag)) begin
            data_mem[update_index][k] <= update_data_i;
            found_hit = 1'b1;
          end
        end

        if (!found_hit) begin
          fill_way = pick_fill_way(update_index);
          valid_mem[update_index][fill_way] <= 1'b1;
          tag_mem[update_index][fill_way]   <= update_tag;
          data_mem[update_index][fill_way]  <= update_data_i;
          repl_ptr[update_index]            <= fill_way + 1'b1;
        end
      end
    end
  end

endmodule