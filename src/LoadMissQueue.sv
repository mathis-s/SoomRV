module LoadMissQueue#(parameter SIZE=2, parameter CLSIZE_E=7)
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,

    input wire IN_ready,

    output reg OUT_full,

    input wire IN_cacheLoadActive,
    input wire[CLSIZE_E-2:0] IN_cacheLoadProgress,
    input wire[31-CLSIZE_E:0] IN_cacheLoadAddr,

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
    OUT_full = 1;
    for (integer i = 0; i < SIZE; i=i+1) begin
        if (!queue[i].ld.valid)
            OUT_full = 0;
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        for (integer i = 0; i < SIZE; i=i+1)
            queue[i].ld.valid <= 0;
    end
    else begin
        
        // Invalidate
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (!(queue[i].ld.external || !IN_branch.taken || $signed(queue[i].ld.sqN - IN_branch.sqN) <= 0))
                queue[i].ld.valid <= 0;
        end

        // Set Ready
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (IN_cacheLoadActive && queue[i].ld.valid &&
                queue[i].ld.addr[31:CLSIZE_E] == IN_cacheLoadAddr &&
                {1'b0, queue[i].ld.addr[CLSIZE_E-1:2]} < IN_cacheLoadProgress)
                queue[i].ready <= 1;
        end

        // Enqueue
        if (IN_ld.valid && IN_enqueue && 
            (IN_ld.external || !IN_branch.taken || $signed(IN_ld.sqN - IN_branch.sqN) <= 0)) begin
            reg enq = 0;
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (!enq && !queue[i].ld.valid) begin
                    enq = 1;
                    queue[i].ld <= IN_ld;
                    queue[i].ready <= 0;

                    //if (IN_cacheLoadActive &&
                    //    IN_ld.addr[31:CLSIZE_E] == IN_cacheLoadAddr &&
                    //    {1'b0, IN_ld.addr[CLSIZE_E-1:0]} < IN_cacheLoadProgress)
                    //    queue[i].ready <= 1;
                end
            end
        end  

        // Dequeue
        if (IN_dequeue || !(OUT_ld.external || !IN_branch.taken || $signed(OUT_ld.sqN - IN_branch.sqN) <= 0)) begin
            OUT_ld <= 'x;
            OUT_ld.valid <= 0;
        end
        if (!OUT_ld.valid || IN_dequeue) begin
            reg deq = 0;
            for (integer i = 0; i < SIZE; i=i+1) begin
                if (!deq && queue[i].ld.valid && (queue[i].ready || IN_ready) && 
                    (queue[i].ld.external || !IN_branch.taken || $signed(queue[i].ld.sqN - IN_branch.sqN) <= 0)) begin
                    deq = 1;
                    OUT_ld <= queue[i].ld;
                    queue[i].ld.valid <= 0;
                end
            end
        end

    end
end

endmodule
