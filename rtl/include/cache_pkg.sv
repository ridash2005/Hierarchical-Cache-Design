package cache_pkg;

    // -------------------------------------------------------------------------
    // System Parameters
    // -------------------------------------------------------------------------
    parameter DATA_WIDTH      = 32;       // Word size (CPU interface)
    parameter ADDR_WIDTH      = 32;       // Physical Address width
    parameter CACHE_LINE_SIZE = 512;      // 64 Bytes (512 bits)
    parameter BURST_LEN       = CACHE_LINE_SIZE / DATA_WIDTH;
    
    // -------------------------------------------------------------------------
    // L1 Configuration
    // -------------------------------------------------------------------------
    parameter L1_SIZE_KB      = 32;
    parameter L1_ASSOC        = 4;
    parameter L1_SETS         = (L1_SIZE_KB * 1024 * 8) / (L1_ASSOC * CACHE_LINE_SIZE);
    parameter L1_INDEX_WIDTH  = $clog2(L1_SETS);
    parameter L1_OFFSET_WIDTH = $clog2(CACHE_LINE_SIZE/8);
    parameter L1_TAG_WIDTH    = ADDR_WIDTH - L1_INDEX_WIDTH - L1_OFFSET_WIDTH;
    
    // -------------------------------------------------------------------------
    // L2 Configuration
    // -------------------------------------------------------------------------
    parameter L2_SIZE_KB      = 256;
    parameter L2_ASSOC        = 8;
    
    // -------------------------------------------------------------------------
    // L3 Configuration
    // -------------------------------------------------------------------------
    parameter L3_SIZE_KB      = 8192;
    parameter L3_ASSOC        = 16;


    // -------------------------------------------------------------------------
    // Transaction Types
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        READ  = 2'b00,
        WRITE = 2'b01,
        FLUSH = 2'b10
    } cmd_t;

    // -------------------------------------------------------------------------
    // Interface Structures
    // -------------------------------------------------------------------------
    
    // Request from master (e.g., CPU or L1) to slave (e.g., L1 or L2)
    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data; // For single word writes
        logic [CACHE_LINE_SIZE-1:0] line_data; // For cache line writebacks
        cmd_t                  cmd;
        logic                  valid;
        logic                  is_burst; // 0 = word access, 1 = line access
        logic [3:0]            byte_en;
    } cache_req_t;

    // Response from slave to master
    typedef struct packed {
        logic [DATA_WIDTH-1:0] data;
        logic [CACHE_LINE_SIZE-1:0] line_data;
        logic                  ready; // Slave accepts request
        logic                  valid; // Read data valid / Write done
        logic                  error;
    } cache_resp_t;

endpackage
