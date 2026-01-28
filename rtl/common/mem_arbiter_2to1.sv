module mem_arbiter_2to1 (
    input logic clk,
    input logic rst_n,
    
    mem_if.slave  in0, // Priority 1
    mem_if.slave  in1, // Priority 2
    mem_if.master out
);

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
                if (in0.req.valid) begin
                    state <= GRANT0;
                    busy  <= 1;
                end else if (in1.req.valid) begin
                    state <= GRANT1;
                    busy  <= 1;
                end
            end else begin
                // We are busy, wait for transaction to complete
                // In our simple cache, transaction ends when `resp.valid` is high
                if (out.resp.valid) begin
                    busy <= 0;
                end
            end
        end
    end

    // Mux Logic
    always_comb begin
        // Defaults
        in0.resp.valid     = 0;
        in0.resp.ready     = 0;
        in0.resp.data      = 0;
        in0.resp.line_data = 0;
        
        in1.resp.valid     = 0;
        in1.resp.ready     = 0;
        in1.resp.data      = 0;
        in1.resp.line_data = 0;
        
        out.req.valid      = 0;
        out.req.cmd        = cache_pkg::READ;
        out.req.addr       = 0;
        out.req.data       = 0;
        out.req.line_data  = 0;
        out.req.is_burst   = 0;
        
        case (state)
            GRANT0: begin
                // Pass Req 0 -> Out
                if (busy) begin
                    out.req = in0.req;
                    // Pass Resp Out -> 0
                    in0.resp = out.resp;
                end
            end
            GRANT1: begin
                if (busy) begin
                    out.req = in1.req;
                    in1.resp = out.resp;
                end
            end
        endcase
    end

endmodule
