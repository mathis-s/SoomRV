module StoreQueue
#(
    parameter NUM_ENTRIES=`SQ_SIZE,
    parameter RESULT_BUS_COUNT=4,
    parameter WIDTH_RN = `DEC_WIDTH,
    parameter NUM_OUT=2
)
(
    input wire clk,
    input wire rst,

    output reg OUT_empty,
    output wire OUT_done,
    
    input LD_UOp IN_uopLd[`NUM_AGUS-1:0],
    output StFwdResult OUT_fwd[`NUM_AGUS-1:0],

    input AGU_UOp IN_uopSt[`NUM_AGUS-1:0],
    
    input R_UOp IN_rnUOp[WIDTH_RN-1:0],
    input StDataUOp IN_stDataUOp[`NUM_AGUS-1:0],
    
    input SqN IN_curSqN,
    input SqN IN_comStSqN,
    
    input BranchProv IN_branch,
    
    output SQ_UOp OUT_uop[NUM_OUT-1:0],
    input wire IN_stall[NUM_OUT-1:0],
    
    output wire OUT_flush,
    output SqN OUT_maxStoreSqN
);

localparam AXI_BWIDTH_E = $clog2(`AXI_WIDTH/8);
localparam IDX_LEN = $clog2(NUM_ENTRIES);

typedef struct packed
{
    RegT data;
    logic[29:0] addr;

    // wmask == 0 is escape sequence for special operations
    logic[3:0] wmask;
    
    SqN sqN;
    logic loaded;
    logic addrAvail;
} SQEntry;

reg[NUM_ENTRIES-1:0] entryReady_r /* verilator public */;
always_ff@(posedge clk) entryReady_r <= rst ? 0 : entryReady_c;

wire[NUM_ENTRIES-1:0] baseIndexOneHot = (1 << baseIndex[IDX_LEN-1:0]);
wire[NUM_ENTRIES-1:0] comStSqNOneHot = (1 << IN_comStSqN[IDX_LEN-1:0]);
wire[NUM_ENTRIES-1:0] branchStSqNOneHot = (1 << IN_branch.storeSqN[IDX_LEN-1:0]);

reg[NUM_ENTRIES-1:0] entryReady_c;
always_comb begin
    reg active = IN_comStSqN[IDX_LEN-1:0] < baseIndex[IDX_LEN-1:0];
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (SqN'(baseIndex + SqN'(NUM_ENTRIES)) == IN_comStSqN)
            active = 1;
        else if (comStSqNOneHot[i])
            active = 0;
        else if (baseIndexOneHot[i])
            active = 1;
        
        entryReady_c[i] = active;
    end
end

reg[NUM_ENTRIES-1:0] invalRange_c;
always_comb begin
    reg active = baseIndex[IDX_LEN-1:0] <= (IN_branch.storeSqN[IDX_LEN-1:0] + IDX_LEN'(1));
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        
        if ($signed(IN_branch.storeSqN - baseIndex) >= NUM_ENTRIES-1)
            active = 0;
        else if (branchStSqNOneHot[(i-1) % NUM_ENTRIES])
            active = 1;
        else if (baseIndexOneHot[i])
            active = 0;
        
        invalRange_c[i] = active;
    end
end

SQEntry entries[NUM_ENTRIES-1:0] /* verilator public */;
SqN baseIndex /* verilator public */;

reg[NUM_ENTRIES-1:0] entryFused /* verilator public */;

reg empty;
always_comb begin
    empty = 1;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].addrAvail) empty = 0;
    end
end

typedef enum logic[0:0] {LOAD, STORE_FUSE} LookupType;
reg[31:0] lookupAddr[`NUM_AGUS-1:0];
LookupType lookupType[`NUM_AGUS-1:0];

for (genvar h = 0; h < `NUM_AGUS; h=h+1)
always_comb begin
    lookupAddr[h] = IN_uopLd[h].addr;
    lookupType[h] = LOAD;
    //if (!IN_uopLd[h].valid && OUT_uop.valid) begin
    //    case (h)
    //        0: lookupAddr[h] = {OUT_uop.addr[29:2], OUT_uop.addr[1:0] + 2'd2, 2'b0};
    //        1: lookupAddr[h] = {OUT_uop.addr[29:2], (&OUT_uop.wmask) ? (OUT_uop.addr[1:0] + 2'd3) : OUT_uop.addr[1:0], 2'b0};
    //    endcase
    //    lookupType[h] = STORE_FUSE;
    //end
end

reg[3:0] readMask[`NUM_AGUS-1:0];
always_comb begin
    for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
        readMask[i] = 4'b1111;
        if (IN_uopLd[i].valid)
            case (IN_uopLd[i].size)
                0: readMask[i] = (4'b1 << IN_uopLd[i].addr[1:0]);
                1: readMask[i] = ((IN_uopLd[i].addr[1:0] == 2) ? 4'b1100 : 4'b0011);
                default: readMask[i] = 4'b1111;
            endcase
    end
end

reg[3:0] lookupMask[`NUM_AGUS-1:0];
reg[31:0] lookupData[`NUM_AGUS-1:0];
reg lookupConflict[`NUM_AGUS-1:0];
reg[NUM_ENTRIES-1:0] lookupFuse[`NUM_AGUS-1:0];
// Store queue lookup
for (genvar h = 0; h < `NUM_AGUS; h=h+1)
always_comb begin
    
    reg[AXI_BWIDTH_E-3:0] shift = lookupAddr[h][2+:AXI_BWIDTH_E-2];
    reg[31:0] data = 'x;
    reg[3:0] mask = 'x;

    // Bytes that are not read by this op are set to available in the lookup mask
    // (could also do this in LSU)
    lookupMask[h] = ~readMask[h];
    lookupData[h] = 32'bx;
    lookupConflict[h] = 0;
    lookupFuse[h] = '0;
    
    for (integer i = 0; i < NUM_OUT; i=i+1) begin
        if (OUT_uop[i].valid &&
            OUT_uop[i].addr[31:2] == lookupAddr[h][31:2] && 
            !`IS_MMIO_PMA(OUT_uop[i].addr)
        ) begin
            for (integer j = 0; j < 4; j=j+1)
                if (OUT_uop[i].wmask[j])
                    lookupData[h][j*8 +: 8] = OUT_uop[i].data[j*8 +: 8];
            lookupMask[h] = lookupMask[h] | OUT_uop[i].wmask;
        end
    end

    for (integer i = 0; i < 4; i=i+1)
        if (lookupMaskIter[h][outputIdx][i])
            lookupData[h][i*8 +: 8] = lookupDataIter[h][outputIdx][i*8 +: 8];

    lookupMask[h] = lookupMask[h] | lookupMaskIter[h][outputIdx];    
    lookupConflict[h] = |lookupConflictList[h];
end

// This generates circular logic to iterate through the StoreQueue for forwarding data to loads.
// Circular logic is necessary to efficiently iterate through a circular buffer (which the SQ is).
// If tooling does not support this, it might be necessary to make the SQ a shift register again
// or chose one of the less efficient methods of iteration.
logic[31:0] lookupDataIter[`NUM_AGUS-1:0][NUM_ENTRIES-1:0];
logic[3:0]  lookupMaskIter[`NUM_AGUS-1:0][NUM_ENTRIES-1:0];
logic[NUM_ENTRIES-1:0] lookupConflictList[`NUM_AGUS-1:0];
wire[IDX_LEN-1:0] outputIdx = baseIndex[IDX_LEN-1:0] - 1;
generate
for (genvar h = 0; h < `NUM_AGUS; h=h+1)
for (genvar i = 0; i < NUM_ENTRIES; i=i+1)
always_comb begin

    integer prev = ((i-1) >= 0) ? (i-1) : (NUM_ENTRIES-1);
    // break in circular feedback
    if (i == baseIndex[IDX_LEN-1:0]) begin
        lookupMaskIter[h][i] = 0;
        lookupDataIter[h][i] = 0;
    end
    // continue circular feedback
    else begin
        lookupMaskIter[h][i] = lookupMaskIter[h][prev];
        lookupDataIter[h][i] = lookupDataIter[h][prev];
    end

    // actual forwarding
    lookupConflictList[h][i] = 0;
    lookupFuse[h][i] = 0;
    if (entries[i].addrAvail &&
        entries[i].addr == lookupAddr[h][31:2] && 
        ((lookupType[h] == LOAD && $signed(entries[i].sqN - IN_uopLd[h].sqN) < 0) || 
            entryReady_r[i]) &&
        !`IS_MMIO_PMA_W(entries[i].addr)
    ) begin
        
        if (entries[i].loaded) begin
            lookupFuse[h][i] = 1;
            for (integer j = 0; j < 4; j=j+1)
                if (entries[i].wmask[j]) begin
                    lookupDataIter[h][i][j*8 +: 8] = entries[i].data[j*8 +: 8];
                    lookupMaskIter[h][i][j] = 1;
                end
        end
        else if ((entries[i].wmask & readMask[h]) != 0) lookupConflictList[h][i] = 1;
    end
end
endgenerate

wire[IDX_LEN-1:0] baseIndexI = baseIndex[IDX_LEN-1:0];
wire[IDX_LEN-1:0] comStSqNI = IN_comStSqN[IDX_LEN-1:0];

assign OUT_done = baseIndex == IN_comStSqN;// && !anyInEv;

// Sort uops to enqueue by storeSqN
R_UOp rnUOpSorted[`DEC_WIDTH-1:0];
always_comb begin
    for (integer i = 0; i < `DEC_WIDTH; i=i+1) begin
        rnUOpSorted[i] = 'x;
        rnUOpSorted[i].valid = 0;
        
        for (integer j = 0; j < `DEC_WIDTH; j=j+1) begin
            // This could be one-hot...
            if (IN_rnUOp[j].valid && IN_rnUOp[j].storeSqN[$clog2(`DEC_WIDTH)-1:0] == i[$clog2(`DEC_WIDTH)-1:0] &&
                ((IN_rnUOp[j].fu == FU_AGU && IN_rnUOp[j].opcode >= LSU_SC_W) || IN_rnUOp[j].fu == FU_ATOMIC)
            ) begin
                rnUOpSorted[i] = IN_rnUOp[j];
            end
        end
    end
end

reg[NUM_ENTRIES-1:0] entryFused_c;
always_comb begin
    entryFused_c = entryFused;
    //if (OUT_uop.loaded && evInsert.valid)
    //    for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
    //        if (lookupType[i] == STORE_FUSE)
    //            entryFused_c = entryFused_c | lookupFuse[i];
    //    end
end

// Dequeue logic to infer sequential reads from SQ
logic[IDX_LEN-1:0] deqAddrsSorted[NUM_OUT-1:0];
logic[IDX_LEN-1:0] deqAddrs[NUM_OUT-1:0];
always_comb begin
    for (integer i = 0; i < NUM_OUT; i=i+1)
        deqAddrs[i] = baseIndexI + i[IDX_LEN-1:0];
    
    for (integer i = 0; i < NUM_OUT; i=i+1)
        deqAddrsSorted[i] = 'x;

    for (integer i = 0; i < NUM_OUT; i=i+1)
        deqAddrsSorted[deqAddrs[i][$clog2(NUM_OUT)-1:0]] = deqAddrs[i];
end
SQ_UOp deqPorts[NUM_OUT-1:0];
always_comb begin

    for (integer i = 0; i < NUM_OUT; i=i+1) begin
        logic[IDX_LEN-1:0] addr = 
            {deqAddrsSorted[i][IDX_LEN-1:$clog2(NUM_OUT)], i[$clog2(NUM_OUT)-1:0]};
        SQEntry entry = entries[addr];
        logic ready = entryReady_r[addr] && entry.loaded;

        deqPorts[i] = SQ_UOp'{valid: 0, default: 'x};
        if (ready) begin
            deqPorts[i].data = entry.data;
            deqPorts[i].addr = {entry.addr, 2'b0};
            deqPorts[i].wmask = entry.wmask;
            deqPorts[i].valid = 1;
        end
    end
end
SQ_UOp deqEntries[NUM_OUT-1:0];
always_comb begin
    logic prevValid = 1;
    for (integer i = 0; i < NUM_OUT; i=i+1) begin
        deqEntries[i] = prevValid ? 
            deqPorts[deqAddrs[i][$clog2(NUM_OUT)-1:0]] :
            SQ_UOp'{valid: 0, default: 'x};
        prevValid = deqEntries[i].valid;
    end
end

SQ_UOp outDeqView[NUM_OUT*2-1:0];
always_comb begin
    for (integer i = 0; i < NUM_OUT; i=i+1)
        outDeqView[i] = OUT_uop[i];

    for (integer i = 0; i < NUM_OUT; i=i+1)
        outDeqView[i+NUM_OUT] = deqEntries[i];
end

logic[NUM_OUT*2-1:0] unhandled;
always_comb begin
    for (integer i = 0; i < NUM_OUT; i=i+1)
        unhandled[i] = OUT_uop[i].valid && IN_stall[i];
    for (integer i = NUM_OUT; i < NUM_OUT*2; i=i+1)
        unhandled[i] = 1;
end
logic[$clog2(NUM_OUT):0] srcIdx[NUM_OUT-1:0];
PriorityEncoder#(2*NUM_OUT, NUM_OUT) penc
(
    .IN_data(unhandled),
    .OUT_idx(srcIdx),
    .OUT_idxValid()
);

// Dequeue/Enqueue
reg flushing;
assign OUT_flush = flushing;
always_ff@(posedge clk) begin
    
    for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
        OUT_fwd[i] <= 'x;
        OUT_fwd[i].valid <= 0;
    end

    if (rst) begin
        entryFused <= 0;
        
        baseIndex <= 0;
        
        OUT_maxStoreSqN <= NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        OUT_empty <= 1;
        flushing <= 0;
        
        for (integer i = 0; i < NUM_OUT; i=i+1)
            OUT_uop[i] <= SQ_UOp'{valid: 0, default: 'x};

        for (integer i = 0; i < NUM_ENTRIES; i=i+1)
            entries[i] <= SQEntry'{addrAvail: 0, loaded: 0, default: 'x};
    end
    else begin
    
        SqN nextBaseIndex = baseIndex;
        reg modified = 0;
        
        // Dequeue
        for (integer i = 0; i < NUM_OUT; i=i+1) begin
            reg[$clog2(NUM_OUT):0] idx = srcIdx[i];
            OUT_uop[i] <= outDeqView[idx];
            if (outDeqView[idx].valid && idx >= NUM_OUT) begin

                // todo: infer sequential writes
                reg[$clog2(NUM_ENTRIES)-1:0] idxSQ = 
                    baseIndexI + $clog2(NUM_ENTRIES)'(idx) - $clog2(NUM_ENTRIES)'(NUM_OUT);
                entries[idxSQ].loaded <= 0;
                entries[idxSQ].addrAvail <= 0;

                nextBaseIndex = nextBaseIndex + 1;
            end
        end

        // Write Loaded Data
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            if (IN_stDataUOp[i].valid && (!IN_branch.taken ||
                (!IN_branch.flush && $signed(IN_stDataUOp[i].storeSqN - IN_branch.storeSqN) <= 0))
            ) begin
                logic[IDX_LEN-1:0] idx = IN_stDataUOp[i].storeSqN[IDX_LEN-1:0];
                
                assert(idx[0] == i[0]); idx[0] = i[0];

                entries[idx].loaded <= 1;
                entries[idx].data <= IN_stDataUOp[i].data;
            end
        end

        // Invalidate
        if (IN_branch.taken) begin
            flushing <= IN_branch.flush;

            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if (entries[i].addrAvail)
                    if(!entryReady_c[i] &&
                        invalRange_c[i] !=
                        $signed(entries[i].sqN - IN_branch.sqN) > 0
                    ) begin
                        $display("got %x, baseIndex=%x, storeSqN=%x, %d\n", invalRange_c[i], baseIndex, IN_branch.storeSqN, i);
                        assert(0);
                    end
                if (invalRange_c[i] || (IN_branch.flush && !entryReady_r[i]))
                    entries[i] <= SQEntry'{addrAvail: 0, loaded: 0, default: 'x};
            end
        end
    
        // Set Address
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            if (IN_uopSt[i].valid && IN_uopSt[i].isStore &&
                (!IN_branch.taken || ($signed(IN_uopSt[i].sqN - IN_branch.sqN) <= 0 && !IN_branch.flush))
            ) begin
                reg[IDX_LEN-1:0] index = IN_uopSt[i].storeSqN[IDX_LEN-1:0];
                assert(IN_uopSt[i].storeSqN <= nextBaseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1);
                assert(!entries[index].addrAvail);
                
                
                if (IN_uopSt[i].exception == AGU_NO_EXCEPTION) begin
                    entries[index].sqN <= IN_uopSt[i].sqN;
                    entries[index].addr <= IN_uopSt[i].addr[31:2];
                    entries[index].wmask <= IN_uopSt[i].wmask;
                    entries[index].addrAvail <= 1;
                end

                modified = 1;
            end
        end

        OUT_empty <= empty && !modified;
        if (OUT_empty && flushing) begin
            flushing <= 0;
        end
        OUT_maxStoreSqN <= nextBaseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        
        for (integer i = 0; i < `NUM_AGUS; i=i+1)
            if (IN_uopLd[i].valid) begin
                OUT_fwd[i].valid <= 1;
                OUT_fwd[i].data <= lookupData[i];
                OUT_fwd[i].mask <= lookupMask[i];
                OUT_fwd[i].conflict <= lookupConflict[i];
            end

        baseIndex <= nextBaseIndex;
    end
end
endmodule
