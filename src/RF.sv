module RF
#(
    parameter SIZE=`NUM_TAGS,
    parameter WIDTH=32
)
(
    input wire clk,
    
    input wire[$clog2(SIZE)-1:0] waddr0,
    input wire[WIDTH-1:0] wdata0,
    input wire wen0,
    
    input wire[$clog2(SIZE)-1:0] waddr1,
    input wire[WIDTH-1:0] wdata1,
    input wire wen1,
    
    input wire[$clog2(SIZE)-1:0] waddr2,
    input wire[WIDTH-1:0] wdata2,
    input wire wen2,
    
    input wire[$clog2(SIZE)-1:0] waddr3,
    input wire[WIDTH-1:0] wdata3,
    input wire wen3,
    
    input wire[$clog2(SIZE)-1:0] raddr0,
    output reg[WIDTH-1:0] rdata0,
    
    input wire[$clog2(SIZE)-1:0] raddr1,
    output reg[WIDTH-1:0] rdata1,
    
    input wire[$clog2(SIZE)-1:0] raddr2,
    output reg[WIDTH-1:0] rdata2,
    
    input wire[$clog2(SIZE)-1:0] raddr3,
    output reg[WIDTH-1:0] rdata3,
    
    input wire[$clog2(SIZE)-1:0] raddr4,
    output reg[WIDTH-1:0] rdata4,
    
    input wire[$clog2(SIZE)-1:0] raddr5,
    output reg[WIDTH-1:0] rdata5,
    
    input wire[$clog2(SIZE)-1:0] raddr6,
    output reg[WIDTH-1:0] rdata6,
    
    input wire[$clog2(SIZE)-1:0] raddr7,
    output reg[WIDTH-1:0] rdata7
);


reg[WIDTH-1:0] mem[SIZE-1:0] /*verilator public*/;

always_ff@(posedge clk) begin

    rdata0 <= mem[raddr0];
    rdata1 <= mem[raddr1];
    rdata2 <= mem[raddr2];
    rdata3 <= mem[raddr3];
    rdata4 <= mem[raddr4];
    rdata5 <= mem[raddr5];
    rdata6 <= mem[raddr6];
    rdata7 <= mem[raddr7];

    if (wen0) mem[waddr0] <= wdata0;
    if (wen1) mem[waddr1] <= wdata1;
    if (wen2) mem[waddr2] <= wdata2;
    if (wen3) mem[waddr3] <= wdata3;
end

endmodule
