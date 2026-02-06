import cache_pkg::*;

module unified_cache #(
    parameter SIZE_KB = 256,
    parameter ASSOC   = 8,
    parameter CACHE_NAME = "UNIF"
)(
    input logic clk,
    input logic rst_n,
    
    // Upstream Interface (From L1 or L2)
    input  cache_req_t  prev_req_i,
    output cache_resp_t prev_resp_o,
    
    // Downstream Interface (To L3 or Memory)
    output cache_req_t  next_req_o,
    input  cache_resp_t next_resp_i
);


    // -------------------------------------------------------------------------
    // Parameters & Signals
    // -------------------------------------------------------------------------
    localparam NUM_SETS  = (SIZE_KB * 1024 * 8) / (ASSOC * CACHE_LINE_SIZE);
    localparam NUM_WAYS  = ASSOC;
    localparam INDEX_WIDTH = $clog2(NUM_SETS);
    localparam OFFSET_WIDTH = $clog2(CACHE_LINE_SIZE/8);
    localparam TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;
    
    // Address decoding
    logic [ADDR_WIDTH-1:0] addr_internal;
    assign addr_internal = prev_req_i.addr;
    
    logic [INDEX_WIDTH-1:0]  req_index;
    logic [TAG_WIDTH-1:0]    req_tag;
    
    assign req_index  = addr_internal[INDEX_WIDTH + OFFSET_WIDTH - 1 : OFFSET_WIDTH];
    assign req_tag    = addr_internal[ADDR_WIDTH - 1 : ADDR_WIDTH - TAG_WIDTH];

    // Array Types
    localparam TAG_ENTRY_WIDTH = 1 + 1 + TAG_WIDTH; // Dirty, Valid, Tag
    localparam LINE_BITS = CACHE_LINE_SIZE;

    // Internal Signals
    logic [NUM_WAYS-1:0] way_hit;
    logic                hit_valid;
    logic [$clog2(NUM_WAYS)-1:0] hit_way_idx;
    logic [TAG_ENTRY_WIDTH-1:0]  tag_rdata [NUM_WAYS-1:0];
    logic [LINE_BITS-1:0]        data_rdata [NUM_WAYS-1:0];
    
    // Array Controls
    logic array_we [NUM_WAYS-1:0];
    logic [TAG_ENTRY_WIDTH-1:0] tag_wdata;
    logic [LINE_BITS-1:0]       data_wdata;
    
    // LRU (Random/Counter for simplicity)
    logic [$clog2(NUM_WAYS)-1:0] lru_counter;
    logic [$clog2(NUM_WAYS)-1:0] victim_way;
    
    // Victim Info
    logic victim_dirty;
    logic [TAG_WIDTH-1:0] victim_tag;
    logic [LINE_BITS-1:0] victim_data;

    // -------------------------------------------------------------------------
    // Instantiate Arrays
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_WAYS; i++) begin : ways
            sram_array #( .WIDTH(TAG_ENTRY_WIDTH), .DEPTH(NUM_SETS) ) tag_ram (
                .clk(clk), .rst_n(rst_n), .we(array_we[i]), 
                .addr(req_index), .wdata(tag_wdata), .rdata(tag_rdata[i])
            );
            sram_array #( .WIDTH(LINE_BITS), .DEPTH(NUM_SETS) ) data_ram (
                .clk(clk), .rst_n(rst_n), .we(array_we[i]),
                .addr(req_index), .wdata(data_wdata), .rdata(data_rdata[i])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Logic (Similar to L1 but streamlined for Line Access)
    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------
    // Logic (Similar to L1 but streamlined for Line Access)
    // -------------------------------------------------------------------------
    logic [NUM_WAYS-1:0] way_hits;
    assign way_hits[0] = ((tag_rdata[0] >> TAG_WIDTH) & 1'b1) && ((tag_rdata[0] & ((1 << TAG_WIDTH)-1)) == req_tag);
    assign way_hits[1] = ((tag_rdata[1] >> TAG_WIDTH) & 1'b1) && ((tag_rdata[1] & ((1 << TAG_WIDTH)-1)) == req_tag);
    assign way_hits[2] = ((tag_rdata[2] >> TAG_WIDTH) & 1'b1) && ((tag_rdata[2] & ((1 << TAG_WIDTH)-1)) == req_tag);
    assign way_hits[3] = ((tag_rdata[3] >> TAG_WIDTH) & 1'b1) && ((tag_rdata[3] & ((1 << TAG_WIDTH)-1)) == req_tag);
    assign way_hits[4] = ((tag_rdata[4] >> TAG_WIDTH) & 1'b1) && ((tag_rdata[4] & ((1 << TAG_WIDTH)-1)) == req_tag);
    assign way_hits[5] = ((tag_rdata[5] >> TAG_WIDTH) & 1'b1) && ((tag_rdata[5] & ((1 << TAG_WIDTH)-1)) == req_tag);
    assign way_hits[6] = ((tag_rdata[6] >> TAG_WIDTH) & 1'b1) && ((tag_rdata[6] & ((1 << TAG_WIDTH)-1)) == req_tag);
    assign way_hits[7] = ((tag_rdata[7] >> TAG_WIDTH) & 1'b1) && ((tag_rdata[7] & ((1 << TAG_WIDTH)-1)) == req_tag);

    always @(*) begin
        way_hit = way_hits;
        hit_valid = (way_hits != 0);
        hit_way_idx = 0;
        if ((way_hits & 8'h01) != 0) hit_way_idx = 0;
        else if ((way_hits & 8'h02) != 0) hit_way_idx = 1;
        else if ((way_hits & 8'h04) != 0) hit_way_idx = 2;
        else if ((way_hits & 8'h08) != 0) hit_way_idx = 3;
        else if ((way_hits & 8'h10) != 0) hit_way_idx = 4;
        else if ((way_hits & 8'h20) != 0) hit_way_idx = 5;
        else if ((way_hits & 8'h40) != 0) hit_way_idx = 6;
        else if ((way_hits & 8'h80) != 0) hit_way_idx = 7;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) lru_counter <= 0;
        else if (state == COMPARE && !hit_valid) lru_counter <= lru_counter + 1;
    end
    assign victim_way = lru_counter;
    
    logic [TAG_ENTRY_WIDTH-1:0] victim_tag_entry;
    assign victim_tag_entry = tag_rdata[victim_way];
    
    assign victim_dirty = (victim_tag_entry >> (TAG_WIDTH+1)) & 1'b1;
    assign victim_tag   = victim_tag_entry[TAG_WIDTH-1:0];
    assign victim_data  = data_rdata[victim_way];

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] { IDLE, COMPARE, WRITEBACK_START, WRITEBACK_WAIT, FILL_REQ, FILL_WAIT, UPDATE } state_t;
    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else begin
            if (state != next_state) $display("[%s] State Change to %d", CACHE_NAME, next_state);
            state <= next_state;
        end
    end

    // Local signals for struct inputs/outputs
    logic [ADDR_WIDTH-1:0]      prev_req_addr;
    logic [CACHE_LINE_SIZE-1:0] prev_req_line_data;
    cmd_t                       prev_req_cmd;
    logic                       prev_req_valid;
    
    assign prev_req_addr      = prev_req_i.addr;
    assign prev_req_line_data = prev_req_i.line_data;
    assign prev_req_cmd       = prev_req_i.cmd;
    assign prev_req_valid     = prev_req_i.valid;

    logic [DATA_WIDTH-1:0]      next_resp_data;
    logic [CACHE_LINE_SIZE-1:0] next_resp_line_data;
    logic                       next_resp_ready;
    logic                       next_resp_valid;
    
    assign next_resp_data      = next_resp_i.data;
    assign next_resp_line_data = next_resp_i.line_data;
    assign next_resp_ready     = next_resp_i.ready;
    assign next_resp_valid     = next_resp_i.valid;

    logic                  prev_resp_ready;
    logic                  prev_resp_valid;
    logic [DATA_WIDTH-1:0] prev_resp_data;
    logic [CACHE_LINE_SIZE-1:0] prev_resp_line_data;
    
    logic [ADDR_WIDTH-1:0]      next_req_addr;
    logic [DATA_WIDTH-1:0]      next_req_data;
    logic [CACHE_LINE_SIZE-1:0] next_req_line_data;
    cmd_t                       next_req_cmd;
    logic                       next_req_valid;
    logic                       next_req_is_burst;

    assign prev_resp_o = {prev_resp_data, prev_resp_line_data, prev_resp_ready, prev_resp_valid, 1'b0};
    assign next_req_o  = {next_req_addr, next_req_data, next_req_line_data, next_req_cmd, next_req_valid, next_req_is_burst, 4'hF};


    always @(*) begin
        next_state = state;
        prev_resp_ready = 0;
        prev_resp_valid = 0;
        prev_resp_data  = 0;
        prev_resp_line_data = 0;

        next_req_valid  = 0;
        next_req_cmd    = READ;
        next_req_addr   = 0;
        next_req_data   = 0;
        next_req_line_data = 0;
        next_req_is_burst = 0;
        
        array_we[0] = 0;
        array_we[1] = 0;
        array_we[2] = 0;
        array_we[3] = 0;
        array_we[4] = 0;
        array_we[5] = 0;
        array_we[6] = 0;
        array_we[7] = 0;
        tag_wdata = 0;
        data_wdata = 0;

        case (state)
            IDLE: begin
                prev_resp_ready = 1;
                if (prev_req_valid) next_state = COMPARE;
            end

            COMPARE: begin
                if (hit_valid) begin
                    // ---- HIT ----
                    prev_resp_valid = 1;
                    if (prev_req_cmd == WRITE) begin
                        array_we[hit_way_idx] = 1;
                        tag_wdata = {1'b1, 1'b1, req_tag}; // Mark Dirty
                        data_wdata = prev_req_line_data; // Full line write from L1/L2
                        prev_resp_ready = 1;
                        next_state = IDLE;
                    end else begin
                        // Read
                        prev_resp_line_data = data_rdata[hit_way_idx];
                        prev_resp_ready = 1;
                        next_state = IDLE;
                    end
                end else begin
                    // ---- MISS ----
                    if (victim_dirty) next_state = WRITEBACK_START;
                    else next_state = FILL_REQ;
                end
            end

            WRITEBACK_START: begin
                next_req_valid = 1;
                next_req_cmd   = WRITE;
                next_req_addr  = {victim_tag, req_index, {OFFSET_WIDTH{1'b0}}};
                next_req_is_burst = 1;
                next_req_line_data = victim_data;
                if (next_resp_ready) next_state = FILL_REQ; // Or wait for data done?
                // Assuming blocking write for simplicity
                else next_state = WRITEBACK_WAIT; 
            end
            
            WRITEBACK_WAIT: begin
                 // Wait for downstream to accept write
                 next_req_valid = 1;
                 next_req_cmd   = WRITE;
                 // (Simplified repetition of signals)
                 next_req_addr  = {victim_tag, req_index, {OFFSET_WIDTH{1'b0}}};
                 next_req_is_burst = 1;
                 next_req_line_data = victim_data;
                 
                 if (next_resp_ready) next_state = FILL_REQ;
            end

            FILL_REQ: begin
                next_req_valid = 1;
                next_req_cmd   = READ;
                next_req_addr  = prev_req_addr;
                next_req_is_burst = 1;
                if (next_resp_ready) next_state = FILL_WAIT; // Accepted
            end

            FILL_WAIT: begin
                 // Wait for data return
                 // We might need to keep req high? AXI vs Simple Handshake.
                 // Assuming simple: keep REQ high until READY (which happened in FILL_REQ).
                 // Now waiting for VALID.
                 if (next_resp_valid) begin
                     // Support for Slave Latency
                     array_we[victim_way] = 1;
                     tag_wdata = {1'b0, 1'b1, req_tag}; // Clean
                     data_wdata = next_resp_line_data;
                     next_state = UPDATE; // Wait for RAM
                 end
            end
            
            UPDATE: begin
                next_state = COMPARE;
            end
        endcase
    end

endmodule
