// Simple mux between sources of loads, currently regular AGU and page walker.
module LoadSelector
(
    input LD_UOp IN_aguLd[NUM_AGUS-1:0],
    output reg OUT_aguLdStall[NUM_AGUS-1:0],

    input PW_LD_UOp IN_pwLd[NUM_AGUS-1:0],
    output reg OUT_pwLdStall[NUM_AGUS-1:0],

    input wire IN_ldUOpStall[NUM_AGUS-1:0],
    output LD_UOp OUT_ldUOp[NUM_AGUS-1:0]
);

always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        OUT_pwLdStall[i] = 0;
        OUT_aguLdStall[i] = 0;

        if (IN_aguLd[i].valid) begin
            OUT_aguLdStall[i] = IN_pwLd[i].valid || IN_ldUOpStall[i];
        end

        if (IN_pwLd[i].valid) begin
            OUT_pwLdStall[i] = IN_ldUOpStall[i];
        end
    end
end

always_comb begin
    for (integer i = 0; i < NUM_AGUS; i=i+1) begin
        OUT_ldUOp[i] = 'x;
        OUT_ldUOp[i].valid = 0;

        if (IN_aguLd[i].valid) begin
            OUT_ldUOp[i] = IN_aguLd[i];
        end

        if (IN_pwLd[i].valid) begin
            OUT_ldUOp[i].data = 'x;
            OUT_ldUOp[i].dataValid = 0;
            OUT_ldUOp[i].addr = IN_pwLd[i].addr;
            OUT_ldUOp[i].signExtend = 0;
            OUT_ldUOp[i].size = 2;
            OUT_ldUOp[i].sqN = 0;
            OUT_ldUOp[i].tagDst = 7'h40;
            OUT_ldUOp[i].loadSqN = 0;
            OUT_ldUOp[i].storeSqN = 0;
            OUT_ldUOp[i].doNotCommit = 1;
            OUT_ldUOp[i].atomic = 0;
            OUT_ldUOp[i].external = 1;
            OUT_ldUOp[i].exception = AGU_NO_EXCEPTION;
            OUT_ldUOp[i].isMMIO = 0;
            OUT_ldUOp[i].valid = IN_pwLd[i].valid;
        end
    end
end
endmodule
