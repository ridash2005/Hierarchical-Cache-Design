module hierarchical_cache_top (
    input logic clk,
    input logic rst_n,

    // CPU Interface (L1)
    // We separate I and D for Harvard Architecture at L1
    input  cache_req_t  cpu_l1i_req_i,
    output cache_resp_t cpu_l1i_resp_o,
    
    input  cache_req_t  cpu_l1d_req_i,
    output cache_resp_t cpu_l1d_resp_o,

    // Main Memory Interface (From L3)
    output cache_req_t  mem_req_o,
    input  cache_resp_t mem_resp_i
);
    
    // -------------------------------------------------------------------------
    // Connectors
    // -------------------------------------------------------------------------
    
    // L1 -> L2 Interconnect
    mem_if l1i_if  (clk, rst_n);
    mem_if l1d_if  (clk, rst_n);
    mem_if l1_arb_out_if (clk, rst_n);
    
    // L2 -> L3 Interconnect
    mem_if l2_if (clk, rst_n);
    
    // L3 -> Mem Interconnect
    mem_if l3_mem_if (clk, rst_n);

    // -------------------------------------------------------------------------
    // L1 Caches (Instruction & Data)
    // -------------------------------------------------------------------------
    
    // Connect IO Request structs to Interface
    assign l1i_if.req = cpu_l1i_req_i;
    assign cpu_l1i_resp_o = l1i_if.resp;
    
    mem_if l1i_mem_port (clk, rst_n);
    
    l1_cache u_l1i (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_port(l1i_if), // CPU <-> L1I
        .mem_port(l1i_mem_port) // L1I <-> Arbiter
    );

    // D-Cache
    assign l1d_if.req = cpu_l1d_req_i;
    assign cpu_l1d_resp_o = l1d_if.resp;
    
    mem_if l1d_mem_port (clk, rst_n);
    
    l1_cache u_l1d (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_port(l1d_if), // CPU <-> L1D
        .mem_port(l1d_mem_port) // L1D <-> Arbiter
    );

    // -------------------------------------------------------------------------
    // Arbiter (L1s -> L2)
    // -------------------------------------------------------------------------
    mem_arbiter_2to1 u_l1_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .in0(l1d_mem_port), // Data Cache Priority usually higher? Or equal.
        .in1(l1i_mem_port),
        .out(l1_arb_out_if)
    );

    // -------------------------------------------------------------------------
    // L2 Cache
    // -------------------------------------------------------------------------
    l2_cache u_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .prev_port(l1_arb_out_if),
        .next_port(l2_if)
    );

    // -------------------------------------------------------------------------
    // L3 Cache
    // -------------------------------------------------------------------------
    l3_cache u_l3 (
        .clk(clk),
        .rst_n(rst_n),
        .prev_port(l2_if),
        .next_port(l3_mem_if)
    );

    // -------------------------------------------------------------------------
    // Memory Interface
    // -------------------------------------------------------------------------
    assign mem_req_o = l3_mem_if.req;
    assign l3_mem_if.resp = mem_resp_i;

endmodule
