

module PopCnt#(parameter SIZE = 32)
(
    input wire[SIZE-1:0] in,
    output wire[$clog2(SIZE):0] res
);

localparam SIZE_POW2 = 1 << $clog2(SIZE);
localparam NUM_STAGES = $clog2(SIZE_POW2);

wire[SIZE_POW2-1:0] inPadded = {{(SIZE_POW2 - SIZE){1'b0}}, in};


generate
for (genvar i = 0; i <= NUM_STAGES; i=i+1) begin : tree
    logic[(SIZE_POW2 >> i)*(i+1)-1:0] iSums;

    if (i == 0)
        assign iSums = inPadded;
    else
        for (genvar j = 0; j < (SIZE_POW2 >> i); j=j+1)
                assign iSums[j*(i+1)+:(i+1)] = tree[i-1].iSums[2*j*i+:i] + tree[i-1].iSums[(2*j+1)*i+:i];

end
endgenerate

// Nicer code (Yosys can't handle)
/*
generate
for (genvar i = 0; i <= NUM_STAGES; i=i+1) begin : tree
    logic[(SIZE_POW2 >> i)-1:0][i:0] iSums;

    if (i == 0)
        always_comb iSums = in;
    else
        always_comb begin
            for (integer j = 0; j < (SIZE_POW2 >> i); j=j+1)
                iSums[j] = tree[i-1].iSums[2*j] + tree[i-1].iSums[2*j+1];
        end
end
endgenerate
*/

assign res = tree[NUM_STAGES].iSums;

endmodule
