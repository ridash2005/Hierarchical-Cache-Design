import cache_pkg::*;

module mem_arbiter_2to1 (
    input logic clk,
    input logic rst_n,
    
    input  cache_req_t  in0_req_i,
    output cache_resp_t in0_resp_o,
    
    input  cache_req_t  in1_req_i,
    output cache_resp_t in1_resp_o,
    
    output cache_req_t  out_req_o,
    input  cache_resp_t out_resp_i
);

    // Local signals for inputs
    logic in0_req_valid;
    logic [ADDR_WIDTH-1:0] in0_req_addr;
    logic [DATA_WIDTH-1:0] in0_req_data;
    logic [CACHE_LINE_SIZE-1:0] in0_req_line_data;
    cmd_t in0_req_cmd;
    logic in0_req_is_burst;
    
    assign in0_req_valid = in0_req_i.valid;
    assign in0_req_addr = in0_req_i.addr;
    assign in0_req_data = in0_req_i.data;
    assign in0_req_line_data = in0_req_i.line_data;
    assign in0_req_cmd = in0_req_i.cmd;
    assign in0_req_is_burst = in0_req_i.is_burst;

    logic in1_req_valid;
    logic [ADDR_WIDTH-1:0] in1_req_addr;
    logic [DATA_WIDTH-1:0] in1_req_data;
    logic [CACHE_LINE_SIZE-1:0] in1_req_line_data;
    cmd_t in1_req_cmd;
    logic in1_req_is_burst;
    
    assign in1_req_valid = in1_req_i.valid;
    assign in1_req_addr = in1_req_i.addr;
    assign in1_req_data = in1_req_i.data;
    assign in1_req_line_data = in1_req_i.line_data;
    assign in1_req_cmd = in1_req_i.cmd;
    assign in1_req_is_burst = in1_req_i.is_burst;

    logic out_resp_valid;
    logic out_resp_ready;
    logic [DATA_WIDTH-1:0] out_resp_data;
    logic [CACHE_LINE_SIZE-1:0] out_resp_line_data;
    
    assign out_resp_valid = out_resp_i.valid;
    assign out_resp_ready = out_resp_i.ready;
    assign out_resp_data = out_resp_i.data;
    assign out_resp_line_data = out_resp_i.line_data;


    // Local signals for struct outputs
    logic                  in0_resp_ready;
    logic                  in0_resp_valid;
    logic [DATA_WIDTH-1:0] in0_resp_data;
    logic [CACHE_LINE_SIZE-1:0] in0_resp_line_data;
    
    logic                  in1_resp_ready;
    logic                  in1_resp_valid;
    logic [DATA_WIDTH-1:0] in1_resp_data;
    logic [CACHE_LINE_SIZE-1:0] in1_resp_line_data;

    logic [ADDR_WIDTH-1:0]      out_req_addr;
    logic [DATA_WIDTH-1:0]      out_req_data;
    logic [CACHE_LINE_SIZE-1:0] out_req_line_data;
    cmd_t                       out_req_cmd;
    logic                       out_req_valid;
    logic                       out_req_is_burst;

    assign in0_resp_o = {in0_resp_data, in0_resp_line_data, in0_resp_ready, in0_resp_valid, 1'b0};
    assign in1_resp_o = {in1_resp_data, in1_resp_line_data, in1_resp_ready, in1_resp_valid, 1'b0};
    assign out_req_o  = {out_req_addr, out_req_data, out_req_line_data, out_req_cmd, out_req_valid, out_req_is_burst, 4'hF};

    // Simple priority mux
    // State to track who owns the bus to route response back
    typedef enum logic { GRANT0, GRANT1 } state_t;
    state_t state, next_state;

    // Logic:
    // If idle, check in0, then in1.
    // If grant, lock until done? 
    // Since our protocol is Req->Ready (Cmd Phase) and Resp->Valid (Data Phase),
    // and they might be split, a simple arbiter only works if transactions are atomic or we track IDs.
    // Our cache controller blocks until refilled. So transactions are effectively atomic (Req -> ... -> Valid).
    
    // We will lock the arbiter once a request is accepted until response returns?
    // The `mem_if` response `valid` signals completion. 
    
    logic busy;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= GRANT0;
            busy  <= 0;
        end else begin
            if (!busy) begin
                if (in0_req_valid) begin
                    state <= GRANT0;
                    busy  <= 1;
                end else if (in1_req_valid) begin
                    state <= GRANT1;
                    busy  <= 1;
                end
            end else begin
                if (out_resp_valid) begin
                    busy <= 0;
                end
            end
        end
    end

    // Mux Logic
    always_comb begin
        // Defaults
        in0_resp_ready     = 0;
        in0_resp_valid     = 0;
        in0_resp_data      = 0;
        in0_resp_line_data = 0;
        
        in1_resp_ready     = 0;
        in1_resp_valid     = 0;
        in1_resp_data      = 0;
        in1_resp_line_data = 0;
        
        out_req_valid      = 0;
        out_req_cmd        = cache_pkg::READ;
        out_req_addr       = 0;
        out_req_data       = 0;
        out_req_line_data  = 0;
        out_req_is_burst   = 0;
        
        case (state)
            GRANT0: begin
                // Pass Req 0 -> Out
                if (busy) begin
                    out_req_valid = in0_req_valid;
                    out_req_cmd   = in0_req_cmd;
                    out_req_addr  = in0_req_addr;
                    out_req_data  = in0_req_data;
                    out_req_line_data = in0_req_line_data;
                    out_req_is_burst  = in0_req_is_burst;
                    
                    in0_resp_valid     = out_resp_valid;
                    in0_resp_ready     = out_resp_ready;
                    in0_resp_data      = out_resp_data;
                    in0_resp_line_data = out_resp_line_data;
                end
            end
            GRANT1: begin
                if (busy) begin
                    out_req_valid = in1_req_valid;
                    out_req_cmd   = in1_req_cmd;
                    out_req_addr  = in1_req_addr;
                    out_req_data  = in1_req_data;
                    out_req_line_data = in1_req_line_data;
                    out_req_is_burst  = in1_req_is_burst;
                    
                    in1_resp_valid     = out_resp_valid;
                    in1_resp_ready     = out_resp_ready;
                    in1_resp_data      = out_resp_data;
                    in1_resp_line_data = out_resp_line_data;
                end
            end
        endcase
    end

endmodule
