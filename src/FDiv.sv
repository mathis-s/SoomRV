module FDiv
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input wire IN_wbAvail,
    output wire OUT_busy,
    
    input BranchProv IN_branch,
    input EX_UOp IN_uop,
    
    output RES_UOp OUT_uop
);

wire[2:0] rm = 0;

wire[32:0] srcArec;
wire[32:0] srcBrec;
fNToRecFN#(8, 24) recA (.in(IN_uop.srcA), .out(srcArec));
fNToRecFN#(8, 24) recB (.in(IN_uop.srcB), .out(srcBrec));

assign OUT_busy = !ready || (en && IN_uop.valid) || OUT_uop.valid;

wire ready;
wire outValid;

wire[32:0] result;
divSqrtRecFN_small#(8, 24, 0) fdiv
(
    .nReset(!rst),
    .clock(clk),
    .control(1'b1),
    
    .inReady(ready),
    .inValid(en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)),
    
    .sqrtOp(IN_uop.opcode[0]),
    .a(srcArec),
    .b(srcBrec),
    .roundingMode(rm),
    
    .outValid(outValid),
    .sqrtOpOut(),
    .out(result),
    .exceptionFlags()
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
        OUT_uop.flags <= FLAGS_NONE;
        OUT_uop.pc <= IN_uop.pc;
        OUT_uop.compressed <= 0;
        running <= 1;
    end
    else if (running && outValid && (!IN_branch.taken || $signed(OUT_uop.sqN - IN_branch.sqN) <= 0)) begin
        OUT_uop.valid <= 1;
        OUT_uop.result <= fpResult;
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
