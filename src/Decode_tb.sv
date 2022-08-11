`timescale 1 ns / 10 ps
localparam period = 10;
module Decode_tb;

reg clk = 0;
reg[31:0] instr = 0;
reg[31:0] pc = 0;

reg wbResult[31:0] = 0;
reg wbRegNm[4:0] = 0;

UOp uop;

// can you also not assign all of these fields explicitly?
Decode dec
(
    .clk(clk),
    .IN_instr(instr),
    .IN_pc(pc),

    .IN_wbResult(wbResult),
    .IN_wbValid(0),
    .IN_wbRegNm(wbRegNm),
    
    .OUT_uop(uop)
);

initial begin
    
    $dumpfile("Decode_tb.vcd");
    $dumpvars(0, Decode_tb);

    clk = 0;
    #period
    instr = 32'hFF010113;
    clk = 1;
    #period;
    clk = 0;
    #period;
    instr = 32'h40B787B3;
    clk = 1;
    #period;
    clk = 0;
    #period;
    instr = 32'h00f62023; //sw	a5,0(a2)
    clk = 1;
    #period;
    clk = 0;
    #period;
    instr = 32'hfeb7fce3;
    clk = 1;
    #period;
    clk = 0;
    #period;
end
endmodule