`default_nettype none

module metadata_controller #(
  parameter int PLEN            = 56,
  parameter int CACHELINE_BITS  = 512,
  parameter int CACHE_LINES     = 8,
  parameter int NUM_WAYS        = 2
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,

  input  logic                      meu_req_valid_i,
  output logic                      meu_req_ready_o,
  input  logic [PLEN-1:0]           meu_req_addr_i,
  output logic                      meu_resp_valid_o,
  input  logic                      meu_resp_ready_i,
  output logic [CACHELINE_BITS-1:0] meu_resp_data_o,
  output logic                      meu_resp_hit_o,

  input  logic                      ic_req_valid_i,
  output logic                      ic_req_ready_o,
  input  logic [PLEN-1:0]           ic_req_addr_i,
  output logic                      ic_resp_valid_o,
  input  logic                      ic_resp_ready_i,
  output logic [CACHELINE_BITS-1:0] ic_resp_data_o,
  output logic                      ic_resp_hit_o,

  output logic                      mem_req_valid_o,
  input  logic                      mem_req_ready_i,
  output logic [PLEN-1:0]           mem_req_addr_o,
  input  logic                      mem_resp_valid_i,
  input  logic [CACHELINE_BITS-1:0] mem_resp_data_i
);

  typedef enum logic [1:0] { MD_IDLE, MD_MEM_REQ, MD_MEM_WAIT, MD_RESPOND } md_state_t;
  typedef enum logic { OWNER_MEU, OWNER_IC } owner_t;

  md_state_t                 state_q, state_n;
  owner_t                    owner_q, owner_n;
  logic [PLEN-1:0]           miss_addr_q, miss_addr_n;
  logic                      resp_valid_q, resp_valid_n;
  logic [CACHELINE_BITS-1:0] resp_data_q, resp_data_n;
  logic                      resp_hit_q, resp_hit_n;

  logic                      cache_lookup_valid;
  logic [PLEN-1:0]           cache_lookup_addr;
  logic                      cache_lookup_hit;
  logic [CACHELINE_BITS-1:0] cache_lookup_data;
  logic                      cache_fill_valid;
  logic [PLEN-1:0]           cache_fill_addr;
  logic [CACHELINE_BITS-1:0] cache_fill_data;

  logic                      sel_valid;
  logic [PLEN-1:0]           sel_addr;
  owner_t                    sel_owner;

  metadata_cache #(
    .ADDR_WIDTH (PLEN),
    .DATA_WIDTH (CACHELINE_BITS),
    .CACHE_LINES(CACHE_LINES),
    .NUM_WAYS   (NUM_WAYS)
  ) u_metadata_cache (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .lookup_valid_i (cache_lookup_valid),
    .lookup_addr_i  (cache_lookup_addr),
    .lookup_hit_o   (cache_lookup_hit),
    .lookup_data_o  (cache_lookup_data),
    .fill_valid_i   (cache_fill_valid),
    .fill_addr_i    (cache_fill_addr),
    .fill_data_i    (cache_fill_data),
    .update_valid_i (1'b0),
    .update_addr_i  ('0),
    .update_data_i  ('0)
  );

  always_comb begin
    sel_valid = 1'b0;
    sel_addr  = '0;
    sel_owner = OWNER_MEU;
    if (ic_req_valid_i) begin
      sel_valid = 1'b1;
      sel_addr  = ic_req_addr_i;
      sel_owner = OWNER_IC;
    end else if (meu_req_valid_i) begin
      sel_valid = 1'b1;
      sel_addr  = meu_req_addr_i;
      sel_owner = OWNER_MEU;
    end
  end

  always_comb begin
    cache_lookup_valid = 1'b0;
    cache_lookup_addr  = '0;
    cache_fill_valid   = 1'b0;
    cache_fill_addr    = '0;
    cache_fill_data    = '0;

    mem_req_valid_o    = 1'b0;
    mem_req_addr_o     = '0;

    meu_req_ready_o    = 1'b0;
    ic_req_ready_o     = 1'b0;
    meu_resp_valid_o   = 1'b0;
    meu_resp_data_o    = '0;
    meu_resp_hit_o     = 1'b0;
    ic_resp_valid_o    = 1'b0;
    ic_resp_data_o     = '0;
    ic_resp_hit_o      = 1'b0;

    state_n            = state_q;
    owner_n            = owner_q;
    miss_addr_n        = miss_addr_q;
    resp_valid_n       = resp_valid_q;
    resp_data_n        = resp_data_q;
    resp_hit_n         = resp_hit_q;

    unique case (state_q)
      MD_IDLE: begin
        if (sel_valid) begin
          cache_lookup_valid = 1'b1;
          cache_lookup_addr  = sel_addr;
          if (sel_owner == OWNER_IC) begin
            ic_req_ready_o = 1'b1;
          end else begin
            meu_req_ready_o = 1'b1;
          end

          if (cache_lookup_hit) begin
            owner_n      = sel_owner;
            resp_valid_n = 1'b1;
            resp_data_n  = cache_lookup_data;
            resp_hit_n   = 1'b1;
            state_n      = MD_RESPOND;
          end else begin
            owner_n      = sel_owner;
            miss_addr_n  = sel_addr;
            resp_hit_n   = 1'b0;
            state_n      = MD_MEM_REQ;
          end
        end
      end

      MD_MEM_REQ: begin
        mem_req_valid_o = 1'b1;
        mem_req_addr_o  = miss_addr_q;
        if (mem_req_ready_i) begin
          state_n = MD_MEM_WAIT;
        end
      end

      MD_MEM_WAIT: begin
        if (mem_resp_valid_i) begin
          cache_fill_valid = 1'b1;
          cache_fill_addr  = miss_addr_q;
          cache_fill_data  = mem_resp_data_i;
          resp_valid_n     = 1'b1;
          resp_data_n      = mem_resp_data_i;
          resp_hit_n       = 1'b0;
          state_n          = MD_RESPOND;
        end
      end

      MD_RESPOND: begin
        if (owner_q == OWNER_IC) begin
          ic_resp_valid_o = resp_valid_q;
          ic_resp_data_o  = resp_data_q;
          ic_resp_hit_o   = resp_hit_q;
          if (resp_valid_q && ic_resp_ready_i) begin
            resp_valid_n = 1'b0;
            resp_data_n  = '0;
            resp_hit_n   = 1'b0;
            state_n      = MD_IDLE;
          end
        end else begin
          meu_resp_valid_o = resp_valid_q;
          meu_resp_data_o  = resp_data_q;
          meu_resp_hit_o   = resp_hit_q;
          if (resp_valid_q && meu_resp_ready_i) begin
            resp_valid_n = 1'b0;
            resp_data_n  = '0;
            resp_hit_n   = 1'b0;
            state_n      = MD_IDLE;
          end
        end
      end

      default: state_n = MD_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= MD_IDLE;
      owner_q      <= OWNER_MEU;
      miss_addr_q  <= '0;
      resp_valid_q <= 1'b0;
      resp_data_q  <= '0;
      resp_hit_q   <= 1'b0;
    end else begin
      state_q      <= state_n;
      owner_q      <= owner_n;
      miss_addr_q  <= miss_addr_n;
      resp_valid_q <= resp_valid_n;
      resp_data_q  <= resp_data_n;
      resp_hit_q   <= resp_hit_n;
    end
  end

endmodule
