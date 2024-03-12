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
    input AMO_Data_UOp IN_amoData,
    output reg[$bits(Tag)-2:0] OUT_RF_raddr,
    input wire[31:0] IN_RF_rdata,
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

typedef struct packed
{
    union packed
    {
        logic[31:0] _data;
        struct packed
        {
            Tag tag;
        } m;
    } data;

    logic[29:0] addr;

    // wmask == 0 is escape sequence for special operations
    logic[3:0] wmask;
    
    SqN sqN;
    
    logic atomicLd;
    logic atomic;
    logic addrAvail;
    logic loaded;
    logic avail;

} SQEntry;

reg[NUM_ENTRIES-1:0] entryReady_r;
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

SQEntry entries[NUM_ENTRIES-1:0];
SqN baseIndex;
SqN lastIndex;
//assign OUT_sqInfo = SQ_ComInfo'{valid: 0, default: 'x};

always_ff@(posedge clk) begin
    OUT_sqInfo <= 'x;
    OUT_sqInfo.valid <= 0;
    if (rst) ;
    else if (loadBaseIndexValid) begin
        OUT_sqInfo.valid <= 1;
        OUT_sqInfo.maxComSqN <= entries[loadBaseIndex[$clog2(NUM_ENTRIES)-1:0]].sqN;
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
        if (evicted[i].valid && !evicted[i].issued)
            empty = 0;
    end
    if (IN_stAck.valid && IN_stAck.fail) empty = 0;
end

typedef struct packed
{
    SQEntry s;
    StID_t id;
    logic issued;
    logic valid;
} EQEntry;
EQEntry evicted[NUM_EVICTED-1:0];

ST_Ack stAck_r;
always_ff@(posedge clk) begin
    if (!rst) stAck_r <= IN_stAck;
    else begin
        stAck_r <= 'x;
        stAck_r.valid <= 0;
    end
end

reg[$clog2(NUM_EVICTED):0] evictedIn;

reg[3:0] readMask[`NUM_AGUS-1:0];
always_comb begin
    for (integer i = 0; i < `NUM_AGUS; i=i+1)
        case (IN_uopLd[i].size)
            0: readMask[i] = (4'b1 << IN_uopLd[i].addr[1:0]);
            1: readMask[i] = ((IN_uopLd[i].addr[1:0] == 2) ? 4'b1100 : 4'b0011);
            default: readMask[i] = 4'b1111;
        endcase
end

reg[3:0] lookupMask[`NUM_AGUS-1:0];
reg[31:0] lookupData[`NUM_AGUS-1:0];
reg lookupConflict[`NUM_AGUS-1:0];
// Store queue lookup
for (genvar h = 0; h < `NUM_AGUS; h=h+1)
always_comb begin
    // Bytes that are not read by this op are set to available in the lookup mask
    // (could also do this in LSU)
    lookupMask[h] = ~readMask[h];
    lookupData[h] = 32'bx;
    lookupConflict[h] = 0;
    
    for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
        if (evicted[i].valid &&
            evicted[i].s.addr == IN_uopLd[h].addr[31:2] && 
            !`IS_MMIO_PMA_W(evicted[i].s.addr)
        ) begin
            for (integer j = 0; j < 4; j=j+1)
                if (evicted[i].s.wmask[j])
                    lookupData[h][j*8 +: 8] = evicted[i].s.data[j*8 +: 8];
            lookupMask[h] = lookupMask[h] | evicted[i].s.wmask;
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
                    entries[i].addr == IN_uopLd[h].addr[31:2] && 
                    ($signed(entries[i].sqN - IN_uopLd[h].sqN) < 0 || entryReady_r[i]) &&
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
    if ((entryValid_c[i]) && entries[i].addrAvail &&
        entries[i].addr == IN_uopLd[h].addr[31:2] && 
        ($signed(entries[i].sqN - IN_uopLd[h].sqN) < 0 || entryReady_r[i]) &&
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

assign OUT_done = 
    baseIndex == IN_comStSqN &&
    evictedIn == 0;

// Do not re-order stores before stores at the same address; and do not re-order MMIO stores.
reg allowDequeue;
always_comb begin
    allowDequeue = 1;
    
    // When a store cache miss occurs, collisions with any issued ops
    // are handled by the LSU. We have to make sure not to issue any
    // conflicting new ops though.
    for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
        if (evicted[i].valid &&

            (!evicted[i].issued || 
                // Forward negative store acks
                (IN_stAck.valid && IN_stAck.fail && IN_stAck.id == evicted[i].id) ||
                (stAck_r.valid && stAck_r.fail && stAck_r.id == evicted[i].id)) &&

            ((evicted[i].s.addr == entries[baseIndexI].addr) || // todo: be less strict by looking at wmask
                (`IS_MMIO_PMA_W(evicted[i].s.addr) && `IS_MMIO_PMA_W(entries[baseIndexI].addr)) ||
                (evicted[i].s.wmask == 0)))
            allowDequeue = 0;
    end
end

// Bitfield for tracking used/free evicted store IDs
reg[NUM_EVICTED-1:0] evictedUsedIds;
reg[$clog2(NUM_EVICTED)-1:0] evictedNextId;
reg evictedNextIdValid;
always_comb begin
    evictedNextId = 'x;
    evictedNextIdValid = 0;
    for (integer i = NUM_EVICTED-1; i >= 0; i=i-1) begin
        if (!evictedUsedIds[i]) begin
            evictedNextId = i[$clog2(NUM_EVICTED)-1:0];
            evictedNextIdValid = 1;
        end
    end
    
    // Re-use id from current ack if possible to avoid wait cycle
    if (stAck_r.valid && !stAck_r.fail) begin
        evictedNextId = stAck_r.id;
        evictedNextIdValid = 1;
    end
end

// Find index of entry corresponding to current store acknowledgement from LSU 
reg[$clog2(NUM_EVICTED)-1:0] stAckIdx;
reg stAckIdxValid;
always_comb begin
    stAckIdx = 'x;
    stAckIdxValid = 0;
    for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
        if (stAck_r.valid && evicted[i].valid && evicted[i].id == stAck_r.id) begin
            //assert(!stAckIdxValid);
            stAckIdx = i[$clog2(NUM_EVICTED)-1:0];
            stAckIdxValid = 1;
        end
    end
end

// Track Store Data Availability
logic[NUM_ENTRIES-1:0] dataAvail;
always_comb begin
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        dataAvail[i] = 0;
        if (entryValid_c[i] && !entries[i].avail) begin
            for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1) begin
                if (IN_resultUOp[j].valid && 
                    !IN_resultUOp[j].tagDst[6] &&
                    IN_resultUOp[j].tagDst[$bits(Tag)-2:0] == entries[i].data.m.tag[$bits(Tag)-2:0]
                ) begin
                    dataAvail[i] = 1;
                end
            end
        end
    end
end

// Select entry for which to read store data from RF
typedef struct packed
{
    logic[31:0] atomicData;
    logic atomic;
    Tag tag;
    logic[3:0] wmask;
    logic[$clog2(NUM_ENTRIES)-1:0] index;
    logic valid;
} SQLoad;

SQLoad load_c;
SQLoad load_r;
always_comb begin
    // Find candidates
    reg[NUM_ENTRIES-1:0] isLoadCandidate;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        isLoadCandidate[i] =
            entryValid_r[i] && !entries[i].loaded && entries[i].avail && entries[i].addrAvail && !entries[i].atomicLd;
    end
    if (load_r.valid) isLoadCandidate[load_r.index] = 0;

    // Priority encode beginning at base index
    load_c = 'x;
    load_c.valid = 0;

    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        reg[$clog2(NUM_ENTRIES)-1:0] idx = i[$clog2(NUM_ENTRIES)-1:0] + baseIndex[$clog2(NUM_ENTRIES)-1:0];
        if (!load_c.valid && 
            isLoadCandidate[idx]
        ) begin
            load_c.valid = 1;
            load_c.index = idx;
            load_c.atomic = 0;
        end
    end

    // If an atomic op result is incoming, load that instead
    if (IN_amoData.valid) begin
        load_c.atomic = 1;
        load_c.valid = 1;
        load_c.index = IN_amoData.storeSqN[$clog2(NUM_ENTRIES)-1:0];
        load_c.atomicData = IN_amoData.result;
    end
    
    OUT_RF_raddr = '0;
    if (load_c.valid) begin
        load_c.wmask = entries[load_c.index].wmask;
        load_c.tag = entries[load_c.index].data.m.tag[$bits(Tag)-1:0];

        if (!load_c.tag[$bits(Tag)-1]) begin
            OUT_RF_raddr = load_c.tag[$bits(Tag)-2:0];
        end
    end
    
    // Late override
    if (IN_branch.taken && ($signed(entries[load_c.index].sqN - IN_branch.sqN) > 0 || IN_branch.flush))
        load_c = SQLoad'{valid: 0, default: 'x};
        
end
always_ff@(posedge clk) begin
    if (rst) load_r <= SQLoad'{valid: 0, default: 'x};
    else load_r <= load_c;
end

// Find oldest not-yet-loaded entry 
reg loadBaseIndexValid;
reg[$clog2(NUM_ENTRIES)-1:0] loadBaseIndex;
always_comb begin
    reg[NUM_ENTRIES-1:0] isNotLoaded;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        isNotLoaded[i] =
            entryValid_c[i] && (!entries[i].loaded || !entries[i].addrAvail);
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

// Preprocess store data
reg[31:0] loadData;
always_comb begin
    reg[31:0] rawLoadData = 'x;
    loadData = 'x;

    if (load_r.atomic)
        rawLoadData = load_r.atomicData;
    else if (load_r.tag[$bits(Tag)-1])
        rawLoadData = {{26{load_r.tag[5]}}, load_r.tag[5:0]};
    else
        rawLoadData = IN_RF_rdata;
    // since we're deconstructing it anyways,
    // we may want to store offset + size instead of wmask

    case (load_r.wmask)
        default: loadData = rawLoadData;
        4'b0001: loadData[7:0] = rawLoadData[7:0];
        4'b0010: loadData[15:8] = rawLoadData[7:0];
        4'b0100: loadData[23:16] = rawLoadData[7:0];
        4'b1000: loadData[31:24] = rawLoadData[7:0];
        4'b0011: loadData[15:0] = rawLoadData[15:0];
        4'b1100: loadData[31:16] = rawLoadData[15:0];
    endcase
end

// Select evicted entry to re-issue
logic reIssueValid;
logic[$clog2(NUM_EVICTED)-1:0] reIssueIdx;
always_comb begin
    reIssueValid = 0;
    reIssueIdx = 'x;

    for (integer i = NUM_EVICTED - 1; i >= 0; i=i-1) begin
        if (evicted[i].valid && !evicted[i].issued) begin
            reIssueValid = 1;
            reIssueIdx = i[$clog2(NUM_EVICTED)-1:0];
        end
    end
    
    // check for collisions with incoming store NACKs
    reIssueValid &= 
        (!stAck_r.valid || !stAck_r.fail || 
            (stAck_r.addr[31:2] != evicted[reIssueIdx].s.addr && 
                !(`IS_MMIO_PMA(stAck_r.addr) && `IS_MMIO_PMA_W(evicted[reIssueIdx].s.addr)))) &&
        (!IN_stAck.valid || !IN_stAck.fail || 
            (IN_stAck.addr[31:2] != evicted[reIssueIdx].s.addr && 
                !(`IS_MMIO_PMA(IN_stAck.addr) && `IS_MMIO_PMA_W(evicted[reIssueIdx].s.addr))));
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
        
        evictedIn <= 0;
        
        baseIndex <= 0;
        lastIndex <= '1;
        
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        OUT_empty <= 1;
        OUT_uopSt.valid <= 0;
        flushing <= 0;
        evictedUsedIds <= 0;
    end
    else begin
    
        SqN nextBaseIndex = baseIndex;

        reg modified = 0;
        reg[$clog2(NUM_EVICTED):0] nextEvictedIn = evictedIn;

        if (!IN_stallSt)
            OUT_uopSt.valid <= 0;
        
        // Delete entry from evicted if we get a positive store ack
        if (stAck_r.valid) begin
            assert(stAckIdxValid);
            if (!stAck_r.fail) begin
                for (integer i = 0; i < NUM_EVICTED-1; i=i+1) begin
                    if (i >= stAckIdx) begin
                        evicted[i] <= evicted[i+1];
                    end
                end
                evicted[NUM_EVICTED-1] <= 'x;
                evicted[NUM_EVICTED-1].valid <= 0;

                nextEvictedIn = nextEvictedIn - 1;
                evictedUsedIds[stAck_r.id] <= 0;
            end
            else begin
                evicted[stAckIdx].issued <= 0;
                modified = 1;
            end
        end

        // Dequeue
        if (!IN_stallSt) begin
            reg[$clog2(NUM_ENTRIES)-1:0] idx = baseIndex[$clog2(NUM_ENTRIES)-1:0];
            // Try storing new op
            if (!IN_branch.taken && 
                entryReady_r[idx] && nextEvictedIn < NUM_EVICTED &&
                entries[idx].loaded && allowDequeue &&
                entries[idx].addrAvail
            ) begin
                assert(evictedNextIdValid);
                modified = 1;

                entries[idx] <= 'x;        
                OUT_uopSt.valid <= 1;
                OUT_uopSt.id <= evictedNextId;
                OUT_uopSt.addr <= {entries[idx].addr, 2'b0};
                OUT_uopSt.data <= entries[idx].data;
                OUT_uopSt.wmask <= entries[idx].wmask;
                OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(entries[idx].addr);
                
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].s <= entries[idx];
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].issued <= 1;
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].id <= evictedNextId;
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].valid <= 1;
                nextEvictedIn = nextEvictedIn + 1;
                    
                evictedUsedIds[evictedNextId] <= 1;
                nextBaseIndex = nextBaseIndex + 1;
            end

            // Re-issue op that previously missed cache
            else if (reIssueValid) begin
                OUT_uopSt.valid <= 1;
                OUT_uopSt.id <= evicted[reIssueIdx].id;
                OUT_uopSt.addr <= {evicted[reIssueIdx].s.addr, 2'b0};
                OUT_uopSt.data <= evicted[reIssueIdx].s.data;
                OUT_uopSt.wmask <= evicted[reIssueIdx].s.wmask;
                OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(evicted[reIssueIdx].s.addr);
                
                if (stAck_r.valid && !stAck_r.fail && reIssueIdx >= stAckIdx)
                    evicted[reIssueIdx - 1].issued <= 1;
                else
                    evicted[reIssueIdx].issued <= 1;

                modified = 1;
            end
        end
        
        // Set Availability
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (entryValid_c[i] && dataAvail[i])
                entries[i].avail <= 1;
        end

        // Write Loaded Data
        if (load_r.valid) begin
            entries[load_r.index].avail <= 1;
            entries[load_r.index].loaded <= 1;
            entries[load_r.index].data <= loadData;
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

                    entries[index].atomicLd <= 0;
                    entries[index].atomic <= 0;
                    entries[index].loaded <= 0;
                    entries[index].sqN <= rnUOpSorted[i].sqN;
                    entries[index].addrAvail <= 0;
                    entries[index].avail <= rnUOpSorted[i].availB;
                    entries[index].data.m.tag <= rnUOpSorted[i].tagB;

                    for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1)
                        if (IN_resultUOp[j].valid && !IN_resultUOp[j].tagDst[6] && rnUOpSorted[i].tagB == IN_resultUOp[j].tagDst)
                            entries[index].avail <= 1;

                    // Atomic Ops special handling
                    if (rnUOpSorted[i].fu == FU_ATOMIC) begin
                        entries[index].atomic <= 1;
                        if (rnUOpSorted[i].opcode != ATOMIC_AMOSWAP_W) begin
                            
                            entries[index].atomicLd <= 1;
                            entries[index].data.m.tag <= 'x;
                            // operand cannot be available yet
                            entries[index].avail <= 0;
                        end
                    end
                    
                    // Cache Block Ops special handling
                    if (rnUOpSorted[i].fu == FU_AGU) begin
                        case (rnUOpSorted[i].opcode)
                            LSU_CBO_CLEAN: begin
                                entries[index].data <= {30'bx, 2'd0};
                                entries[index].loaded <= 1;
                            end
                            LSU_CBO_INVAL: begin
                                entries[index].data <= {30'bx, (IN_vmem.cbie == 3) ? 2'd1 : 2'd2};
                                entries[index].loaded <= 1;
                            end
                            LSU_CBO_FLUSH: begin
                                entries[index].data <= {30'bx, 2'd2};
                                entries[index].loaded <= 1;
                            end
                            default: ;
                        endcase
                    end

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

        evictedIn <= nextEvictedIn;
        baseIndex <= nextBaseIndex;
    end
end
endmodule
