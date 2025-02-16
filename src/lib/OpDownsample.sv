// Downsample NUM_IN ops to NUM_OUT ops, selecting ops where opBaseValid and opValid are set.
// OUT_stall is set only for baseValid ops where either opValid is false or when throughput limited by NUM_OUT or dynMaxNumOut.

module OpDownsample#(parameter NUM_IN, parameter NUM_OUT, parameter OP_SIZE)
(
    input logic[OP_SIZE-1:0] IN_ops[NUM_IN-1:0],
    input logic[NUM_IN-1:0] IN_opBaseValid,
    input logic[NUM_IN-1:0] IN_opValid,
    output logic[NUM_IN-1:0] OUT_opStall,

    input logic[$clog2(NUM_OUT+1)-1:0] IN_dynMaxNumOut,

    output logic[OP_SIZE-1:0] OUT_ops[NUM_OUT-1:0]
);

logic[$clog2(NUM_IN+1)-1:0] baseCandPSums_c[NUM_IN-1:0];
PrefixSum#(NUM_IN) enqCandPSum(IN_opBaseValid, baseCandPSums_c);

logic[NUM_IN-1:0] isCand_c;
always_comb begin
    for (integer i = 0; i < NUM_IN; i++) begin
        isCand_c[i] = 0;
        OUT_opStall[i] = 0;
        if (IN_opBaseValid[i]) begin
            // verilator lint_off WIDTHEXPAND
            if (IN_opValid[i] && baseCandPSums_c[i] <= IN_dynMaxNumOut) begin
                isCand_c[i] = 1;
            end
            else OUT_opStall[i] = 1;
            // verilator lint_off WIDTHEXPAND
        end
    end
end

logic[$clog2(NUM_IN)-1:0] candIndex_c[NUM_OUT-1:0];
logic candValid_c[NUM_OUT-1:0];
PriorityEncoder #(.BITS(NUM_IN), .N(NUM_OUT)) penc(
    .IN_data(isCand_c),
    .OUT_idx(candIndex_c),
    .OUT_idxValid(candValid_c)
);

always_comb begin
    for (int j = 0; j < NUM_OUT; j++) begin
        OUT_ops[j] = 'x;
        OUT_ops[j][0] = 0;
        if (candValid_c[j] && j < IN_dynMaxNumOut)
            OUT_ops[j] = IN_ops[candIndex_c[j]];
    end
end

endmodule
