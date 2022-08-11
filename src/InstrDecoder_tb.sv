`timescale 1 ns / 10 ps
localparam period = 10;
module InstrDecoder_tb;

reg clk = 0;
reg[31:0] instr = 0;
reg[31:0] pc = 0;

D_UOp uop;

wire invalidEnc;

InstrDecoder dec(
    .IN_instr(instr),
    .IN_pc(pc),
    .OUT_uop(uop),
    .OUT_invalid(invalidEnc)
    );

initial begin
    
    $dumpfile("InstrDecoder_tb.vcd");
    $dumpvars(0, InstrDecoder_tb);
 
    instr = 32'hFF010113;
    #10;
    $display("Instr: %h | INV: %h | SRCA: %h | SRCB: %h | IMMB: %b | DST: %h | OPC: %h | FU: %x | IMM: %0d", instr, invalidEnc, uop.rs0, uop.rs1, uop.immB, uop.rd, uop.opcode, uop.fu, $signed(uop.imm));
    
    instr = 32'h40B787B3;
    #10;
    $display("Instr: %h | INV: %h | SRCA: %h | SRCB: %h | IMMB: %b | DST: %h | OPC: %h | FU: %x | IMM: %0d", instr, invalidEnc, uop.rs0, uop.rs1, uop.immB, uop.rd, uop.opcode, uop.fu, $signed(uop.imm));
    
    instr = 32'h00f62023; //sw	a5,0(a2)
    #10;
    $display("Instr: %h | INV: %h | SRCA: %h | SRCB: %h | IMMB: %b | DST: %h | OPC: %h | FU: %x | IMM: %0d", instr, invalidEnc, uop.rs0, uop.rs1, uop.immB, uop.rd, uop.opcode, uop.fu, $signed(uop.imm));
    
    instr = 32'hfeb7fce3;
    #10;
    $display("Instr: %h | INV: %h | SRCA: %h | SRCB: %h | IMMB: %b | DST: %h | OPC: %h | FU: %x | IMM: %0d", instr, invalidEnc, uop.rs0, uop.rs1, uop.immB, uop.rd, uop.opcode, uop.fu, $signed(uop.imm));
    #10;
end
endmodule