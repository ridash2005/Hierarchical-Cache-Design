import cache_pkg::*;

interface mem_if (input logic clk, input logic rst_n);


    // Signals
    cache_req_t  req;
    cache_resp_t resp;

    // Master Modport (e.g., CPU, previous cache level)
    modport master (
        input  clk, rst_n,
        output req,
        input  resp
    );

    // Slave Modport (e.g., Cache, Memory)
    modport slave (
        input  clk, rst_n,
        input  req,
        output resp
    );

endinterface
