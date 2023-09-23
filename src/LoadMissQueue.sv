module LoadMissQueue#(parameter SIZE=4)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,

    input wire IN_ready,

    output reg OUT_full,

    input MemController_Res IN_memc,

    input LD_UOp IN_ld,
    input wire IN_enqueue,

    output LD_UOp OUT_ld,
    input wire IN_dequeue
);


// unordered queue
struct packed
{
    logic ready;
    LD_UOp ld;
} queue[SIZE-1:0];

always_comb begin
    reg[$clog2(SIZE):0] free = SIZE;
    for (integer i = 0; i < SIZE; i=i+1) begin
        if (queue[i].ld.valid)
            free = free - 1;
    end
    OUT_full = free == 0;
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        for (integer i = 0; i < SIZE; i=i+1)
            queue[i].ld.valid <= 0;
        OUT_ld.valid <= 0;
    end
    else begin
        
        // Invalidate
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (!(queue[i].ld.external || !IN_branch.taken || $signed(queue[i].ld.sqN - IN_branch.sqN) <= 0))
                queue[i].ld.valid <= 0;
        end

        // Set Ready
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (queue[i].ld.valid) begin
                if (IN_ready)
                    queue[i].ready <= 1;
                
                for (integer j = 0; j < 4; j=j+1) begin
                    if (IN_memc.transfers[j].valid && 
                        IN_memc.transfers[j].readAddr[31:`CLSIZE_E] == queue[i].ld.addr[31:`CLSIZE_E]
                    ) begin
                        queue[i].ready <= IN_memc.transfers[j].progress > 
                            ({1'b0, queue[i].ld.addr[`CLSIZE_E-1:2]} - {1'b0, IN_memc.transfers[j].readAddr[`CLSIZE_E-1:2]});
                    end
                end
            end
        end

        // Enqueue
        if (IN_ld.valid && IN_enqueue && !OUT_full &&
            (IN_ld.external || !IN_branch.taken || $signed(IN_ld.sqN - IN_branch.sqN) <= 0)) begin
            reg enq = 0;
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (!enq && !queue[i].ld.valid) begin
                    enq = 1;
                    queue[i].ld <= IN_ld;
                    assert(IN_ld.exception == AGU_NO_EXCEPTION);
                    queue[i].ld.exception <= AGU_NO_EXCEPTION;
                    // todo: set ready on insert if miss was ignored
                    queue[i].ready <= 0;
                end
            end
        end  

        // Dequeue
        // TODO: dequeue only one op when doing IN_ready dequeue (we can only handle one miss anyways)
        if (IN_dequeue || !(OUT_ld.external || !IN_branch.taken || $signed(OUT_ld.sqN - IN_branch.sqN) <= 0)) begin
            OUT_ld <= 'x;
            OUT_ld.valid <= 0;
        end
        if (!OUT_ld.valid || IN_dequeue) begin
            reg deq = 0;
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (!deq && queue[i].ld.valid && (queue[i].ready) && 
                    (queue[i].ld.external || !IN_branch.taken || $signed(queue[i].ld.sqN - IN_branch.sqN) <= 0)) begin
                    deq = 1;
                    OUT_ld <= queue[i].ld;
                    OUT_ld.exception <= AGU_NO_EXCEPTION;
                    queue[i].ld.valid <= 0;
                end
            end
        end

    end
end

endmodule
