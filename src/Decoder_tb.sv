`timescale 1 ns / 10 ps
localparam period = 10;
module Decoder_tb;

reg clk = 0;
reg[31:0] instr = 0;
reg[31:0] pc = 0;

wire[90:0] uop;
wire[2:0] fu;

Decoder dec(
    .clk(clk),
    .IN_instr(instr),
    .IN_pc(pc),
    .OUT_uop(uop)
    
    );

initial begin
    
    $dumpfile("Decoder_tb.vcd");
    $dumpvars(0, Decoder_tb);

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