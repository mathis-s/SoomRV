// Simple mux between sources of loads, currently regular AGU and page walker.
module LoadSelector
(
    input LD_UOp IN_aguLd[`NUM_AGUS-1:0],
    output reg OUT_aguLdStall[`NUM_AGUS-1:0],

    input PW_LD_UOp IN_pwLd[`NUM_AGUS-1:0],
    output reg OUT_pwLdStall[`NUM_AGUS-1:0],

    input wire IN_ldUOpStall[`NUM_AGUS-1:0],
    output LD_UOp OUT_ldUOp[`NUM_AGUS-1:0]
);

always_comb begin
    
    for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
        OUT_ldUOp[i] = 'x;
        OUT_ldUOp[i].valid = 0;

        OUT_pwLdStall[i] = 0;
        OUT_aguLdStall[i] = 0;

        if (IN_pwLd[i].valid) begin
            OUT_ldUOp[i].addr = IN_pwLd[i].addr;
            OUT_ldUOp[i].signExtend = 0;
            OUT_ldUOp[i].size = 2;
            OUT_ldUOp[i].sqN = 0;
            OUT_ldUOp[i].tagDst = 7'h40;
            OUT_ldUOp[i].sqN = 0;
            OUT_ldUOp[i].doNotCommit = 1;
            OUT_ldUOp[i].external = 1;
            OUT_ldUOp[i].exception = AGU_NO_EXCEPTION;
            OUT_ldUOp[i].isMMIO = 0;
            OUT_ldUOp[i].valid = IN_pwLd[i].valid;

            OUT_pwLdStall[i] = IN_aguLd[i].valid || IN_ldUOpStall[i];
        end

        if (IN_aguLd[i].valid) begin
            OUT_ldUOp[i].addr = IN_aguLd[i].addr;
            OUT_ldUOp[i].signExtend = IN_aguLd[i].signExtend;
            OUT_ldUOp[i].size = IN_aguLd[i].size;
            OUT_ldUOp[i].loadSqN = IN_aguLd[i].loadSqN;
            OUT_ldUOp[i].tagDst = IN_aguLd[i].tagDst;
            OUT_ldUOp[i].sqN = IN_aguLd[i].sqN;
            OUT_ldUOp[i].doNotCommit = IN_aguLd[i].doNotCommit;
            OUT_ldUOp[i].external = 0;
            OUT_ldUOp[i].exception = IN_aguLd[i].exception;
            OUT_ldUOp[i].isMMIO = IN_aguLd[i].isMMIO;
            OUT_ldUOp[i].valid = IN_aguLd[i].valid;

            OUT_aguLdStall[i] = IN_ldUOpStall[i];
        end
    end
end
endmodule
