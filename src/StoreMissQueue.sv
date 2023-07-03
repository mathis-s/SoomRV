module StoreMissQueue#(parameter SIZE=2, parameter CLSIZE_E=7)
(
    input wire clk,
    input wire rst,

    input wire IN_ready,

    output wire OUT_full,

    input wire IN_cacheLoadActive,
    input wire[CLSIZE_E-2:0] IN_cacheLoadProgress,
    input wire[31-CLSIZE_E:0] IN_cacheLoadAddr,

    input ST_UOp IN_st,
    input wire IN_enqueue,

    output ST_UOp OUT_st,
    input wire IN_dequeue
);


reg[$clog2(SIZE)-1:0] inIdx;
reg[$clog2(SIZE)-1:0] outIdx;
reg[$clog2(SIZE):0] free;
struct packed
{
    logic ready;
    ST_UOp st;
} queue[SIZE-1:0];


assign OUT_full = !(free > 3);

always_ff@(posedge clk) begin
    
    if (rst) begin
        for (integer i = 0; i < SIZE; i=i+1)
            queue[i].st.valid <= 0;
        OUT_st.valid <= 0;
        inIdx <= 0;
        outIdx <= 0;
        free <= SIZE;
    end
    else begin

        // Set Ready
        for (integer i = 0; i < SIZE; i=i+1) begin
            if (IN_cacheLoadActive && queue[i].st.valid &&
                queue[i].st.addr[31:CLSIZE_E] == IN_cacheLoadAddr &&
                {1'b0, queue[i].st.addr[CLSIZE_E-1:2]} < IN_cacheLoadProgress)
                queue[i].ready <= 1;
        end

        // Enqueue
        if (IN_st.valid && IN_enqueue) begin
            assert(free != 0);
            queue[inIdx].ready <= 0;
            queue[inIdx].st <= IN_st;
            inIdx <= inIdx + 1;
            free <= free - 1;
        end

        // Dequeue
        if (IN_dequeue) begin
            OUT_st <= 'x;
            OUT_st.valid <= 0;
        end
        if ((!OUT_st.valid || IN_dequeue) && !(IN_st.valid && IN_enqueue)) begin
            if (free != SIZE && (queue[outIdx].ready || IN_ready)) begin
                assert(queue[outIdx].st.valid);
                OUT_st <= queue[outIdx].st;
                outIdx <= outIdx + 1;
                free <= free + 1;
            end
        end

    end
end

endmodule
