module PCFile
#(
    parameter WORD_SIZE=$bits(PCFileEntry),
    parameter ADDR_SIZE=$bits(FetchID_t)
)
(
    input wire clk,

    input wire wen0,
    input wire[ADDR_SIZE-1:0] waddr0,
    input wire[WORD_SIZE-1:0] wdata0,
    
    input wire[ADDR_SIZE-1:0] raddr0, output reg[WORD_SIZE-1:0] rdata0,
    input wire[ADDR_SIZE-1:0] raddr1, output reg[WORD_SIZE-1:0] rdata1,
    input wire[ADDR_SIZE-1:0] raddr2, output reg[WORD_SIZE-1:0] rdata2,
    input wire[ADDR_SIZE-1:0] raddr3, output reg[WORD_SIZE-1:0] rdata3,
    input wire[ADDR_SIZE-1:0] raddr4, output reg[WORD_SIZE-1:0] rdata4,
    input wire[ADDR_SIZE-1:0] raddr5, output reg[WORD_SIZE-1:0] rdata5
);

reg[WORD_SIZE-1:0] mem[(1<<ADDR_SIZE)-1:0];

always_comb begin
    rdata0 = mem[raddr0];
    rdata1 = mem[raddr1];
    rdata2 = mem[raddr2];
    rdata3 = mem[raddr3];
    rdata4 = mem[raddr4];
    rdata5 = mem[raddr5];
end

always_ff@(posedge clk) begin
    if (wen0) mem[waddr0] <= wdata0;
end

endmodule
