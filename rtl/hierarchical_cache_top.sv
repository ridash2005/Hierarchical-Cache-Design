import cache_pkg::*;

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
    // Connectors (Local Structs replace Interfaces for Icarus compatibility)
    // -------------------------------------------------------------------------
    
    // L1I <-> Arbiter
    cache_req_t  l1i_mem_req;
    cache_resp_t l1i_mem_resp;
    
    // L1D <-> Arbiter
    cache_req_t  l1d_mem_req;
    cache_resp_t l1d_mem_resp;

    // Arbiter <-> L2
    cache_req_t  l1_arb_req;
    cache_resp_t l1_arb_resp;
    
    // L2 <-> L3
    cache_req_t  l2_l3_req;
    cache_resp_t l2_l3_resp;

    // L3 <-> Mem
    cache_req_t  l3_mem_req;
    cache_resp_t l3_mem_resp;

    // -------------------------------------------------------------------------
    // L1 Caches (Instruction & Data)
    // -------------------------------------------------------------------------
    
    l1_cache u_l1i (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req_i(cpu_l1i_req_i),
        .cpu_resp_o(cpu_l1i_resp_o),
        .mem_req_o(l1i_mem_req),
        .mem_resp_i(l1i_mem_resp)
    );

    l1_cache u_l1d (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req_i(cpu_l1d_req_i),
        .cpu_resp_o(cpu_l1d_resp_o),
        .mem_req_o(l1d_mem_req),
        .mem_resp_i(l1d_mem_resp)
    );

    // -------------------------------------------------------------------------
    // Arbiter (L1s -> L2)
    // -------------------------------------------------------------------------
    mem_arbiter_2to1 u_l1_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .in0_req_i(l1d_mem_req),
        .in0_resp_o(l1d_mem_resp),
        .in1_req_i(l1i_mem_req),
        .in1_resp_o(l1i_mem_resp),
        .out_req_o(l1_arb_req),
        .out_resp_i(l1_arb_resp)
    );

    // -------------------------------------------------------------------------
    // L2 Cache (Unified)
    // -------------------------------------------------------------------------
    unified_cache #(
        .SIZE_KB(L2_SIZE_KB),
        .ASSOC(L2_ASSOC),
        .CACHE_NAME("L2")
    ) u_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .prev_req_i(l1_arb_req),
        .prev_resp_o(l1_arb_resp),
        .next_req_o(l2_l3_req),
        .next_resp_i(l2_l3_resp)
    );

    // -------------------------------------------------------------------------
    // L3 Cache (Unified)
    // -------------------------------------------------------------------------
    unified_cache #(
        .SIZE_KB(L3_SIZE_KB),
        .ASSOC(L3_ASSOC),
        .CACHE_NAME("L3")
    ) u_l3 (
        .clk(clk),
        .rst_n(rst_n),
        .prev_req_i(l2_l3_req),
        .prev_resp_o(l2_l3_resp),
        .next_req_o(l3_mem_req),
        .next_resp_i(l3_mem_resp)
    );

    // -------------------------------------------------------------------------
    // Memory Interface
    // -------------------------------------------------------------------------
    assign mem_req_o = l3_mem_req;
    assign l3_mem_resp = mem_resp_i;

endmodule
