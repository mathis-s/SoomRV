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
    logic addrAvail;
    logic loaded;
} SQEntry;

reg[NUM_ENTRIES-1:0] entryReady_r /* verilator public */;
always_ff@(posedge clk) entryReady_r <= rst ? 0 : entryReady_c;
reg[NUM_ENTRIES-1:0] entryValid_r;
always_ff@(posedge clk) entryValid_r <= rst ? 0 : entryValid_c;

wire[NUM_ENTRIES-1:0] baseIndexOneHot = (1 << baseIndex[IDX_LEN-1:0]);
wire[NUM_ENTRIES-1:0] comStSqNOneHot = (1 << IN_comStSqN[IDX_LEN-1:0]);
wire[NUM_ENTRIES-1:0] lastIndexOneHot = (1 << lastIndex[IDX_LEN-1:0]);

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

reg[NUM_ENTRIES-1:0] entryValid_c;
always_comb begin

    reg active = lastIndex[IDX_LEN-1:0] + 1'b1 < baseIndex[IDX_LEN-1:0];
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        integer prev = ((i-1) >= 0) ? (i-1) : (NUM_ENTRIES-1);
        if (SqN'(baseIndex + SqN'(NUM_ENTRIES - 1)) == lastIndex)
            active = 1;
        else if (lastIndexOneHot[prev])
            active = 0;
        else if (baseIndexOneHot[i])
            active = 1;
        
        entryValid_c[i] = active;
    end
end

SQEntry entries[NUM_ENTRIES-1:0] /* verilator public */;
SqN baseIndex /* verilator public */;
SqN lastIndex;

reg[NUM_ENTRIES-1:0] entryFused /* verilator public */;

reg empty;
always_comb begin
    empty = 1;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entryValid_c[i])
            empty = 0;
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
    
    /*if (lookupType[h] == LOAD) begin
        for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
            
            data = evicted[i].data[32*shift+:32];
            mask = evicted[i].wmask[4*shift+:4];

            if (evicted[i].valid &&
                evicted[i].addr[29:AXI_BWIDTH_E-2] == lookupAddr[h][31:AXI_BWIDTH_E] && 
                !`IS_MMIO_PMA_W(evicted[i].addr)
            ) begin
                for (integer j = 0; j < 4; j=j+1)
                    if (mask[j])
                        lookupData[h][j*8 +: 8] = data[j*8 +: 8];
                lookupMask[h] = lookupMask[h] | mask;
            end
        end
    end*/
    
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

`ifdef SQ_LINEAR
    begin
        reg active = 0;
        for (integer base = 0; base < 2; base=base+1)
            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                integer prev = ((i-1) >= 0) ? (i-1) : (NUM_ENTRIES-1);

                if (SqN'(baseIndex + SqN'(NUM_ENTRIES - 1)) == lastIndex) begin
                    if (baseIndexOneHot[i] && base == 0) active = 1;
                    else if (lastIndexOneHot[prev]) active = 0;
                end
                else begin
                    if (lastIndexOneHot[prev]) active = 0;
                    else if (baseIndexOneHot[i] && base == 0) active = 1;
                end

                if (active &&
                    entries[i].addrAvail &&
                    entries[i].addr == lookupAddr[h][31:2] && 
                    ((lookupType[h] == LOAD && $signed(entries[i].sqN - IN_uopLd[h].sqN) < 0) || 
                        entryReady_r[i]) &&
                    !`IS_MMIO_PMA_W(entries[i].addr)
                ) begin
                    if (entries[i].loaded) begin
                        lookupFuse[h][i] = 1;
                        for (integer j = 0; j < 4; j=j+1)
                            if (entries[i].wmask[j]) begin
                                lookupData[h][j*8 +: 8] = entries[i].data[j*8 +: 8];
                                lookupMask[h][j] = 1;
                            end
                    end
                    else if ((entries[i].wmask & readMask[h]) != 0) lookupConflict[h] = 1;
                end
            end
    end
`else
    for (integer i = 0; i < 4; i=i+1)
        if (lookupMaskIter[h][outputIdx][i])
            lookupData[h][i*8 +: 8] = lookupDataIter[h][outputIdx][i*8 +: 8];

    lookupMask[h] = lookupMask[h] | lookupMaskIter[h][outputIdx];    
    lookupConflict[h] = |lookupConflictList[h];
`endif
end

`ifndef SQ_LINEAR
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
    if ((entryValid_r[i]) && entries[i].addrAvail &&
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
`endif


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
        logic ready = entryReady_r[addr];

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
    for (integer i = 0; i < NUM_OUT; i=i+1) begin
        deqEntries[i] = deqPorts[deqAddrs[i][$clog2(NUM_OUT)-1:0]];
    end
end

SQ_UOp outDeqView[NUM_OUT*2-1:0];
always_comb begin
    for (integer i = 0; i < NUM_OUT; i=i+1)
        outDeqView[i] = OUT_uop[i];

    for (integer i = 0; i < NUM_OUT; i=i+1)
        outDeqView[i+NUM_OUT] = deqEntries[i];
end

reg[$clog2(NUM_OUT):0] numHandled_c;
always_comb begin
    numHandled_c = 0;
    for (integer i = 0; i < NUM_OUT; i=i+1)
        if (!IN_stall[i] || !OUT_uop[i].valid)
            numHandled_c = numHandled_c + 1;
end

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
        lastIndex <= '1;
        
        OUT_maxStoreSqN <= NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        OUT_empty <= 1;
        flushing <= 0;
        
        for (integer i = 0; i < NUM_OUT; i=i+1)
            OUT_uop[i] <= SQ_UOp'{valid: 0, default: 'x};
    end
    else begin
    
        SqN nextBaseIndex = baseIndex;
        reg modified = 0;
        
        // Dequeue
        for (integer i = 0; i < NUM_OUT; i=i+1) begin
            if (!IN_stall[i] || !OUT_uop[i].valid) begin
                reg[$clog2(NUM_OUT):0] idx = numHandled_c + $bits(numHandled_c)'(i);
                OUT_uop[i] <= outDeqView[idx];
                if (outDeqView[idx].valid && idx >= NUM_OUT)
                    nextBaseIndex = nextBaseIndex + 1;
            end
        end

        // Write Loaded Data
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            if (IN_stDataUOp[i].valid && (!IN_branch.taken ||
                (!IN_branch.flush && $signed(IN_stDataUOp[i].storeSqN - IN_branch.storeSqN) <= 0))
            ) begin
                logic[IDX_LEN-1:0] idx = 
                    IN_stDataUOp[i].storeSqN[IDX_LEN-1:0];
                
                assert(idx[0] == i[0]); idx[0] = i[0];

                entries[idx].loaded <= 1;
                entries[idx].data <= IN_stDataUOp[i].data;
            end
        end

        // Invalidate
        if (IN_branch.taken) begin            
            lastIndex <= IN_branch.storeSqN;
            flushing <= IN_branch.flush;
        end
    
        // Set Address
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            // TODO: indexed insert
            if (IN_uopSt[i].valid && IN_uopSt[i].isStore &&
                (!IN_branch.taken || ($signed(IN_uopSt[i].sqN - IN_branch.sqN) <= 0 && !IN_branch.flush))
            ) begin
                reg[IDX_LEN-1:0] index = IN_uopSt[i].storeSqN[IDX_LEN-1:0];
                assert(IN_uopSt[i].storeSqN <= nextBaseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1);
                assert(entryValid_c[index]);
                assert(!entries[index].addrAvail);
                if (IN_uopSt[i].exception == AGU_NO_EXCEPTION) begin
                    entries[index].addr <= IN_uopSt[i].addr[31:2];
                    entries[index].wmask <= IN_uopSt[i].wmask;
                    entries[index].addrAvail <= 1;
                end
                modified = 1;
            end
        end

        // Enqueue
        if (!IN_branch.taken) begin
            for (integer i = 0; i < WIDTH_RN; i=i+1)
                if (rnUOpSorted[i].valid) begin
                    
                    reg[IDX_LEN-1:0] index = {rnUOpSorted[i].storeSqN[IDX_LEN-1:$clog2(`DEC_WIDTH)], i[0+:$clog2(`DEC_WIDTH)]};
                    assert(rnUOpSorted[i].storeSqN <= nextBaseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1);
                    
                    entries[index].data <= 'x;
                    entries[index].addr <= 'x;
                    entries[index].wmask <= 0;

                    entries[index].loaded <= 0;
                    entries[index].sqN <= rnUOpSorted[i].sqN;
                    entries[index].addrAvail <= 0;

                    modified = 1;
                end
            for (integer i = 0; i < WIDTH_RN; i=i+1) begin
                if (IN_rnUOp[i].valid && ((IN_rnUOp[i].fu == FU_AGU && IN_rnUOp[i].opcode >= LSU_SC_W) || IN_rnUOp[i].fu == FU_ATOMIC))
                    lastIndex <= IN_rnUOp[i].storeSqN;
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
