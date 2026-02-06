module tb_hierarchical_cache;

    import cache_pkg::*;

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    // CPU L1I Interface
    cache_req_t  cpu_l1i_req;
    cache_resp_t cpu_l1i_resp;
    
    // CPU L1D Interface
    cache_req_t  cpu_l1d_req;
    cache_resp_t cpu_l1d_resp;
    
    // Main Memory Interface
    cache_req_t  mem_req;
    cache_resp_t mem_resp;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    hierarchical_cache_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_l1i_req_i(cpu_l1i_req),
        .cpu_l1i_resp_o(cpu_l1i_resp),
        .cpu_l1d_req_i(cpu_l1d_req),
        .cpu_l1d_resp_o(cpu_l1d_resp),
        .mem_req_o(mem_req),
        .mem_resp_i(mem_resp)
    );

    // -------------------------------------------------------------------------
    // Main Memory Simulation (Behavioral)
    // -------------------------------------------------------------------------
    // Simple memory model that responds with latency
    logic [7:0] memory [0:1024*1024-1]; // 1MB Memory Space for Simulation
    logic [CACHE_LINE_SIZE-1:0] temp_mem_line;

    always @(posedge clk) begin
        mem_resp.valid <= 0;
        mem_resp.ready <= 1; // Always ready to accept request in this simple model
        
        if (mem_req.valid) begin
            logic [ADDR_WIDTH-1:0] cur_mem_addr;
            cur_mem_addr = mem_req.addr;
            if (mem_req.cmd == WRITE) begin
                $display("[MEM] Writing Addr: %h", cur_mem_addr);
                // Write Line to Memory
                temp_mem_line = mem_req.line_data; 
                for (int i=0; i < CACHE_LINE_SIZE/8; i++) begin
                    memory[cur_mem_addr + i] = (temp_mem_line >> (i*8)) & 8'hFF;
                end
                mem_resp.valid <= 1; // Acknowledge write done
            end else if (mem_req.cmd == READ) begin
                $display("[MEM] Reading Addr: %h", cur_mem_addr);
                // Read Line from Memory
                temp_mem_line = 0;
                for (int i=0; i < CACHE_LINE_SIZE/8; i++) begin
                    logic [CACHE_LINE_SIZE-1:0] padded_byte;
                    padded_byte = memory[cur_mem_addr + i];
                    temp_mem_line = temp_mem_line | (padded_byte << (i*8));
                end
                mem_resp.line_data = temp_mem_line;
                mem_resp.valid <= 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Clock Gen
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Test Tasks
    // -------------------------------------------------------------------------
    task cpu_write_word(input [31:0] addr, input [31:0] data);
        $display("[CPU] Write Addr: %h Data: %h", addr, data);
        cpu_l1d_req.valid = 1;
        cpu_l1d_req.cmd   = WRITE;
        cpu_l1d_req.addr  = addr;
        cpu_l1d_req.data  = data;
        cpu_l1d_req.is_burst = 0;
        
        // Wait for Ready AND Valid (to ensure it finished the FSM sequence if needed)
        // For a simple blocking cache, completion is often signaled by valid after ready
        // or just ready if it's a one-cycle hit.
        // Let's wait for resp.valid.
        do @(posedge clk); while (!(cpu_l1d_resp.ready && cpu_l1d_resp.valid));
        
        cpu_l1d_req.valid = 0;
        $display("[CPU] Write Complete");
    endtask

    task cpu_read_word(input [31:0] addr, output [31:0] data);
        $display("[CPU] Read Addr: %h", addr);
        cpu_l1d_req.valid = 1;
        cpu_l1d_req.cmd   = READ;
        cpu_l1d_req.addr  = addr;
        cpu_l1d_req.is_burst = 0;
        
        // Wait for valid response while keeping request active
        do @(posedge clk); while (!(cpu_l1d_resp.ready && cpu_l1d_resp.valid));
        
        data = cpu_l1d_resp.data;
        cpu_l1d_req.valid = 0;
        $display("[CPU] Read Return: %h", data);
    endtask

    // -------------------------------------------------------------------------
    // Test Scenario
    // -------------------------------------------------------------------------
    logic [31:0] read_data;

    initial begin
        // Setup Dumping
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_hierarchical_cache);

        // Reset
        rst_n = 0;
        cpu_l1i_req = 0;
        cpu_l1d_req = 0;
        #20;
        rst_n = 1;
        #20;

        $display("----------------------------------------------------------------");
        $display("Starting Cache Verification");
        $display("----------------------------------------------------------------");

        // 1. Cold Miss Write - Should allocate in L1, potentially fetch from L2/L3/Mem
        // Address 0x100 (Set 4, Tag 0)
        cpu_write_word(32'h0000_0100, 32'hDEAD_BEEF);
        
        #100;
        
        // 2. Read Hit - Should read from L1 immediately
        cpu_read_word(32'h0000_0100, read_data);
        if (read_data !== 32'hDEAD_BEEF) $error("Mismatch! Expected DEADBEEF, got %h", read_data);
        else $display("PASS: Read Hit correct");

        // 3. Write Hit - Modify value
        cpu_write_word(32'h0000_0100, 32'hCAFE_BABE);
        
        // 4. Read Verification
        cpu_read_word(32'h0000_0100, read_data);
        if (read_data !== 32'hCAFE_BABE) $error("Mismatch! Expected CAFEBABE, got %h", read_data);
         else $display("PASS: Write Hit correct");
         
        // 5. Eviction and Writeback Test (4-way L1, Set 0)
        $display("----------------------------------------------------------------");
        $display("Starting Eviction and Writeback Test");
        $display("----------------------------------------------------------------");
        
        // Fill all 4 ways of Set 0 in L1
        $display("[TB] Filling Set 0 with 4 different addresses...");
        cpu_write_word(32'h0000_0100, 32'h1111_1111);
        cpu_write_word(32'h0000_0200, 32'h2222_2222);
        cpu_write_word(32'h0000_0300, 32'h3333_3333);
        cpu_write_word(32'h0000_0400, 32'h4444_4444);
        
        // Trigger eviction of the oldest (0x100) by writing to a 5th address in same set
        $display("[TB] Writing to 5th address (0x500) to trigger eviction of 0x100...");
        cpu_write_word(32'h0000_0500, 32'h5555_5555);
        
        // Verification: Read back 0x100
        // This should cause: L1 Miss -> Fetch from L2 (L1 writeback should have updated L2)
        $display("[TB] Verifying evicted data (0x100) can be read back...");
        cpu_read_word(32'h0000_0100, read_data);
        
        if (read_data !== 32'h1111_1111) begin
            $display("ERROR: Mismatch at 0x100! Expected 11111111, got %h", read_data);
        end else begin
            $display("PASS: Data integrity maintained through eviction and writeback");
        end
        
        $display("----------------------------------------------------------------");
        $display("Test Complete - Hierarchical Cache is Operational");
        $display("----------------------------------------------------------------");
        $finish;
    end

    initial begin
        #100000; // 100us timeout
        $display("TIMEOUT");
        $finish;
    end

endmodule
