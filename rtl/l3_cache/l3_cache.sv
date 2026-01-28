module l3_cache (
    input logic clk,
    input logic rst_n,
    
    // Interface from L2
    mem_if.slave  prev_port,
    
    // Interface to Main Memory
    mem_if.master next_port
);
    import cache_pkg::*;

    // Parameterized Instantiation of Unified Cache
    unified_cache #(
        .SIZE_KB(8196), // 8MB for example, or based on pkg
        .ASSOC(16)      // 16-Way
    ) u_unified_l3 (
        .clk(clk),
        .rst_n(rst_n),
        .prev_port(prev_port),
        .next_port(next_port)
    );

endmodule
