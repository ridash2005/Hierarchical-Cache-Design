module l2_cache (
    input logic clk,
    input logic rst_n,
    
    // Interface from L1 Arbiter
    mem_if.slave  prev_port,
    
    // Interface to L3
    mem_if.master next_port
);
    import cache_pkg::*;

    // Parameterized Instantiation of Unified Cache
    unified_cache #(
        .SIZE_KB(L2_SIZE_KB), // 256 KB
        .ASSOC(L2_ASSOC)      // 8-Way
    ) u_unified_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .prev_port(prev_port),
        .next_port(next_port)
    );

endmodule
