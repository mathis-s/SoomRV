

module InstrAligner
#(
    parameter NUM_PACKETS = 8,
    parameter NUM_INSTRS = 4,
    parameter BUF_SIZE = 2,
    parameter FF_OUTPUT = 1
)
(
    input wire clk,
    input wire rst,

    input wire IN_clear,
    input wire IN_accept,
    output wire OUT_ready,
    input IF_Instr IN_op,

    input wire IN_ready,
    output PD_Instr OUT_instr[NUM_INSTRS-1:0]
);
localparam WINDOW_SIZE = (BUF_SIZE + 1) * NUM_PACKETS;
typedef struct packed
{
    IF_Instr op;
    logic[NUM_PACKETS-1:0] start;
    logic[NUM_PACKETS-1:0] start32;
} FetchCycle;

wire canShift = !|(unhandled_c[0+:NUM_PACKETS] & windowStart_c[0+:NUM_PACKETS]);
wire validCycle = IN_accept && IN_op.valid && canShift;
assign OUT_ready = validCycle;

// Propagate instruction boundaries
logic[NUM_PACKETS-1:0] isInstrStart_c;
logic[NUM_PACKETS-1:0] isInstrStart32_c;
logic validInstrStart_c;
logic is32bit;
always_comb begin
    is32bit = 'x;
    // The first word may be consumed by a 32-bit instruction that started in the previous packet
    validInstrStart_c = !(prev_r[BUF_SIZE-1].start[NUM_PACKETS-1] && prev_r[BUF_SIZE-1].start32[NUM_PACKETS-1]);

    for (integer i = 0; i < NUM_PACKETS; i=i+1) begin

        // only accept instructions within the package's boundaries
        if (FetchOff_t'(i) < IN_op.firstValid || !IN_op.valid)
            validInstrStart_c = 0;
        if (FetchOff_t'(i) > IN_op.lastValid)
            validInstrStart_c = 0;

        if (validInstrStart_c) begin
            is32bit = (IN_op.instrs[i][1:0] == 2'b11);
            isInstrStart_c[i] = 1;
            isInstrStart32_c[i] = is32bit;
            validInstrStart_c = !is32bit;
        end
        else begin
            isInstrStart_c[i] = 0;
            isInstrStart32_c[i] = 0;
            // If the current halfword was the second half of a 32-bit instruction,
            // the next halfword is a valid instruction start again.
            validInstrStart_c = 1;
        end
    end
end

wire FetchCycle cur_c = FetchCycle'{
    op:      IN_op,
    start:   isInstrStart_c,
    start32: isInstrStart32_c
};
FetchCycle[BUF_SIZE-1:0] prev_r;
wire FetchCycle[BUF_SIZE:0] cycles_c = {cur_c, prev_r};

always_ff@(posedge clk or posedge rst) begin

    if (rst) begin
        for (integer i = 0; i < BUF_SIZE; i=i+1) begin
            prev_r[i].start <= 0;
            prev_r[i].start32 <= 0;
            prev_r[i].op <= IF_Instr'{valid: 0, default: 'x};
        end
    end
    else begin
        if (validCycle) begin
            for (integer i = 0; i < BUF_SIZE; i=i+1) begin
                prev_r[i].start   <= cycles_c[i+1].start & unhandled_c[(i+1)*NUM_PACKETS+:NUM_PACKETS];
                prev_r[i].start32 <= cycles_c[i+1].start32;
                prev_r[i].op      <= cycles_c[i+1].op;
            end
        end
        else begin
            for (integer i = 0; i < BUF_SIZE; i=i+1) begin
                prev_r[i].start   <= prev_r[i].start & unhandled_c[i*NUM_PACKETS+:NUM_PACKETS];
            end
        end

        if (IN_clear) begin
            for (integer i = 0; i < BUF_SIZE; i=i+1) begin
                prev_r[i].start <= 0;
                prev_r[i].start32 <= 0;
                prev_r[i].op <= IF_Instr'{valid: 0, default: 'x};
            end
        end
    end
end

// Combine cycles_c into one window
logic[WINDOW_SIZE-1:0][15:0] window_c;
logic[WINDOW_SIZE-1:0] windowStart_c;
logic[WINDOW_SIZE-1:0] windowStart32_c;

wire lastIsSplit32 = isInstrStart32_c[BUF_SIZE*NUM_PACKETS-1];
wire middleIsSplit32 = prev_r[BUF_SIZE-1].start32[NUM_PACKETS-1] && !IN_op.valid;
always_comb begin
    for (integer i = 0; i <= BUF_SIZE; i=i+1) begin
        for (integer j = 0; j < NUM_PACKETS; j=j+1) begin
            window_c       [i*NUM_PACKETS+j] = cycles_c[i].op.instrs[j];
            windowStart_c  [i*NUM_PACKETS+j] = cycles_c[i].start[j];
            windowStart32_c[i*NUM_PACKETS+j] = cycles_c[i].start32[j];
        end
    end

    windowStart_c[BUF_SIZE*NUM_PACKETS-1] &= !middleIsSplit32;
    windowStart_c[WINDOW_SIZE-1] &= !lastIsSplit32;
end

// Select NUM_INSTRS instruction starts out of the window
wire[$clog2(WINDOW_SIZE)-1:0] pencIdx[NUM_INSTRS-1:0];
wire pencIdxValid[NUM_INSTRS-1:0];
PriorityEncoder#(WINDOW_SIZE, NUM_INSTRS) penc
(
    .IN_data(windowStart_c),
    .OUT_idx(pencIdx),
    .OUT_idxValid(pencIdxValid)
);

PD_Instr instr_c[NUM_INSTRS-1:0];
always_comb begin
    for (integer i = 0; i < NUM_INSTRS; i=i+1) begin
        IF_Instr ifetchOpFirst = 'x;
        IF_Instr ifetchOp = 'x;

        reg is32bit_c = 'x;
        reg[$clog2(WINDOW_SIZE)-1:0] idxLastWord_c = 'x;

        instr_c[i] = PD_Instr'{valid: 0, default: 'x};
        if (pencIdxValid[i]) begin
            is32bit_c = windowStart32_c[pencIdx[i]];
            idxLastWord_c = pencIdx[i] + $clog2(WINDOW_SIZE)'(is32bit_c);

            // verilator lint_off WIDTHEXPAND
            ifetchOp = cycles_c[idxLastWord_c / NUM_PACKETS].op;
            ifetchOpFirst = cycles_c[pencIdx[i] / NUM_PACKETS].op;
            // verilator lint_off WIDTHEXPAND

            instr_c[i] = PD_Instr'{
                instr:           {window_c[pencIdx[i] + 1], window_c[pencIdx[i]]},
                pc:              {ifetchOpFirst.pc, pencIdx[i][0+:$bits(FetchOff_t) ]},
                fetchStartOffs:  ifetchOp.pc[1+:$bits(FetchOff_t)],
                fetchPredOffs:   ifetchOp.predPos,
                predTarget:      ifetchOp.predTarget,
                predTaken:       ifetchOp.predTaken && ifetchOp.predPos == FetchOff_t'(idxLastWord_c),
                fetchID:         ifetchOp.fetchID,
                fetchFault:      ifetchOp.fetchFault,
                is16bit:         !windowStart32_c[pencIdx[i]],
                valid:           1
            };
        end
    end
end

wire outputReady;
if (FF_OUTPUT) begin
    always_ff@(posedge clk or posedge rst) begin
        if (rst) begin
            for (integer i = 0; i < NUM_INSTRS; i=i+1)
                OUT_instr[i] <= PD_Instr'{valid: 0, default: 'x};
        end
        else if (IN_clear) begin
            for (integer i = 0; i < NUM_INSTRS; i=i+1)
                OUT_instr[i] <= PD_Instr'{valid: 0, default: 'x};
        end
        else begin
            for (integer i = 0; i < NUM_INSTRS; i=i+1)
                if (outputReady)
                    OUT_instr[i] <= instr_c[i];
        end
    end
    assign outputReady = !OUT_instr[0].valid || IN_ready;
end
else begin
    always_comb begin
        for (integer i = 0; i < NUM_INSTRS; i=i+1)
            OUT_instr[i] = instr_c[i];
    end
    assign outputReady = IN_ready;
end

logic[WINDOW_SIZE-1:0] unhandled_c;
always_comb begin
    for (integer i = 0; i < WINDOW_SIZE; i=i+1)
        unhandled_c[i] = !outputReady ||
            (pencIdxValid[NUM_INSTRS-1] &&
                (windowStart32_c[pencIdx[NUM_INSTRS-1]] ?
                    (i==0 ? 0 : i-1) > pencIdx[NUM_INSTRS-1] :
                    i                > pencIdx[NUM_INSTRS-1]));

    unhandled_c[BUF_SIZE*NUM_PACKETS-1] |= middleIsSplit32;
    unhandled_c[WINDOW_SIZE-1] |= lastIsSplit32;
end

endmodule
