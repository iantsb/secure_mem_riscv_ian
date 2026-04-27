package metadata_pkg;

  typedef enum logic [2:0] {
    META_READ_VERSION  = 3'd0,  // read counter/version metadata line
    META_ALLOC_VERSION = 3'd1,  // increment selected version lane and return updated line
    META_READ_TAG      = 3'd2,  // read tag metadata line
    META_WRITE_TAG     = 3'd3   // update selected tag lane
  } meta_op_e;

endpackage
