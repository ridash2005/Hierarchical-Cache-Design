module l1_cache (
    input logic clk,
    input logic rst_n,
    
    // CPU Interface
    mem_if.slave  cpu_port,
    
    // Lower Level Cache Interface (L2)
    mem_if.master mem_port
);
    import cache_pkg::*;

    // -------------------------------------------------------------------------
    // Parameters & Signals
    // -------------------------------------------------------------------------
    localparam NUM_SETS  = L1_SETS;
    localparam NUM_WAYS  = L1_ASSOC;
    localparam TAG_BITS  = L1_TAG_WIDTH;
    localparam LINE_BITS = CACHE_LINE_SIZE;
    
    // Address decoding
    logic [L1_INDEX_WIDTH-1:0]  req_index;
    logic [L1_TAG_WIDTH-1:0]    req_tag;
    logic [L1_OFFSET_WIDTH-1:0] req_offset; // Byte offset
    
    assign req_index  = cpu_port.req.addr[L1_INDEX_WIDTH + L1_OFFSET_WIDTH - 1 : L1_OFFSET_WIDTH];
    assign req_tag    = cpu_port.req.addr[ADDR_WIDTH - 1 : ADDR_WIDTH - L1_TAG_WIDTH];
    assign req_offset = cpu_port.req.addr[L1_OFFSET_WIDTH - 1 : 0];

    // Array Types
    // Tag Entry: {Dirty, Valid, Tag}
    localparam TAG_ENTRY_WIDTH = 1 + 1 + TAG_BITS; 
    
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
    
    // PLRU State
    logic [NUM_WAYS-2:0] plru_bits [NUM_SETS-1:0];
    logic [$clog2(NUM_WAYS)-1:0] victim_way;
    
    // -------------------------------------------------------------------------
    // FSM States
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        COMPARE,
        ALLOCATE_WAIT,
        WRITEBACK,
        UPDATE
    } state_t;
    
    state_t state, next_state;

    // -------------------------------------------------------------------------
    // Instantiate Arrays (SRAMs)
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_WAYS; i++) begin : ways
            // Tag Array
            sram_array #(
                .WIDTH(TAG_ENTRY_WIDTH),
                .DEPTH(NUM_SETS)
            ) tag_ram (
                .clk(clk),
                .rst_n(rst_n),
                .we(array_we[i]),
                .addr(req_index),
                .wdata(tag_wdata),
                .rdata(tag_rdata[i])
            );
            
            // Data Array
            sram_array #(
                .WIDTH(LINE_BITS),
                .DEPTH(NUM_SETS)
            ) data_ram (
                .clk(clk),
                .rst_n(rst_n),
                .we(array_we[i]),
                .addr(req_index),
                .wdata(data_wdata), // Need logic to merge word writes
                .rdata(data_rdata[i])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Tag Comparison & Hit Detection
    // -------------------------------------------------------------------------
    always_comb begin
        way_hit = 0;
        hit_valid = 0;
        hit_way_idx = 0;
        for (int k = 0; k < NUM_WAYS; k++) begin
            if (tag_rdata[k][TAG_BITS] == 1'b1 && // Valid bit check
                tag_rdata[k][TAG_BITS-1:0] == req_tag) begin
                way_hit[k] = 1'b1;
                hit_valid = 1'b1;
                hit_way_idx = k[$clog2(NUM_WAYS)-1:0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // LRU / Victim Selection (Pseudo-LRU for 4-way)
    // -------------------------------------------------------------------------
    // Simple Modulo Counter for replacement if too complex (Fallback)
    // Implementing a true PLRU for N-way is complex.
    // For now, let's use a simple counter for victim selection to simplify demonstration.
    // Ideally we track access history. 
    logic [$clog2(NUM_WAYS)-1:0] lru_counter;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) lru_counter <= 0;
        else if (state == COMPARE && !hit_valid) lru_counter <= lru_counter + 1;
    end
    assign victim_way = lru_counter; 
    
    // Check if victim is dirty
    logic victim_dirty;
    logic [TAG_BITS-1:0] victim_tag;
    logic [LINE_BITS-1:0] victim_data;
    
    assign victim_dirty = tag_rdata[victim_way][TAG_BITS+1]; // Bit after valid
    assign victim_tag   = tag_rdata[victim_way][TAG_BITS-1:0];
    assign victim_data  = data_rdata[victim_way];

    // -------------------------------------------------------------------------
    // Controller FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        
        // Default Outputs
        cpu_port.resp.ready = 0;
        cpu_port.resp.valid = 0;
        cpu_port.resp.data  = 0;
        
        mem_port.req.valid  = 0;
        mem_port.req.cmd    = READ;
        mem_port.req.addr   = 0;
        
        // Array Write Signals Default
        for(int k=0; k<NUM_WAYS; k++) begin
            array_we[k] = 0;
        end
        tag_wdata = 0;
        data_wdata = 0;

        case (state)
            IDLE: begin
                cpu_port.resp.ready = 1;
                if (cpu_port.req.valid) begin
                    next_state = COMPARE;
                end
            end

            COMPARE: begin
                // Wait one cycle for RAM read (Synchronous Read)
                // In next cycle, tag_rdata is valid.
                // NOTE: Detailed timing usually requires pipelining.
                // Assuming standard 1-cycle latency, we stay here for 1 cycle?
                // Actually, if we accepted in IDLE, the valid addr went to SRAM.
                // So in this cycle (COMPARE), data IS available.
                
                if (hit_valid) begin
                    // ---- HIT CASE ----
                    cpu_port.resp.valid = 1;
                    
                    if (cpu_port.req.cmd == WRITE) begin
                        // Update Data
                        array_we[hit_way_idx] = 1;
                        // Construct new line data
                        // NOTE: Simplified: Assuming word aligned access for now
                        // Real design needs byte masking
                        tag_wdata = {1'b1, 1'b1, req_tag}; // Set Dirty, Valid, Tag
                        
                        // Modify just the word
                        // Real implementation needs to read old line, modify word, write back OR have byte enable support in SRAM
                        // For this demo, let's assume we can construct the mask logic here.
                        // Ideally SRAM should support byte enables or we read-modify-write.
                        // Since we just read it (data_rdata), we can MUX it.
                        data_wdata = data_rdata[hit_way_idx];
                        // Insert 32-bit word at correct offset
                        // [Offset*8 +: 32]
                         data_wdata[req_offset*8 +: 32] = cpu_port.req.data;
                         
                         cpu_port.resp.ready = 1; // Done
                         next_state = IDLE;
                    end else begin
                        // READ
                        cpu_port.resp.data = data_rdata[hit_way_idx][req_offset*8 +: 32];
                        cpu_port.resp.ready = 1; // Done
                        next_state = IDLE;
                    end
                end else begin
                    // ---- MISS CASE ----
                    if (victim_dirty) begin
                        next_state = WRITEBACK;
                    end else begin
                         next_state = ALLOCATE_WAIT;
                    end
                end
            end

            WRITEBACK: begin
                // Write dirty line to L2
                mem_port.req.valid    = 1;
                mem_port.req.cmd      = WRITE;
                mem_port.req.addr     = {victim_tag, req_index, {L1_OFFSET_WIDTH{1'b0}}}; // Reconstruct Addr
                mem_port.req.is_burst = 1; // Line write
                mem_port.req.line_data= victim_data;
                
                if (mem_port.resp.ready) begin
                    next_state = ALLOCATE_WAIT;
                end
            end

            ALLOCATE_WAIT: begin
                // Read new line from L2
                mem_port.req.valid    = 1;
                mem_port.req.cmd      = READ;
                mem_port.req.addr     = cpu_port.req.addr; // Original Addr
                mem_port.req.is_burst = 1;
                
                if (mem_port.resp.valid) begin
                    // We got the data from L2
                    // Write to Victim Way
                    array_we[victim_way] = 1;
                    tag_wdata = {1'b0, 1'b1, req_tag}; // Clean, Valid, New Tag
                    data_wdata = mem_port.resp.line_data;
                    
                    // Go back to Compare to service the request (Retry) or just finish here
                    next_state = COMPARE; 
                end
            end
        endcase
    end

endmodule
