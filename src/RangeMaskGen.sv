module RangeMaskGen#(parameter LENGTH=16, parameter OUTPUT_ON_EQUAL=0, parameter START_SHIFT=0, parameter END_SHIFT=0)
(
    input wire IN_allOnes,
    input wire IN_enable,
    input wire[$clog2(LENGTH)-1:0] IN_startIdx,
    input wire[$clog2(LENGTH)-1:0] IN_endIdx,
    output logic[LENGTH-1:0] OUT_range
);


wire[LENGTH-1:0] startIdxOH = 1 << IN_startIdx;
wire[LENGTH-1:0] endIdxOH = 1 << IN_endIdx;

wire[$clog2(LENGTH)-1:0] startIdxSh = IN_startIdx + START_SHIFT;
wire[$clog2(LENGTH)-1:0] endIdxSh = IN_endIdx + END_SHIFT;

always_comb begin
    logic active = OUTPUT_ON_EQUAL ?
        (startIdxSh >= endIdxSh) :
        (startIdxSh >  endIdxSh);

    for (integer i = 0; i < LENGTH; i=i+1) begin
        logic doEnd = endIdxOH[(i-END_SHIFT)%LENGTH];
        logic doStart = startIdxOH[(i-START_SHIFT)%LENGTH];

        // Swap cases depending on what we are supposed to output when indices are equal.
        if (OUTPUT_ON_EQUAL) begin
            if (doStart) active = 1;
            else if (doEnd) active = 0;
        end
        else begin
            if (doEnd) active = 0;
            else if (doStart) active = 1;
        end

        OUT_range[i] = (active && IN_enable) || IN_allOnes;
    end
end

endmodule
