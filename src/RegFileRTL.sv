module RegFile
#(
    parameter WIDTH = 32,
    parameter SIZE = 64,
    parameter NUM_READ = 8,
    parameter NUM_WRITE = 4
)
(
    input wire clk,
    
    input wire[NUM_READ-1:0] IN_re,
    input wire[NUM_READ-1:0][$clog2(SIZE)-1:0] IN_raddr,
    output reg[NUM_READ-1:0][WIDTH-1:0] OUT_rdata,

    input wire[NUM_WRITE-1:0] IN_we,
    input wire[NUM_WRITE-1:0][$clog2(SIZE)-1:0] IN_waddr,
    input wire[NUM_WRITE-1:0][WIDTH-1:0] IN_wdata
);

reg[WIDTH-1:0] mem[SIZE-1:0];

always_ff@(posedge clk) begin
    for (integer i = 0; i < NUM_READ; i=i+1) begin
        if (IN_re[i]) OUT_rdata[i] <= mem[IN_raddr[i]];
        else OUT_rdata[i] <= 'x;
    end
    for (integer i = 0; i < NUM_WRITE; i=i+1) begin
        if (IN_we[i]) mem[IN_waddr[i]] <= IN_wdata[i];
    end
    
    for (integer i = 0; i < NUM_READ; i=i+1)
        for (integer j = 0; j < NUM_WRITE; j=j+1)
            if (IN_re[i] && IN_we[j] && IN_raddr[i] == IN_waddr[j]) begin
                $display("write collision: %x", IN_waddr[j]);
                assert(0);
            end
end

endmodule
