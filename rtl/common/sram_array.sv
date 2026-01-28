module sram_array #(
    parameter WIDTH = 32,
    parameter DEPTH = 64
) (
    input  logic                 clk,
    input  logic                 rst_n, // Not typically used for SRAM content, but for simulation init
    input  logic                 we,
    input  logic [$clog2(DEPTH)-1:0] addr,
    input  logic [WIDTH-1:0]     wdata,
    output logic [WIDTH-1:0]     rdata
);

    // Memory Array
    logic [WIDTH-1:0] mem [DEPTH-1:0];

    // Synchronous Write / Asynchronous Read (or Sync Read)
    // Standard Block RAMs usually have Sync Read. Let's model Sync Read.
    
    always_ff @(posedge clk) begin
        if (we) begin
            mem[addr] <= wdata;
        end
        rdata <= mem[addr];
    end

    // Simulation Clean init
    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = 0;
        end
    end

endmodule
