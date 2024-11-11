module OHEncoder#(parameter LEN=32, parameter ALLOW_NULL=0)
(
    input wire[LEN-1:0] IN_idxOH,
    output reg[LEN == 1 ? 0 : $clog2(LEN)-1:0] OUT_idx,
    output reg OUT_valid
);

if (LEN > 1)
    always_comb begin
        OUT_valid = 0;
        for (integer i = 0; i < LEN; i=i+1) begin
            assert(!(IN_idxOH[i] && OUT_valid));
            OUT_valid |= IN_idxOH[i];
        end

        assert(OUT_valid || ALLOW_NULL);

        for (integer i = 0; i < $clog2(LEN); i=i+1) begin
            OUT_idx[i] = 1'b0;
            for (integer j = 0; j < LEN; j=j+1) begin
                if ((j & (1 << i)) != 0) begin
                    OUT_idx[i] |= IN_idxOH[j];
                end
            end
        end
    end
else always_comb begin
    OUT_idx = 0;
    OUT_valid = IN_idxOH[0];

    assert(OUT_valid || ALLOW_NULL);
end

endmodule
