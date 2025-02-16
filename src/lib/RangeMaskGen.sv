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
        logic doEnd = endIdxOH[$unsigned(i-END_SHIFT)%LENGTH];
        logic doStart = startIdxOH[$unsigned(i-START_SHIFT)%LENGTH];

        if (doStart && doEnd) active = OUTPUT_ON_EQUAL;
        else if (doStart) active = 1;
        else if (doEnd) active = 0;

        OUT_range[i] = (active && IN_enable) || IN_allOnes;
    end
end

endmodule
