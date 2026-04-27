package tilelink;
`timescale 1ns / 1ps

localparam int BEAT_WIDTH = 256;

typedef enum logic [2:0] {
  PUTFULLDATA    = 3'b000,
  PUTPARTIALDATA = 3'b001,
  ARITHMETICDATA = 3'b010,
  LOGICALDATA    = 3'b011,
  GET            = 3'b100,
  INTENT         = 3'b101
} tl_a_opcode_t;

typedef enum logic [2:0] {
  ACCESSACK     = 3'b000,
  ACCESSACKDATA = 3'b001,
  HINTACK       = 3'b010
} tl_d_opcode_t;


// -----------------------------------------------------------------------------
// TileLink Channel A compatibility wrapper.
//
// Supports both styles used across the project:
//
//   ChannelA#(.WIDTH(...))::a_data_t
//
// and:
//
//   ChannelA#(.DATA_WIDTH(...), .SIZE_WIDTH(...))::a_req_t
// -----------------------------------------------------------------------------
class ChannelA #(
  parameter int WIDTH        = BEAT_WIDTH,
  parameter int DATA_WIDTH   = WIDTH,
  parameter int SIZE_WIDTH   = 3,
  parameter int SOURCE_WIDTH = 10,
  parameter int ADDRESS_WIDTH = 34,
  parameter int MASK_WIDTH   = DATA_WIDTH / 8
);

  typedef struct packed {
    logic [2:0]                 opcode;
    logic [2:0]                 param;
    logic [SIZE_WIDTH-1:0]      size;
    logic [SOURCE_WIDTH-1:0]    source;
    logic [ADDRESS_WIDTH-1:0]   address;
    logic [MASK_WIDTH-1:0]      mask;
    logic [DATA_WIDTH-1:0]      data;
  } channel_a_t;

  typedef channel_a_t a_req_t;
  typedef channel_a_t a_data_t;

endclass


// -----------------------------------------------------------------------------
// TileLink Channel D compatibility wrapper.
//
// Supports both:
//
//   ChannelD#(.WIDTH(...))::d_data_t
//
// and:
//
//   ChannelD#(.DATA_WIDTH(...), .SIZE_WIDTH(...))::d_resp_t
// -----------------------------------------------------------------------------
class ChannelD #(
  parameter int WIDTH        = BEAT_WIDTH,
  parameter int DATA_WIDTH   = WIDTH,
  parameter int SIZE_WIDTH   = 3,
  parameter int SOURCE_WIDTH = 10
);

  typedef struct packed {
    logic [2:0]              opcode;
    logic [2:0]              param;
    logic [SIZE_WIDTH-1:0]   size;
    logic [SOURCE_WIDTH-1:0] source;
    logic                    denied;
    logic [DATA_WIDTH-1:0]   data;
    logic                    corrupt;
  } channel_d_t;

  typedef channel_d_t d_resp_t;
  typedef channel_d_t d_data_t;

endclass

endpackage