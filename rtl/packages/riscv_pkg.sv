package riscv_;

  localparam int CACHELINE_WIDTH = 512;
  localparam int TL_DATA_WIDTH = 64;
  localparam int TL_SIZE_WIDTH = 3;
  localparam int TL_ADDRESS_WIDTH = 34; // this naming convertion isn't correct it depends on the rocketchip, diplomacy...
  
  typedef enum logic [11:0] {
    CSR_PMPCFG0   = 12'h3A0,
    CSR_PMPCFG1   = 12'h3A1,
    CSR_PMPCFG2   = 12'h3A2,
    CSR_PMPCFG3   = 12'h3A3,
    CSR_PMPCFG4   = 12'h3A4,
    CSR_PMPCFG5   = 12'h3A5,
    CSR_PMPCFG6   = 12'h3A6,
    CSR_PMPCFG7   = 12'h3A7,
    CSR_PMPCFG8   = 12'h3A8,
    CSR_PMPCFG9   = 12'h3A9,
    CSR_PMPCFG10  = 12'h3AA,
    CSR_PMPCFG11  = 12'h3AB,
    CSR_PMPCFG12  = 12'h3AC,
    CSR_PMPCFG13  = 12'h3AD,
    CSR_PMPCFG14  = 12'h3AE,
    CSR_PMPCFG15  = 12'h3AF,
    CSR_PMPADDR0  = 12'h3B0,
    CSR_PMPADDR1  = 12'h3B1,
    CSR_PMPADDR2  = 12'h3B2,
    CSR_PMPADDR3  = 12'h3B3,
    CSR_PMPADDR4  = 12'h3B4,
    CSR_PMPADDR5  = 12'h3B5,
    CSR_PMPADDR6  = 12'h3B6,
    CSR_PMPADDR7  = 12'h3B7,
    CSR_PMPADDR8  = 12'h3B8,
    CSR_PMPADDR9  = 12'h3B9,
    CSR_PMPADDR10 = 12'h3BA,
    CSR_PMPADDR11 = 12'h3BB,
    CSR_PMPADDR12 = 12'h3BC,
    CSR_PMPADDR13 = 12'h3BD,
    CSR_PMPADDR14 = 12'h3BE,
    CSR_PMPADDR15 = 12'h3BF,
    CSR_PMPADDR16 = 12'h3C0,
    CSR_PMPADDR17 = 12'h3C1,
    CSR_PMPADDR18 = 12'h3C2,
    CSR_PMPADDR19 = 12'h3C3,
    CSR_PMPADDR20 = 12'h3C4,
    CSR_PMPADDR21 = 12'h3C5,
    CSR_PMPADDR22 = 12'h3C6,
    CSR_PMPADDR23 = 12'h3C7,
    CSR_PMPADDR24 = 12'h3C8,
    CSR_PMPADDR25 = 12'h3C9,
    CSR_PMPADDR26 = 12'h3CA,
    CSR_PMPADDR27 = 12'h3CB,
    CSR_PMPADDR28 = 12'h3CC,
    CSR_PMPADDR29 = 12'h3CD,
    CSR_PMPADDR30 = 12'h3CE,
    CSR_PMPADDR31 = 12'h3CF,
    CSR_PMPADDR32 = 12'h3D0,
    CSR_PMPADDR33 = 12'h3D1,
    CSR_PMPADDR34 = 12'h3D2,
    CSR_PMPADDR35 = 12'h3D3,
    CSR_PMPADDR36 = 12'h3D4,
    CSR_PMPADDR37 = 12'h3D5,
    CSR_PMPADDR38 = 12'h3D6,
    CSR_PMPADDR39 = 12'h3D7,
    CSR_PMPADDR40 = 12'h3D8,
    CSR_PMPADDR41 = 12'h3D9,
    CSR_PMPADDR42 = 12'h3DA,
    CSR_PMPADDR43 = 12'h3DB,
    CSR_PMPADDR44 = 12'h3DC,
    CSR_PMPADDR45 = 12'h3DD,
    CSR_PMPADDR46 = 12'h3DE,
    CSR_PMPADDR47 = 12'h3DF,
    CSR_PMPADDR48 = 12'h3E0,
    CSR_PMPADDR49 = 12'h3E1,
    CSR_PMPADDR50 = 12'h3E2,
    CSR_PMPADDR51 = 12'h3E3,
    CSR_PMPADDR52 = 12'h3E4,
    CSR_PMPADDR53 = 12'h3E5,
    CSR_PMPADDR54 = 12'h3E6,
    CSR_PMPADDR55 = 12'h3E7,
    CSR_PMPADDR56 = 12'h3E8,
    CSR_PMPADDR57 = 12'h3E9,
    CSR_PMPADDR58 = 12'h3EA,
    CSR_PMPADDR59 = 12'h3EB,
    CSR_PMPADDR60 = 12'h3EC,
    CSR_PMPADDR61 = 12'h3ED,
    CSR_PMPADDR62 = 12'h3EE,
    CSR_PMPADDR63 = 12'h3EF
  } csr_reg_t;


  // --------------------
  // Privilege Spec
  // --------------------
  typedef enum logic [1:0] {
    PRIV_LVL_M = 2'b11,
    PRIV_LVL_S = 2'b01,
    PRIV_LVL_U = 2'b00
  } priv_lvl_t;

  // decoded CSR address
  typedef struct packed {
    logic [1:0] rw;
    priv_lvl_t  priv_lvl;
    logic [7:0] address;
  } csr_addr_t;

  typedef union packed {
    csr_reg_t  address;
    csr_addr_t csr_decode;
  } csr_t;

  // PMP
  typedef enum logic [1:0] {
    OFF   = 2'b00,
    TOR   = 2'b01,
    NA4   = 2'b10,
    NAPOT = 2'b11
  } pmp_addr_mode_t;

  // PMP Access Type
  typedef enum logic [2:0] {
    ACCESS_NONE  = 3'b000,
    ACCESS_READ  = 3'b001,
    ACCESS_WRITE = 3'b010,
    ACCESS_EXEC  = 3'b100
  } pmp_access_t;

  typedef struct packed {
    logic x;
    logic w;
    logic r;
  } pmpcfg_access_t;

  // packed struct of a PMP configuration register (8bit)

  typedef struct packed {
    logic           locked;       // lock this configuration
    logic           reserved;
    logic           ee;           // encryption enabled 
    pmp_addr_mode_t addr_mode;    // Off, TOR, NA4, NAPOT
    pmpcfg_access_t access_type;
  } pmpcfg_t;

endpackage
