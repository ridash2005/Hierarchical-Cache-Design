import cache_pkg::*;

module l1_cache (
    input logic clk,
    input logic rst_n,
    
    // CPU Interface
    input  cache_req_t  cpu_req_i,
    output cache_resp_t cpu_resp_o,
    
    // Lower Level Cache Interface (L2)
    output cache_req_t  mem_req_o,
    input  cache_resp_t mem_resp_i
);


    // -------------------------------------------------------------------------
    // Parameters & Signals
    // -------------------------------------------------------------------------
    localparam NUM_SETS  = L1_SETS;
    localparam NUM_WAYS  = L1_ASSOC;
    localparam TAG_BITS  = L1_TAG_WIDTH;
    localparam LINE_BITS = CACHE_LINE_SIZE;
    
    // Address decoding
    logic [ADDR_WIDTH-1:0] addr_internal;
    assign addr_internal = cpu_req_i.addr;

    logic [L1_INDEX_WIDTH-1:0]  req_index;
    logic [L1_TAG_WIDTH-1:0]    req_tag;
    logic [L1_OFFSET_WIDTH-1:0] req_offset; // Byte offset
    
    assign req_index  = addr_internal[L1_INDEX_WIDTH + L1_OFFSET_WIDTH - 1 : L1_OFFSET_WIDTH];
    assign req_tag    = addr_internal[ADDR_WIDTH - 1 : ADDR_WIDTH - L1_TAG_WIDTH];
    assign req_offset = addr_internal[L1_OFFSET_WIDTH - 1 : 0];

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
    // Tag Comparison & Hit Detection (Manually unrolled for Icarus compatibility)
    // -------------------------------------------------------------------------
    logic hit_0, hit_1, hit_2, hit_3;
    assign hit_0 = ((tag_rdata[0] >> TAG_BITS) & 1'b1) && ((tag_rdata[0] & ((1 << TAG_BITS)-1)) == req_tag);
    assign hit_1 = ((tag_rdata[1] >> TAG_BITS) & 1'b1) && ((tag_rdata[1] & ((1 << TAG_BITS)-1)) == req_tag);
    assign hit_2 = ((tag_rdata[2] >> TAG_BITS) & 1'b1) && ((tag_rdata[2] & ((1 << TAG_BITS)-1)) == req_tag);
    assign hit_3 = ((tag_rdata[3] >> TAG_BITS) & 1'b1) && ((tag_rdata[3] & ((1 << TAG_BITS)-1)) == req_tag);

    always @(*) begin
        way_hit = 0;
        hit_valid = hit_0 | hit_1 | hit_2 | hit_3;
        hit_way_idx = 0;
        
        if (hit_0) begin way_hit[0] = 1; hit_way_idx = 0; end
        else if (hit_1) begin way_hit[1] = 1; hit_way_idx = 1; end
        else if (hit_2) begin way_hit[2] = 1; hit_way_idx = 2; end
        else if (hit_3) begin way_hit[3] = 1; hit_way_idx = 3; end
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
    
    logic [TAG_ENTRY_WIDTH-1:0] victim_tag_entry;
    assign victim_tag_entry = tag_rdata[victim_way];
    
    assign victim_dirty = (victim_tag_entry >> (TAG_BITS+1)) & 1'b1; // Bit after valid
    assign victim_tag   = victim_tag_entry[TAG_BITS-1:0];
    assign victim_data  = data_rdata[victim_way];

    // -------------------------------------------------------------------------
    // Controller FSM
    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------
    // Controller FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else begin
            if (state != next_state) $display("[L1] State Change to %d", next_state);
            state <= next_state;
        end
    end

    // Local signals for struct inputs/outputs
    logic [ADDR_WIDTH-1:0]      cpu_req_addr;
    logic [DATA_WIDTH-1:0]      cpu_req_data;
    cmd_t                       cpu_req_cmd;
    logic                       cpu_req_valid;
    
    assign cpu_req_addr  = cpu_req_i.addr;
    assign cpu_req_data  = cpu_req_i.data;
    assign cpu_req_cmd   = cpu_req_i.cmd;
    assign cpu_req_valid = cpu_req_i.valid;

    logic [DATA_WIDTH-1:0]      mem_resp_data;
    logic [CACHE_LINE_SIZE-1:0] mem_resp_line_data;
    logic                       mem_resp_ready;
    logic                       mem_resp_valid;
    
    assign mem_resp_data      = mem_resp_i.data;
    assign mem_resp_line_data = mem_resp_i.line_data;
    assign mem_resp_ready     = mem_resp_i.ready;
    assign mem_resp_valid     = mem_resp_i.valid;

    logic [DATA_WIDTH-1:0] cpu_resp_data;
    logic                  cpu_resp_ready;
    logic                  cpu_resp_valid;
    
    logic [ADDR_WIDTH-1:0]      mem_req_addr;
    logic [DATA_WIDTH-1:0]      mem_req_data;
    logic [CACHE_LINE_SIZE-1:0] mem_req_line_data;
    cmd_t                       mem_req_cmd;
    logic                       mem_req_valid;
    logic                       mem_req_is_burst;

    assign cpu_resp_o = {cpu_resp_data, {CACHE_LINE_SIZE{1'b0}}, cpu_resp_ready, cpu_resp_valid, 1'b0};
    assign mem_req_o  = {mem_req_addr, mem_req_data, mem_req_line_data, mem_req_cmd, mem_req_valid, mem_req_is_burst, 4'hF};

    logic [31:0] bit_offset;
    assign bit_offset = {26'b0, req_offset} << 3;


    always @(*) begin
        next_state = state;
        
        // Default Outputs
        cpu_resp_ready = 0;
        cpu_resp_valid = 0;
        cpu_resp_data  = 0;
        
        mem_req_valid  = 0;
        mem_req_cmd    = READ;
        mem_req_addr   = 0;
        mem_req_data   = 0;
        mem_req_line_data = 0;
        mem_req_is_burst = 0;
        
        // Array Write Signals Default
        array_we[0] = 0;
        array_we[1] = 0;
        array_we[2] = 0;
        array_we[3] = 0;
        tag_wdata = 0;
        data_wdata = 0;

        case (state)
            IDLE: begin
                cpu_resp_ready = 1;
                if (cpu_req_valid) begin
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
                    cpu_resp_valid = 1;
                    
                    if (cpu_req_cmd == WRITE) begin
                        // Update Data
                        array_we[hit_way_idx] = 1;
                        tag_wdata = {1'b1, 1'b1, req_tag}; // Set Dirty, Valid, Tag
                        
                        // Mask-based line modification to avoid variable part-select
                        begin
                            logic [LINE_BITS-1:0] write_mask;
                            write_mask = {32{1'b1}};
                            write_mask = write_mask << bit_offset;
                            data_wdata = (data_rdata[hit_way_idx] & ~write_mask) | (({LINE_BITS/32{cpu_req_data}} << bit_offset) & write_mask);
                        end
                         
                        cpu_resp_ready = 1; // Done
                        next_state = IDLE;
                    end else begin
                        // READ using shift to avoid variable part-select
                        cpu_resp_data = (data_rdata[hit_way_idx] >> bit_offset);
                        cpu_resp_ready = 1; // Done
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
                mem_req_valid    = 1;
                mem_req_cmd      = WRITE;
                mem_req_addr     = {victim_tag, req_index, {L1_OFFSET_WIDTH{1'b0}}}; // Reconstruct Addr
                mem_req_is_burst = 1; // Line write
                mem_req_line_data= victim_data;
                
                if (mem_resp_ready) begin
                    next_state = ALLOCATE_WAIT;
                end
            end

            ALLOCATE_WAIT: begin
                // Read new line from L2
                mem_req_valid    = 1;
                mem_req_cmd      = READ;
                mem_req_addr     = cpu_req_addr; // Original Addr
                mem_req_is_burst = 1;
                
                if (mem_resp_valid) begin
                    // We got the data from L2
                    // Write to Victim Way
                    array_we[victim_way] = 1;
                    tag_wdata = {1'b0, 1'b1, req_tag}; // Clean, Valid, New Tag
                    data_wdata = mem_resp_line_data;
                    
                    // Go to UPDATE state to let SRAM read the new data
                    next_state = UPDATE; 
                end
            end

            UPDATE: begin
                // Just wait one cycle for SRAM read to reflect new data
                next_state = COMPARE;
            end
        endcase
    end

endmodule
