// Simple mux between sources of loads, currently regular AGU and page walker.
module LoadSelector
(
    input LD_UOp IN_aguLd,
    output reg OUT_aguLdStall,

    input PW_LD_UOp IN_pwLd,
    output reg OUT_pwLdStall,

    input wire IN_ldUOpStall,
    output LD_UOp OUT_ldUOp
);

always_comb begin
    
    OUT_ldUOp = 'x;
    OUT_ldUOp.valid = 0;

    OUT_pwLdStall = 0;
    OUT_aguLdStall = 0;

    if (IN_pwLd.valid) begin
        OUT_ldUOp.addr = IN_pwLd.addr;
        OUT_ldUOp.signExtend = 0;
        OUT_ldUOp.size = 2;
        OUT_ldUOp.tagDst = 7'h40;
        OUT_ldUOp.sqN = 0;
        OUT_ldUOp.doNotCommit = 1;
        OUT_ldUOp.external = 1;
        OUT_ldUOp.exception = AGU_NO_EXCEPTION;
        OUT_ldUOp.isMMIO = 0;
        OUT_ldUOp.valid = IN_pwLd.valid;

        OUT_pwLdStall = IN_aguLd.valid || IN_ldUOpStall;
    end

    if (IN_aguLd.valid) begin
        OUT_ldUOp.addr = IN_aguLd.addr;
        OUT_ldUOp.signExtend = IN_aguLd.signExtend;
        OUT_ldUOp.size = IN_aguLd.size;
        OUT_ldUOp.tagDst = IN_aguLd.tagDst;
        OUT_ldUOp.sqN = IN_aguLd.sqN;
        OUT_ldUOp.doNotCommit = IN_aguLd.doNotCommit;
        OUT_ldUOp.external = 0;
        OUT_ldUOp.exception = IN_aguLd.exception;
        OUT_ldUOp.isMMIO = IN_aguLd.isMMIO;
        OUT_ldUOp.valid = IN_aguLd.valid;

        OUT_aguLdStall = IN_ldUOpStall;
    end
end
endmodule
