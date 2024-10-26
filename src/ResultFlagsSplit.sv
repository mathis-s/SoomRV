module ResultFlagsSplit#(parameter WIDTH=1)
(
    input RES_UOp[WIDTH-1:0] IN_uop,
    output FlagsUOp[WIDTH-1:0] OUT_flagsUOp,
    output ResultUOp[WIDTH-1:0] OUT_resultUOp
);

always_comb begin
    for (integer i = 0; i < WIDTH; i=i+1) begin
        OUT_flagsUOp[i] = FlagsUOp'{
            sqN:         IN_uop[i].sqN,
            tagDst:      IN_uop[i].tagDst,
            flags:       IN_uop[i].flags,
            doNotCommit: IN_uop[i].doNotCommit,
            valid:       IN_uop[i].valid && !IN_uop[i].doNotCommit
        };
        OUT_resultUOp[i] = ResultUOp'{
            result:      IN_uop[i].result,
            tagDst:      IN_uop[i].tagDst,
            doNotCommit: IN_uop[i].doNotCommit,
            valid:       IN_uop[i].valid
        };
    end
end

endmodule
