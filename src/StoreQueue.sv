module StoreQueue
#(
    parameter NUM_ENTRIES=`SQ_SIZE,
    parameter NUM_EVICTED=4,
    parameter RESULT_BUS_COUNT=4,
    parameter WIDTH_RN = `DEC_WIDTH
)
(
    input wire clk,
    input wire rst,
    input wire IN_stallSt,
    output reg OUT_empty,
    output wire OUT_done,
    
    input AGU_UOp IN_uopSt[`NUM_AGUS-1:0],
    input LD_UOp IN_uopLd[`NUM_AGUS-1:0],
    
    input R_UOp IN_rnUOp[WIDTH_RN-1:0],
    input RES_UOp IN_resultUOp[RESULT_BUS_COUNT-1:0],
    input StDataUOp IN_stDataUOp[`NUM_AGUS-1:0],

    input VirtMemState IN_vmem,
    
    input SqN IN_curSqN,
    input SqN IN_comStSqN,
    
    input BranchProv IN_branch,
    
    output ST_UOp OUT_uopSt,
    output StFwdResult OUT_fwd[`NUM_AGUS-1:0],
    
    input ST_Ack IN_stAck,
    
    output wire OUT_flush,
    output SqN OUT_maxStoreSqN,
    output SQ_ComInfo OUT_sqInfo
);

localparam AXI_BWIDTH_E = $clog2(`AXI_WIDTH/8);

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

typedef struct packed
{
    logic[`AXI_WIDTH-1:0] data;
    logic[29:0] addr;
    logic[`AXI_WIDTH/8-1:0] wmask;
    
    logic issued;
    StNonce_t nonce;
    logic valid;
} EQEntry;

typedef struct packed
{
    StID_t idx;
    logic valid;
} IdxN;

reg[NUM_ENTRIES-1:0] entryReady_r /* verilator public */;
always_ff@(posedge clk) entryReady_r <= rst ? 0 : entryReady_c;
reg[NUM_ENTRIES-1:0] entryValid_r;
always_ff@(posedge clk) entryValid_r <= rst ? 0 : entryValid_c;

wire[NUM_ENTRIES-1:0] baseIndexOneHot = (1 << baseIndex[$clog2(NUM_ENTRIES)-1:0]);
wire[NUM_ENTRIES-1:0] comStSqNOneHot = (1 << IN_comStSqN[$clog2(NUM_ENTRIES)-1:0]);
wire[NUM_ENTRIES-1:0] lastIndexOneHot = (1 << lastIndex[$clog2(NUM_ENTRIES)-1:0]);

reg[NUM_ENTRIES-1:0] entryReady_c;
always_comb begin
    reg active = IN_comStSqN[$clog2(NUM_ENTRIES)-1:0] < baseIndex[$clog2(NUM_ENTRIES)-1:0];
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

    reg active = lastIndex[$clog2(NUM_ENTRIES)-1:0] + 1'b1 < baseIndex[$clog2(NUM_ENTRIES)-1:0];
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

SQEntry entryOut /* verilator public */;

always_ff@(posedge clk) begin
    OUT_sqInfo <= 'x;
    OUT_sqInfo.valid <= 0;
    if (rst) ;
    else if (loadBaseIndexValid) begin
        OUT_sqInfo.valid <= 1;
        OUT_sqInfo.maxComSqN <= entries[loadBaseIndex[$clog2(NUM_ENTRIES)-1:0]].sqN;
    end
end

// Find oldest not-yet-loaded entry 
reg loadBaseIndexValid;
reg[$clog2(NUM_ENTRIES)-1:0] loadBaseIndex;
always_comb begin
    reg[NUM_ENTRIES-1:0] isNotLoaded;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        isNotLoaded[i] =
            entryValid_c[i] && (!entries[i].loaded);
    end

    // Priority encode beginning at base index
    loadBaseIndexValid = 0;
    loadBaseIndex = 'x;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        reg[$clog2(NUM_ENTRIES)-1:0] idx = i[$clog2(NUM_ENTRIES)-1:0] + baseIndex[$clog2(NUM_ENTRIES)-1:0];
        if (!loadBaseIndexValid && 
            isNotLoaded[idx]
        ) begin
            loadBaseIndexValid = 1;
            loadBaseIndex = idx;
        end
    end
end

reg empty;
always_comb begin
    empty = 1;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entryValid_c[i])
            empty = 0;
    end
    for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
        if (evicted[i].valid)
            empty = 0;
    end
    if (IN_stAck.valid && IN_stAck.fail) empty = 0;
end

EQEntry evicted[NUM_EVICTED-1:0] /* verilator public */;

ST_Ack stAck_r;
always_ff@(posedge clk) begin
    if (!rst) stAck_r <= IN_stAck;
    else begin
        stAck_r <= 'x;
        stAck_r.valid <= 0;
    end
end

reg[3:0] readMask[`NUM_AGUS-1:0];
always_comb begin
    for (integer i = 0; i < `NUM_AGUS; i=i+1)
        case (IN_uopLd[i].size)
            0: readMask[i] = (4'b1 << IN_uopLd[i].addr[1:0]);
            1: readMask[i] = ((IN_uopLd[i].addr[1:0] == 2) ? 4'b1100 : 4'b0011);
            default: readMask[i] = 4'b1111;
        endcase
end

typedef enum logic[0:0] {LOAD, STORE_FUSE} LookupType;
reg[31:0] lookupAddr[`NUM_AGUS-1:0];
LookupType lookupType[`NUM_AGUS-1:0];
for (genvar h = 0; h < `NUM_AGUS; h=h+1)
always_comb begin
    lookupAddr[h] = IN_uopLd[h].addr;
    lookupType[h] = LOAD;
end

reg[3:0] lookupMask[`NUM_AGUS-1:0];
reg[31:0] lookupData[`NUM_AGUS-1:0];
reg lookupConflict[`NUM_AGUS-1:0];
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
    
    if (lookupType[h] == LOAD) begin
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
    end

    if (entryOut.loaded &&
        entryOut.addr[29:0] == lookupAddr[h][31:2] && 
        !`IS_MMIO_PMA_W(entryOut.addr)
    ) begin
        for (integer j = 0; j < 4; j=j+1)
            if (entryOut.wmask[j])
                lookupData[h][j*8 +: 8] = entryOut.data[j*8 +: 8];
        lookupMask[h] = lookupMask[h] | entryOut.wmask;
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
wire[$clog2(NUM_ENTRIES)-1:0] outputIdx = baseIndex[$clog2(NUM_ENTRIES)-1:0] - 1;
generate
for (genvar h = 0; h < `NUM_AGUS; h=h+1)
for (genvar i = 0; i < NUM_ENTRIES; i=i+1)
always_comb begin

    integer prev = ((i-1) >= 0) ? (i-1) : (NUM_ENTRIES-1);
    // break in circular feedback
    if (i == baseIndex[$clog2(NUM_ENTRIES)-1:0]) begin
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
    if ((entryValid_r[i]) && entries[i].addrAvail &&
        entries[i].addr == lookupAddr[h][31:2] && 
        ((lookupType[h] == LOAD && $signed(entries[i].sqN - IN_uopLd[h].sqN) < 0) || 
            entryReady_r[i]) &&
        !`IS_MMIO_PMA_W(entries[i].addr)
    ) begin
        
        if (entries[i].loaded) begin
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

wire[$clog2(NUM_ENTRIES)-1:0] baseIndexI = baseIndex[$clog2(NUM_ENTRIES)-1:0];
wire[$clog2(NUM_ENTRIES)-1:0] comStSqNI = IN_comStSqN[$clog2(NUM_ENTRIES)-1:0];

logic mmioOpInEv;
logic anyInEv;
always_comb begin
    mmioOpInEv = 0;
    anyInEv = 0;
    for (integer i = 0; i < NUM_EVICTED; i=i+1)
        if (evicted[i].valid) begin
            anyInEv = 1;
           if (`IS_MMIO_PMA_W(evicted[i].addr))
            mmioOpInEv = 1;
        end
end

assign OUT_done = baseIndex == IN_comStSqN && !anyInEv;



IdxN evInsert;
always_comb begin
    evInsert = IdxN'{valid: 0, default: 'x};

    if (!(mmioOpInEv && `IS_MMIO_PMA_W(entryOut.addr)))
        for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
            if ((evicted[i].valid && evicted[i].addr[29:AXI_BWIDTH_E-2] == entryOut.addr[29:AXI_BWIDTH_E-2]) ||
                (!evicted[i].valid && !evInsert.valid)
            ) begin
                evInsert.valid = 1;
                evInsert.idx = i[$bits(evInsert.idx)-1:0];
            end
        end
end

// Select evicted entry to re-issue
IdxN reIssue;
always_comb begin
    reIssue = IdxN'{valid: 0, default: 'x};
    for (integer i = NUM_EVICTED - 1; i >= 0; i=i-1) begin
        if (evicted[i].valid && !evicted[i].issued) begin
            reIssue.valid = 1;
            reIssue.idx = i[$clog2(NUM_EVICTED)-1:0];
        end
    end
end

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

// Dequeue/Enqueue
reg flushing;
assign OUT_flush = flushing;
always_ff@(posedge clk) begin
    
    for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
        OUT_fwd[i] <= 'x;
        OUT_fwd[i].valid <= 0;
    end

    if (rst) begin
        
        for (integer i = 0; i < NUM_EVICTED; i=i+1)
            evicted[i].valid <= 0;
        
        baseIndex <= 0;
        lastIndex <= '1;
        
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        OUT_empty <= 1;
        OUT_uopSt.valid <= 0;
        flushing <= 0;

        entryOut <= SQEntry'{loaded: 0, default: 'x};
    end
    else begin
    
        SqN nextBaseIndex = baseIndex;
        reg modified = 0;

        if (OUT_uopSt.valid) begin
            OUT_uopSt <= ST_UOp'{valid: 0, default: 'x};
            if (IN_stallSt)
                evicted[OUT_uopSt.id].issued <= 0;
        end

        if (stAck_r.valid && stAck_r.nonce == evicted[stAck_r.idx].nonce) begin
            // delete if store ack has most recent nonce and successful
            if (evicted[stAck_r.idx].nonce == stAck_r.nonce) begin
                evicted[stAck_r.idx].issued <= 0;
                if (!stAck_r.fail) begin
                    evicted[stAck_r.idx] <= 'x;
                    evicted[stAck_r.idx].wmask <= 0;
                    evicted[stAck_r.idx].valid <= 0;
                end
            end
        end

        // Issue op from evicted
        if (reIssue.valid) begin
            modified = 1;
            
            evicted[reIssue.idx].issued <= 1;

            OUT_uopSt.valid <= 1;
            OUT_uopSt.id <= reIssue.idx;
            OUT_uopSt.nonce <= evicted[reIssue.idx].nonce;
            OUT_uopSt.addr <= {evicted[reIssue.idx].addr, 2'b0};
            OUT_uopSt.data <= evicted[reIssue.idx].data;
            OUT_uopSt.wmask <= evicted[reIssue.idx].wmask;
            OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(evicted[reIssue.idx].addr);
        end
        
        // Enqueue into evicted
        if (entryOut.loaded && evInsert.valid) begin
            reg[`AXI_WIDTH-1:0] data = 'x;
            reg[`AXI_WIDTH/8-1:0] mask = 'x;
            StNonce_t newNonce = evicted[evInsert.idx].nonce + 1;
            
            modified = 1;

            entryOut <= SQEntry'{loaded: 0, default: 'x};   
            
            if (`IS_MMIO_PMA_W(entryOut.addr)) begin
                data[31:0] = entryOut.data;
                mask[3:0] = entryOut.wmask;
            end
            else begin
                mask = evicted[evInsert.idx].wmask | 
                    (`AXI_WIDTH/8)'(entryOut.wmask) << (entryOut.addr[AXI_BWIDTH_E-3:0]*4);

                for (integer i = 0; i < 16; i=i+1) begin
                    if ((AXI_BWIDTH_E-2)'(i/4) == entryOut.addr[AXI_BWIDTH_E-3:0] && entryOut.wmask[i%4])
                        data[i*8+:8] = entryOut.data[(i%4)*8+:8];
                    else
                        data[i*8+:8] = evicted[evInsert.idx].data[i*8+:8];
                end
            end
            
            evicted[evInsert.idx].issued <= 0;
            evicted[evInsert.idx].nonce <= newNonce;
            evicted[evInsert.idx].data <= data;
            evicted[evInsert.idx].wmask <= mask;
            evicted[evInsert.idx].addr <= entryOut.addr;
            evicted[evInsert.idx].valid <= 1;
            
            if (!reIssue.valid) begin
                evicted[evInsert.idx].issued <= 1;

                OUT_uopSt.valid <= 1;
                OUT_uopSt.id <= evInsert.idx;
                OUT_uopSt.nonce <= newNonce;
                OUT_uopSt.addr <= {entryOut.addr[29:2], 4'b0};
                OUT_uopSt.data <= data;
                OUT_uopSt.wmask <= mask;
                OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(entryOut.addr);
            end

        end

        // Dequeue
        begin
            reg[$clog2(NUM_ENTRIES)-1:0] idx = baseIndex[$clog2(NUM_ENTRIES)-1:0];
            if (!IN_branch.taken && 
                entryReady_r[idx] &&
                entries[idx].loaded &&
                entries[idx].addrAvail &&
                (!entryOut.loaded || evInsert.valid)
            ) begin

                modified = 1;
                entryOut <= entries[idx];
                entries[idx] <= 'x;        
                nextBaseIndex = nextBaseIndex + 1;
            end
        end

        // Write Loaded Data
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            if (IN_stDataUOp[i].valid && (!IN_branch.taken ||
                (!IN_branch.flush && $signed(IN_stDataUOp[i].storeSqN - IN_branch.storeSqN) <= 0))
            ) begin
                logic[$clog2(NUM_ENTRIES)-1:0] idx = 
                    IN_stDataUOp[i].storeSqN[$clog2(NUM_ENTRIES)-1:0];
                
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
                reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uopSt[i].storeSqN[$clog2(NUM_ENTRIES)-1:0];
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
                    
                    reg[$clog2(NUM_ENTRIES)-1:0] index = {rnUOpSorted[i].storeSqN[$clog2(NUM_ENTRIES)-1:$clog2(`DEC_WIDTH)], i[0+:$clog2(`DEC_WIDTH)]};
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
