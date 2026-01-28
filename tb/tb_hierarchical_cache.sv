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

    always @(posedge clk) begin
        mem_resp.valid <= 0;
        mem_resp.ready <= 1; // Always ready to accept request in this simple model
        
        if (mem_req.valid) begin
            if (mem_req.cmd == WRITE) begin
                // Write Line to Memory
                // Assuming byte aligned linear write for line
                for (int i=0; i < CACHE_LINE_SIZE/8; i++) begin
                    memory[mem_req.addr + i] = mem_req.line_data[i*8 +: 8];
                end
                mem_resp.valid <= 1; // Acknowledge write done
            end else if (mem_req.cmd == READ) begin
                // Read Line from Memory
                for (int i=0; i < CACHE_LINE_SIZE/8; i++) begin
                    mem_resp.line_data[i*8 +: 8] = memory[mem_req.addr + i];
                end
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
        
        // Wait for ready
        do @(posedge clk); while (!cpu_l1d_resp.ready);
        
        cpu_l1d_req.valid = 0;
        
        // Wait for completion (valid)
        // do @(posedge clk); while (!cpu_l1d_resp.valid); // Handled in Cache Logic immediately for Write Hit?
        $display("[CPU] Write Complete");
    endtask

    task cpu_read_word(input [31:0] addr, output [31:0] data);
        $display("[CPU] Read Addr: %h", addr);
        cpu_l1d_req.valid = 1;
        cpu_l1d_req.cmd   = READ;
        cpu_l1d_req.addr  = addr;
        cpu_l1d_req.is_burst = 0;
        
        // Wait for ready
        do @(posedge clk); while (!cpu_l1d_resp.ready);
        cpu_l1d_req.valid = 0;
        
        // Wait for Data
        while (!cpu_l1d_resp.valid) @(posedge clk);
        
        data = cpu_l1d_resp.data;
        $display("[CPU] Read Return: %h", data);
    endtask

    // -------------------------------------------------------------------------
    // Test Scenario
    // -------------------------------------------------------------------------
    logic [31:0] read_data;

    initial begin
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
         
        // 5. Conflict Miss / Eviction (Capacity testing needs massive access pattern)
        // Testing basic flow here.
        
        $display("----------------------------------------------------------------");
        $display("Test Complete");
        $display("----------------------------------------------------------------");
        $finish;
    end

endmodule
