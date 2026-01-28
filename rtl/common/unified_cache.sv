module unified_cache #(
    parameter SIZE_KB = 256,
    parameter ASSOC   = 8
)(
    input logic clk,
    input logic rst_n,
    
    // Upstream Interface (From L1 or L2)
    mem_if.slave  prev_port,
    
    // Downstream Interface (To L3 or Memory)
    mem_if.master next_port
);
    import cache_pkg::*;

    // -------------------------------------------------------------------------
    // Parameters & Signals
    // -------------------------------------------------------------------------
    localparam NUM_SETS  = (SIZE_KB * 1024 * 8) / (ASSOC * CACHE_LINE_SIZE);
    localparam NUM_WAYS  = ASSOC;
    localparam INDEX_WIDTH = $clog2(NUM_SETS);
    localparam OFFSET_WIDTH = $clog2(CACHE_LINE_SIZE/8);
    localparam TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;
    
    // Address decoding
    logic [INDEX_WIDTH-1:0]  req_index;
    logic [TAG_WIDTH-1:0]    req_tag;
    
    assign req_index  = prev_port.req.addr[INDEX_WIDTH + OFFSET_WIDTH - 1 : OFFSET_WIDTH];
    assign req_tag    = prev_port.req.addr[ADDR_WIDTH - 1 : ADDR_WIDTH - TAG_WIDTH];

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
    always_comb begin
        way_hit = 0;
        hit_valid = 0;
        hit_way_idx = 0;
        for (int k = 0; k < NUM_WAYS; k++) begin
            if (tag_rdata[k][TAG_WIDTH] == 1'b1 && // Valid
                tag_rdata[k][TAG_WIDTH-1:0] == req_tag) begin
                way_hit[k] = 1'b1;
                hit_valid = 1'b1;
                hit_way_idx = k[$clog2(NUM_WAYS)-1:0];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) lru_counter <= 0;
        else if (state == COMPARE && !hit_valid) lru_counter <= lru_counter + 1;
    end
    assign victim_way = lru_counter;
    
    assign victim_dirty = tag_rdata[victim_way][TAG_WIDTH+1];
    assign victim_tag   = tag_rdata[victim_way][TAG_WIDTH-1:0];
    assign victim_data  = data_rdata[victim_way];

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] { IDLE, COMPARE, WRITEBACK_START, WRITEBACK_WAIT, FILL_REQ, FILL_WAIT } state_t;
    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        prev_port.resp.ready = 0;
        prev_port.resp.valid = 0;
        prev_port.resp.data  = 0;  // Don't care for line ops usually
        prev_port.resp.line_data = 0;

        next_port.req.valid  = 0;
        next_port.req.cmd    = READ;
        next_port.req.addr   = 0;
        
        for(int k=0; k<NUM_WAYS; k++) array_we[k] = 0;
        tag_wdata = 0;
        data_wdata = 0;

        case (state)
            IDLE: begin
                prev_port.resp.ready = 1;
                if (prev_port.req.valid) next_state = COMPARE;
            end

            COMPARE: begin
                if (hit_valid) begin
                    // ---- HIT ----
                    prev_port.resp.valid = 1;
                    if (prev_port.req.cmd == WRITE) begin
                        array_we[hit_way_idx] = 1;
                        tag_wdata = {1'b1, 1'b1, req_tag}; // Mark Dirty
                        data_wdata = prev_port.req.line_data; // Full line write from L1/L2
                        prev_port.resp.ready = 1;
                        next_state = IDLE;
                    end else begin
                        // Read
                        prev_port.resp.line_data = data_rdata[hit_way_idx];
                        prev_port.resp.ready = 1;
                        next_state = IDLE;
                    end
                end else begin
                    // ---- MISS ----
                    if (victim_dirty) next_state = WRITEBACK_START;
                    else next_state = FILL_REQ;
                end
            end

            WRITEBACK_START: begin
                next_port.req.valid = 1;
                next_port.req.cmd   = WRITE;
                next_port.req.addr  = {victim_tag, req_index, {OFFSET_WIDTH{1'b0}}};
                next_port.req.is_burst = 1;
                next_port.req.line_data= victim_data;
                if (next_port.resp.ready) next_state = FILL_REQ; // Or wait for data done?
                // Assuming blocking write for simplicity
                else next_state = WRITEBACK_WAIT; 
            end
            
            WRITEBACK_WAIT: begin
                 // Wait for downstream to accept write
                 next_port.req.valid = 1;
                 next_port.req.cmd   = WRITE;
                 // (Simplified repetition of signals)
                 next_port.req.addr  = {victim_tag, req_index, {OFFSET_WIDTH{1'b0}}};
                 next_port.req.is_burst = 1;
                 next_port.req.line_data= victim_data;
                 
                 if (next_port.resp.ready) next_state = FILL_REQ;
            end

            FILL_REQ: begin
                next_port.req.valid = 1;
                next_port.req.cmd   = READ;
                next_port.req.addr  = prev_port.req.addr;
                next_port.req.is_burst = 1;
                if (next_port.resp.ready) next_state = FILL_WAIT; // Accepted
            end

            FILL_WAIT: begin
                 // Wait for data return
                 // We might need to keep req high? AXI vs Simple Handshake.
                 // Assuming simple: keep REQ high until READY (which happened in FILL_REQ).
                 // Now waiting for VALID.
                 if (next_port.resp.valid) begin
                     // Support for Slave Latency
                     array_we[victim_way] = 1;
                     tag_wdata = {1'b0, 1'b1, req_tag}; // Clean
                     data_wdata = next_port.resp.line_data;
                     next_state = COMPARE; // Retry
                 end
            end
        endcase
    end

endmodule
