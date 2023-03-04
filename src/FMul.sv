module FMul
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input BranchProv IN_branch,
    input EX_UOp IN_uop,
    
    output RES_UOp OUT_uop
);

wire[32:0] srcArec;
wire[32:0] srcBrec;
fNToRecFN#(8, 24) recA (.in(IN_uop.srcA), .out(srcArec));
fNToRecFN#(8, 24) recB (.in(IN_uop.srcB), .out(srcBrec));

wire[2:0] rm = 0;

wire[32:0] mul;
wire[4:0] mulFlags;
mulRecFN#(8, 24) mulRec
(
    .control(0),
    .a(srcArec),
    .b(srcBrec),
    .roundingMode(rm),
    .out(mul),
    .exceptionFlags(mulFlags)
);

wire[31:0] fpResult;
recFNToFN#(8, 24) recode
(
    .in(mul),
    .out(fpResult)
);
// 149390 cycles
always@(posedge clk) begin
    
    if (rst) begin
        OUT_uop.valid <= 0;
    end
    else if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
        
        OUT_uop.tagDst <= IN_uop.tagDst;
        OUT_uop.nmDst <= IN_uop.nmDst;
        OUT_uop.sqN <= IN_uop.sqN;
        OUT_uop.flags <= FLAGS_NONE;
        OUT_uop.valid <= 1;
        OUT_uop.pc <= IN_uop.pc;
        OUT_uop.compressed <= 0;
        OUT_uop.result <= fpResult;
        OUT_uop.doNotCommit <= 0;
    end
    else begin
        OUT_uop.valid <= 0;
    end

end

endmodule
