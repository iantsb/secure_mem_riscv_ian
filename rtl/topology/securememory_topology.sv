`timescale 1ns / 1ps


// currenty only support NAPOT bytes > 8 
// addres match 
module securememory_topology #(
  parameter PLEN           = ROCKETCfg.PLEN,
  parameter CACHELINE_BITS = ROCKETCfg.CAHCLEINE_WIDTH,
  parameter MARY = 8,
      
  //-- Dependent parameters,
  parameter CAHCELINE_BYTES = CACHELINE_BITS >> 3 // devide by 8
 
) (
    input  logic            [               PLEN-1:0] mask_i,
    input  logic            [               PLEN-1:0] base_i,
    input  logic            [               PLEN-1:0] addr_i,
    input  logic            [                 32-1:0] level_i,
    output logic            [                 32-1:0] metadata_block_count_o,
    output logic            [               PLEN-1:0] metadata_tag_addr_o,
    output logic            [               PLEN-1:0] metadata_version_addr_o,
    output logic            [                 32-1:0] merkeltree_leaf_count_o,    
    output logic            [                 32-1:0] merkeltree_height_o,
    output logic            [               PLEN-1:0] merkeltree_leaf_addr_o
);
 
  logic [  32-1:0] metadata_block_count;
  logic [PLEN-1:0] metadata_tag_addr;
  logic [PLEN-1:0] metadata_version_addr;
  logic [  32-1:0] merkeltree_leaf_count; // number of leafs in level-0
  logic [  32-1:0] merkeltree_height; // heigth of tree 
  logic [PLEN-1:0] merkeltree_leaf_addr;
  
  assign metadata_block_count_o  = metadata_block_count;
  assign metadata_tag_addr_o     = metadata_tag_addr;
  assign metadata_version_addr_o = metadata_version_addr;
  assign merkeltree_leaf_count_o = merkeltree_leaf_count;
  assign merkeltree_height_o     = merkeltree_height;
  assign merkeltree_leaf_addr_o  = merkeltree_leaf_addr;

  // -----
  //  LZC 
  // -----
  logic [$clog2(PLEN)-1:0] trail_zeros;
  
  lzc #(
      .WIDTH(PLEN),
      .MODE(1'b0)  // Mode counts the trailing zeros
  ) i_lzc (
      .in_i   (~mask_i),
      .cnt_o  (trail_zeros), 
      .empty_o()
  );
 
  logic        [PLEN-1:0]        upper_addr; 
  logic        [PLEN-1:0]        lower_addr; 
  logic        [PLEN-1:0]        md_mask;
  logic        [PLEN-1:0]        md_index;
  logic        [PLEN-1:0]        lz_mask;
  logic        [PLEN-1:0]        ll_mask;
  logic        [PLEN-1:0]        ll_index;
  
  logic [PLEN-1:0] mem_bytes;
  logic [PLEN-1:0] pd_bytes;
  logic [  32-1:0] pd_blocks; // memory size in terms of blocks
   
  logic [  32-1:0]   log2_leaves;
  localparam int K = $clog2(MARY); 
  
 

always_comb begin
 
  upper_addr  = ~mask_i & addr_i;
  lower_addr  = mask_i & addr_i;
  
  md_mask                  = 2'b11 << (trail_zeros-2);
  md_index                 = lower_addr >> 9;
  metadata_tag_addr        = upper_addr | md_mask | (md_index <<7);
  metadata_version_addr    = metadata_tag_addr;
  metadata_version_addr[6] = 1'b1;
  
  lz_mask              = 6'b111111 << (trail_zeros-6);
  ll_mask              = lz_mask | ( (( 1 << level_i*3) -1) << (trail_zeros - 6  - (3*level_i)));
  ll_index             = lower_addr >> (12 + (3 * level_i));
  merkeltree_leaf_addr = upper_addr | ll_mask | (ll_index << 6);	
   
  // calc height
  mem_bytes              =  mask_i + 1;
  pd_bytes               = (mem_bytes >> 1) | (mem_bytes >> 2); // this is also the ofset for metadata
  pd_blocks              = pd_bytes/CAHCELINE_BYTES;
  metadata_block_count   = pd_blocks/MARY; // repalce with shift
  merkeltree_leaf_count  = metadata_block_count/MARY; // repalce with shift
 
  log2_leaves            = $clog2(merkeltree_leaf_count);
  merkeltree_height      = (log2_leaves + K - 1) / K; // ceiling division  something is short here
  
end

endmodule
