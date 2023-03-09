`include "../hardfloat/HardFloat_consts.vi"

module FDiv
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input wire IN_wbAvail,
    output wire OUT_busy,
    
    input BranchProv IN_branch,
    input EX_UOp IN_uop,
    
    input wire[2:0] IN_fRoundMode,
    
    output RES_UOp OUT_uop
);

wire[2:0] rm = IN_fRoundMode;

wire[32:0] srcArec;
wire[32:0] srcBrec;
fNToRecFN#(8, 24) recA (.in(IN_uop.srcA), .out(srcArec));
fNToRecFN#(8, 24) recB (.in(IN_uop.srcB), .out(srcBrec));

assign OUT_busy = !ready || (en && IN_uop.valid) || OUT_uop.valid;

wire ready;
wire outValid;

wire[4:0] flags;
wire[32:0] result;
divSqrtRecFN_small#(8, 24, 0) fdiv
(
    .nReset(!rst),
    .clock(clk),
    .control(`flControl_tininessAfterRounding),
    
    .inReady(ready),
    .inValid(en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)),
    
    .sqrtOp(IN_uop.opcode[0]),
    .a(srcArec),
    .b(srcBrec),
    .roundingMode(rm),
    
    .outValid(outValid),
    .sqrtOpOut(),
    .out(result),
    .exceptionFlags(flags)
);

wire[31:0] fpResult;
recFNToFN#(8, 24) recode
(
    .in(result),
    .out(fpResult)
);

reg running;
always_ff@(posedge clk) begin
    
    if (rst) begin
        running <= 0;
    end
    if (!running && en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
        
        // Store metadata in output uop (without setting it valid)
        OUT_uop.tagDst <= IN_uop.tagDst;
        OUT_uop.nmDst <= IN_uop.nmDst;
        OUT_uop.sqN <= IN_uop.sqN;
        OUT_uop.pc <= IN_uop.pc;
        OUT_uop.compressed <= 0;
        OUT_uop.doNotCommit <= 0;
        running <= 1;
    end
    else if (running && outValid && (!IN_branch.taken || $signed(OUT_uop.sqN - IN_branch.sqN) <= 0)) begin
        OUT_uop.valid <= 1;
        OUT_uop.result <= fpResult;
        
        /* verilator lint_off CASEOVERLAP */
        casez (flags)
            5'b00000: OUT_uop.flags <= FLAGS_NONE;
            5'b???1?: OUT_uop.flags <= FLAGS_FP_UF;
            5'b??1??: OUT_uop.flags <= FLAGS_FP_OF;
            5'b?1???: OUT_uop.flags <= FLAGS_FP_DZ;
            5'b1????: OUT_uop.flags <= FLAGS_FP_NV;
            5'b????1: OUT_uop.flags <= FLAGS_FP_NX;
        endcase
        /* verilator lint_on CASEOVERLAP */
        
        if (rm >= 3'b101)
            OUT_uop.flags <= FLAGS_EXCEPT;
                
        running <= 0;
    end
    else begin
        if (!(!IN_branch.taken || $signed(OUT_uop.sqN - IN_branch.sqN) <= 0) || IN_wbAvail) begin
            OUT_uop.valid <= 0;
        end
        
        if (!(!IN_branch.taken || $signed(OUT_uop.sqN - IN_branch.sqN) <= 0)) begin
            running <= 0;
        end
    end
    

end

endmodule
