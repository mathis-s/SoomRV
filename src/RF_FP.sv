module RF_FP
#(
    parameter SIZE=64,
    parameter WIDTH=32
)
(
    input wire clk,
    
    // One write for FPU, one for load
    input wire[5:0] waddr0,
    input wire[WIDTH-1:0] wdata0,
    input wire wen0,
    
    input wire[5:0] waddr1,
    input wire[WIDTH-1:0] wdata1,
    input wire wen1,
    
    // Three reads for FMA, one for store
    input wire[5:0] raddr0,
    output reg[WIDTH-1:0] rdata0,
    
    input wire[5:0] raddr1,
    output reg[WIDTH-1:0] rdata1,
    
    input wire[5:0] raddr2,
    output reg[WIDTH-1:0] rdata2,
    
    input wire[5:0] raddr3,
    output reg[WIDTH-1:0] rdata3
);

integer i;

reg[WIDTH-1:0] mem[SIZE-1:0];

always_comb begin
    rdata0 = mem[raddr0];
    rdata1 = mem[raddr1];
    rdata2 = mem[raddr2];
    rdata3 = mem[raddr3];
end

always_ff@(posedge clk) begin
    if (wen0) mem[waddr0] <= wdata0;
    if (wen1) mem[waddr1] <= wdata1;
end

endmodule
