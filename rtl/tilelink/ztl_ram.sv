/*

Copyright (c) 2025 Zach Moolman

*/

`resetall `timescale 1ns / 1ps 
//`default_nettype none

// ------------
// TileLink RAM
// -------------


typedef enum logic[2:0] {
  IDLE,
  WRITE_BURST,
  WRITE_ACK,
  READ_ACK
} state_t;

module ztl_ram #(
 
  parameter SIZE_BITS = 3,
  parameter SOURCE_BITS = 8,
  parameter DATA_BITS = 64,
  parameter ADDR_BITS = 19,
  // Depentent paramterter - do not change
  // if type is defined then  part of above is ignored
  parameter type channel_a_t = tilelink::ChannelA#(
      .SIZE_BITS(SIZE_BITS),
      .SOURCE_BITS(SOURCE_BITS),
      .DATA_BITS(DATA_BITS))::channel_a_t,
  parameter type channel_d_t  = tilelink::ChannelD#(
      .SIZE_BITS(SIZE_BITS),
      .SOURCE_BITS(SOURCE_BITS),
      .DATA_BITS(DATA_BITS))::channel_d_t
) (

    input logic clk_i,
    input logic rst_ni,

    // TLChannel A
    output logic       a_ready_o,
    input  logic       a_valid_i,
    input  channel_a_t a_req_i,

    // TLChannel D
    input  logic       d_ready_i,
    output logic       d_valid_o,
    output channel_d_t d_resp_o

);

  localparam DATA_BYTES = DATA_BITS >> 3; // devide by 8
  localparam VALID_ADDR_BITS = ADDR_BITS - $clog2(DATA_BYTES);
  localparam BEAT_COUNT_BITS = $clog2((1 << (1 << SIZE_BITS )) / (DATA_BITS >> 3));


  // -------------
  // Global - VAR 
  // ------------

  logic                 a_fire;
  logic                 d_fire;
  logic [DATA_BITS-1:0] mem[(2**VALID_ADDR_BITS)-1:0];
  // ---------------------
  // Req/Assembler - VAR 
  // ---------------------
  
  state_t                                   state_q, state_n;


  logic                                     resp_valid;
  logic                                     mem_rd_en;
  logic                                     mem_wr_en;
  logic [VALID_ADDR_BITS-1:0]               mem_addr;
  logic [BEAT_COUNT_BITS-1:0]               beats_left_q, beats_left_n;
  //logic [BEAT_COUNT_BITS-1:0]               a_beats_left_q, a_beats_left_n;
  //logic [BEAT_COUNT_BITS-1:0]               d_beats_left_q, d_beats_left_n;
  channel_a_t a_req_q, a_req_n;
  channel_d_t d_resp;


  // -------------------
  // PORT - ASSIGNMENTS
  // -------------------
  assign a_ready_o  = state_q == IDLE || state_q == WRITE_BURST;
  
  assign d_valid_o  = resp_valid;
  assign d_resp_o   = d_valid_o == 1'b1 ? d_resp : '0;
  
  // -------------------
  // THIS - ASSIGNMENTS
  // -------------------
  assign a_fire = a_ready_o && a_valid_i;
  assign d_fire = d_ready_i && d_valid_o;

  integer i, j;

  initial begin
    // alex 
    for (i = 0; i < 2 ** VALID_ADDR_BITS; i =  i + 2 ** (VALID_ADDR_BITS /2)) begin
        for (j = i; j < i + 2 ** (VALID_ADDR_BITS / 2); j = j + 2) begin
            mem[j]   = '0;
            mem[j+1] = '0;
        end
    end
  end

  // ----------------------
  // Req - IMPLE
  // ----------------------
  

  always_comb begin: req_beats_comb
    logic [BEAT_COUNT_BITS-1:0]  beat_count;
    
    state_n        = state_q;
    beats_left_n   = beats_left_q;
   
    a_req_n        = a_req_q;
    
    mem_rd_en  = 1'b0;
    mem_wr_en  = 1'b0;
    resp_valid = 1'b0;
    
    case(state_q)  
    IDLE: begin // first beat
      if (a_fire)  begin
        beat_count   = ((1 << a_req_i.size) / (DATA_BITS >> 3)) - 1;
        $display("===> beat_count %0d", beat_count);
        mem_wr_en    = a_req_i.opcode != tilelink::GET ? 1'b1 : 1'b0;
        
        a_req_n.opcode  = a_req_i.opcode;
        a_req_n.param   = a_req_i.param;
        a_req_n.size    = a_req_i.size;
        a_req_n.source  = a_req_i.source;
        a_req_n.address = a_req_i.address;
        a_req_n.data    = a_req_i.data;
        mem_addr        = a_req_n.address >> (ADDR_BITS - VALID_ADDR_BITS); 
        
        if (mem_wr_en) begin
          if (beat_count == 0) begin
            state_n = WRITE_ACK;
            beats_left_n = 0;
          end else begin
            state_n = WRITE_BURST;
            beats_left_n = beat_count-1; //write on next pos_edge
          end  
        end else begin
          state_n = READ_ACK;
          beats_left_n = beat_count; // start reading on next state
        end
      end
    end
    WRITE_BURST: begin
      if (a_fire) begin
        mem_wr_en      = 1'b1;
        beat_count     = ((1 << a_req_i.size) / (DATA_BITS >> 3)) - 1;
    
        a_req_n.data   = a_req_i.data;
        mem_addr       = (a_req_n.address >> (ADDR_BITS - VALID_ADDR_BITS)) + (beat_count - beats_left_q);
        
        beats_left_n = beats_left_q > 0 ? beats_left_q - 1 : '0;
        
        if (beats_left_q == '0) begin
          state_n = WRITE_ACK;
        end 
      end
    end
    WRITE_ACK: begin    
      resp_valid     = 1'b1;
      d_resp.opcode  = tilelink::ACCESSACK;
      d_resp.param   = a_req_q.param;
      d_resp.source  = a_req_q.source;
      d_resp.size    = a_req_q.size;
      d_resp.denied  = 1'b0;
      d_resp.data    = '0;
      d_resp.corrupt = 1'b0;
      
      if (d_fire) begin
        a_req_n = '0;
        state_n = IDLE;
      end
    end
    READ_ACK: begin
      beat_count     = ((1 << a_req_n.size) / (DATA_BITS >> 3)) - 1;
      resp_valid     = 1'b1;
      d_resp.opcode  = tilelink::ACCESSACKDATA;
      d_resp.param   = a_req_q.param;
      d_resp.source  = a_req_q.source;
      d_resp.size    = a_req_q.size;
      d_resp.denied  = 1'b0;
      mem_addr       = (a_req_n.address >> (ADDR_BITS - VALID_ADDR_BITS)) + (beat_count - beats_left_q);   
      d_resp.data    = mem[mem_addr]; 
      d_resp.corrupt = 1'b0;
           
      if (d_fire) begin
        beats_left_n   = beats_left_q > 0 ? beats_left_q - 1 : '0;
       
        if (beats_left_q == '0) begin
          a_req_n = '0;
          state_n = IDLE;
        end
      end
    end 
    endcase
    
  end: req_beats_comb
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      state_q      <= IDLE;
      beats_left_q <= '0;
      a_req_q      <= '0;
    end else begin
      state_q      <= state_n;
      beats_left_q <= beats_left_n;
      a_req_q      <= a_req_n;
      if (mem_wr_en) begin
        mem[mem_addr] <= a_req_n.data;
      end
    end
  end
  
endmodule

`resetall
