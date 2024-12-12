module Scheduler
(
    input wire clk,
    input wire rst,

    input wire IN_valid,

    input SqN IN_uopSqN[`DEC_WIDTH-1:0],
    input SqN IN_uopLoadSqN[`DEC_WIDTH-1:0],
    input SqN IN_uopStoreSqN[`DEC_WIDTH-1:0],

    input D_UOp IN_uop[`DEC_WIDTH-1:0],
    output IntUOpOrder_t OUT_order[`DEC_WIDTH-1:0]
);

typedef logic[NUM_ALUS-1:0] Candidates_t;
// verilator lint_off VARHIDDEN
function automatic Candidates_t GetCandidates(FuncUnit fu, SqN sqN, SqN loadSqN, SqN storeSqN);
    Candidates_t retval = '0;

    case (fu)
        default: begin
            for (integer i = 0; i < 4; i=i+1)
                if (PORT_FUS[i][fu] != 0)
                    retval |= (1 << i);
        end

        FU_ATOMIC: begin
            // Atomics are distributed by store sqn
            retval = 1 << (storeSqN % NUM_AGUS);
        end

        // Not handled here
        FU_RN, FU_AGU, FU_TRAP: ;
    endcase

    return retval;
endfunction
// verilator lint_on VARHIDDEN

// Yosys can't handle constant non-pow2 mods, so put a lookup table here.
localparam PAD = $clog2(NUM_ALUS) + 1;
localparam MOD_TABLE_LEN = 1 << PAD;
reg[$clog2(NUM_ALUS)-1:0] modTable[MOD_TABLE_LEN-1:0];
// verilator lint_off WIDTHTRUNC
initial begin
    for (integer i = 0; i < MOD_TABLE_LEN; i=i+1)
        modTable[i] = (i % NUM_ALUS);
end
// verilator lint_on WIDTHTRUNC

Candidates_t candidates[`DEC_WIDTH-1:0];
always_comb begin
    for (integer i = 0; i < 4; i=i+1)
        candidates[i] = GetCandidates(IN_uop[i].fu, IN_uopSqN[i], IN_uopLoadSqN[i], IN_uopStoreSqN[i]);
end

logic[$clog2(NUM_ALUS)-1:0] prio_r;
always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst) begin
        prio_r <= 0;
    end
    else begin
        for (integer i = 0; i < `DEC_WIDTH; i=i+1)
            if (IN_valid && IN_uop[i].valid)
                prio_r <= modTable[PAD'(OUT_order[i]) + PAD'(1)];
    end
end

// verilator lint_off UNOPTFLAT

// Faster scheduling
//logic[$clog2(NUM_ALUS)-1:0] prios_c[`DEC_WIDTH-1:0];
//always_comb begin
//    for (integer i = 0; i < `DEC_WIDTH; i=i+1)
//        prios_c[i] = modTable[PAD'(prio_r) + PAD'(i)];
//end

logic[$clog2(NUM_ALUS)-1:0] prios_c[`DEC_WIDTH-1:0];
always_comb begin
    prios_c[0] = prio_r;
    for (integer i = 1; i < `DEC_WIDTH; i=i+1)
        prios_c[i] = modTable[PAD'(OUT_order[i-1]) + PAD'(1)];
end

IntUOpOrder_t outOrderRaw[`DEC_WIDTH-1:0];
generate for (genvar i = 0; i < `DEC_WIDTH; i=i+1)
    PriorityEncoder#(NUM_ALUS) penc (
        .IN_data((candidates[i] >> prios_c[i]) | (candidates[i] << (NUM_ALUS - prios_c[i]))),
        .OUT_idx({outOrderRaw[i]}),
        .OUT_idxValid()
    );
endgenerate

always_comb begin
    for (integer i = 0; i < `DEC_WIDTH; i=i+1)
        OUT_order[i] = modTable[PAD'(outOrderRaw[i]) + PAD'(prios_c[i])];
end

// verilator lint_on UNOPTFLAT

`ifdef DEBUG
always_ff@(posedge clk) begin
    for (integer i = 0; i < `DEC_WIDTH; i=i+1)
        if (IN_valid && IN_uop[i].valid && IN_uop[i].valid && |candidates[i] && !candidates[i][OUT_order[i]]) begin
            $display("error; i=%d, candidates[i]=%b, OUT_order[i]=%d", i, candidates[i], OUT_order[i]);
            assert(0);
        end
end
`endif

endmodule
