module StoreQueue
#(
    parameter NUM_ENTRIES=`SQ_SIZE,
    parameter NUM_EVICTED=4,
    parameter RESULT_BUS_COUNT=3,
    parameter WIDTH_RN = `DEC_WIDTH
)
(
    input wire clk,
    input wire rst,
    input wire IN_stallSt,
    input wire IN_stallLd,
    output reg OUT_empty,
    output reg OUT_done,
    
    input AGU_UOp IN_uopSt,
    input LD_UOp IN_uopLd,
    
    input R_UOp IN_rnUOp[WIDTH_RN-1:0],
    input RES_UOp IN_resultUOp[RESULT_BUS_COUNT-1:0],
    output reg[$bits(Tag)-2:0] OUT_RF_raddr,
    input wire[31:0] IN_RF_rdata,
    
    input SqN IN_curSqN,
    
    input BranchProv IN_branch,
    
    output ST_UOp OUT_uopSt,
    output StFwdResult OUT_fwd,
    
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
    
    logic addrAvail;
    logic ready;
    logic loaded;
    logic avail;
    logic valid;
} SQEntry;

SQEntry entries[NUM_ENTRIES-1:0];
SqN baseIndex;
reg[$clog2(NUM_ENTRIES):0] loadBaseIndex;

always_comb begin
    OUT_sqInfo = 'x;
    OUT_sqInfo.valid =
        entries[loadBaseIndex[$clog2(NUM_ENTRIES)-1:0]].valid;
    if (OUT_sqInfo.valid)
        OUT_sqInfo.maxComSqN = entries[loadBaseIndex[$clog2(NUM_ENTRIES)-1:0]].sqN;
end

reg empty;
always_comb begin
    empty = 1;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].valid)
            empty = 0;
    end
end

typedef struct packed
{
    SQEntry s;
    StID_t id;
    logic issued;
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

reg[3:0] readMask;
always_comb begin
    case (IN_uopLd.size)
        0: readMask = (4'b1 << IN_uopLd.addr[1:0]);
        1: readMask = ((IN_uopLd.addr[1:0] == 2) ? 4'b1100 : 4'b0011);
        default: readMask = 4'b1111;
    endcase
end

reg[3:0] lookupMask;
reg[31:0] lookupData;
reg lookupConflict;
// Store queue lookup
always_comb begin
    // Bytes that are not read by this op are set to available in the lookup mask
    // (could also do this in LSU)
    lookupMask = ~readMask;
    lookupData = 32'bx;
    lookupConflict = 0;
    
    for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
        if (evicted[i].s.valid &&
            evicted[i].s.addr == IN_uopLd.addr[31:2] && 
            !`IS_MMIO_PMA_W(evicted[i].s.addr)
        ) begin
            for (integer j = 0; j < 4; j=j+1)
                if (evicted[i].s.wmask[j])
                    lookupData[j*8 +: 8] = evicted[i].s.data[j*8 +: 8];
            lookupMask = lookupMask | evicted[i].s.wmask;
        end
    end

    for (integer i = 0; i < 4; i=i+1)
        if (lookupMaskIter[outputIdx][i])
            lookupData[i*8 +: 8] = lookupDataIter[outputIdx][i*8 +: 8];

    lookupMask = lookupMask | lookupMaskIter[outputIdx];    
    lookupConflict = |lookupConflictList;
end

// This generates circular logic to iterate through the StoreQueue for forwarding data to loads.
// Circular logic is necessary to efficiently iterate through a circular buffer (which the SQ is).
// If tooling does not support this, it might be necessary to make the SQ a shift register again
// or chose one of the less efficient methods of iteration.
logic[31:0] lookupDataIter[NUM_ENTRIES-1:0];
logic[3:0]  lookupMaskIter[NUM_ENTRIES-1:0];
logic[NUM_ENTRIES-1:0] lookupConflictList;
wire[$clog2(NUM_ENTRIES)-1:0] outputIdx = baseIndex[$clog2(NUM_ENTRIES)-1:0] - 1;
generate
for (genvar i = 0; i < NUM_ENTRIES; i=i+1)
always_comb begin
    integer prev = ((i-1) >= 0) ? (i-1) : (NUM_ENTRIES-1);
    // break in circular feedback
    if (i == baseIndex[$clog2(NUM_ENTRIES)-1:0]) begin
        lookupMaskIter[i] = 0;
        lookupDataIter[i] = 'x;
    end
    // continue circular feedback
    else begin
        lookupMaskIter[i] = lookupMaskIter[prev];
        lookupDataIter[i] = lookupDataIter[prev];
    end

    // actual forwarding
    lookupConflictList[i] = 0;
    if (entries[i].valid && entries[i].addrAvail &&
        entries[i].addr == IN_uopLd.addr[31:2] && 
        ($signed(entries[i].sqN - IN_uopLd.sqN) < 0 || entries[i].ready) &&
        !`IS_MMIO_PMA_W(entries[i].addr)
    ) begin
        
        if (entries[i].loaded) begin
            
            for (integer j = 0; j < 4; j=j+1)
                if (entries[i].wmask[j])
                    lookupDataIter[i][j*8 +: 8] = entries[i].data[j*8 +: 8];
                
            lookupMaskIter[i] = lookupMaskIter[i] | entries[i].wmask;
        end
        else if ((entries[i].wmask & readMask) != 0) lookupConflictList[i] = 1;
    end
end
endgenerate


assign OUT_done = 
    (!entries[0].valid || (!entries[0].ready && !($signed(IN_curSqN - entries[0].sqN) > 0))) && 
    evictedIn == 0 &&
    !IN_stallSt;

// Do not re-order stores before stores at the same address; and do not re-order MMIO stores.
reg allowDequeue;
always_comb begin
    allowDequeue = 1;
    
    // When a store cache miss occurs, collisions with any issued ops
    // are handled by the LSU. We have to make sure not to issue any
    // conflicting new ops though.
    for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
        if (evicted[i].s.valid &&

            (!evicted[i].issued || 
                // Forward negative store acks
                (IN_stAck.valid && IN_stAck.fail && IN_stAck.id == evicted[i].id) ||
                (stAck_r.valid && stAck_r.fail && stAck_r.id == evicted[i].id)) &&

            ((evicted[i].s.addr == entries[0].addr) || (`IS_MMIO_PMA_W(evicted[i].s.addr) && `IS_MMIO_PMA_W(entries[0].addr))))
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
        if (stAck_r.valid && evicted[i].s.valid && evicted[i].id == stAck_r.id) begin
            assert(!stAckIdxValid);
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
        if (entries[i].valid && !entries[i].avail) begin
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

// Register File Read
reg[$clog2(NUM_ENTRIES)-1:0] loadIndex;
reg loadValid;
always_comb begin
    loadIndex = loadBaseIndex[$clog2(NUM_ENTRIES)-1:0];
    OUT_RF_raddr = '0;
    loadValid = 0;

    if (entries[loadIndex].valid && !entries[loadIndex].loaded && entries[loadIndex].avail && entries[loadIndex].addrAvail) begin
        OUT_RF_raddr = entries[loadIndex].data.m.tag[$bits(Tag)-2:0];
        loadValid = 1;
    end
end
reg[31:0] loadData;
always_comb begin
    reg[31:0] rawLoadData = 'x;
    loadData = 'x;
    rawLoadData = IN_RF_rdata;
    // since we're deconstructing it anyways,
    // we may want to store offset + size instead of wmask

    case (entries[loadIndex].wmask)
        4'b1111: loadData = rawLoadData;
        4'b0001: loadData[7:0] = rawLoadData[7:0];
        4'b0010: loadData[15:8] = rawLoadData[7:0];
        4'b0100: loadData[23:16] = rawLoadData[7:0];
        4'b1000: loadData[31:24] = rawLoadData[7:0];
        4'b0011: loadData[15:0] = rawLoadData[15:0];
        4'b1100: loadData[31:16] = rawLoadData[15:0];
        default: ;
    endcase
end

// Dequeue/Enqueue
reg flushing;
assign OUT_flush = flushing;
always_ff@(posedge clk) begin

    OUT_fwd <= 'x;
    OUT_fwd.valid <= 0;

    if (rst) begin
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        
        for (integer i = 0; i < NUM_EVICTED; i=i+1)
            evicted[i].s.valid <= 0;
        
        evictedIn <= 0;
        
        baseIndex = 0;
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        OUT_empty <= 1;
        OUT_uopSt.valid <= 0;
        flushing <= 0;
        evictedUsedIds <= 0;
        loadBaseIndex <= 0;
    end
    
    else begin
        reg doingEnqueue = 0;
        reg doingDequeue = 0;
        reg[$clog2(NUM_EVICTED):0] nextEvictedIn = evictedIn;
        reg[$clog2(NUM_ENTRIES):0] nextloadBaseIndex = loadBaseIndex;

        if (!IN_stallSt)
            OUT_uopSt.valid <= 0;
        
        // Set entries of committed instructions to ready
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            if ($signed(IN_curSqN - entries[i].sqN) > 0) begin
                entries[i].ready <= 1;
            end
        end
        
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
                evicted[NUM_EVICTED-1].s.valid <= 0;
                nextEvictedIn = nextEvictedIn - 1;
                evictedUsedIds[stAck_r.id] <= 0;
            end
            else
                evicted[stAckIdx].issued <= 0;
        end
        
        // Dequeue
        if (!IN_stallSt) begin
            reg[$clog2(NUM_ENTRIES)-1:0] idx = baseIndex[$clog2(NUM_ENTRIES)-1:0];
            // Try storing new op
            if (entries[idx].valid && !IN_branch.taken && 
                entries[idx].ready && nextEvictedIn < NUM_EVICTED &&
                entries[idx].loaded && allowDequeue &&
                entries[idx].addrAvail
            ) begin
                assert(evictedNextIdValid);
                doingDequeue = 1;

                entries[idx].valid <= 0;        
                OUT_uopSt.valid <= 1;
                OUT_uopSt.id <= evictedNextId;
                OUT_uopSt.addr <= {entries[idx].addr, 2'b0};
                OUT_uopSt.data <= entries[idx].data;
                OUT_uopSt.wmask <= entries[idx].wmask;
                OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(entries[idx].addr);
                
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].s <= entries[idx];
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].issued <= 1;
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].id <= evictedNextId;
                nextEvictedIn = nextEvictedIn + 1;
                    
                evictedUsedIds[evictedNextId] <= 1;
                baseIndex = baseIndex + 1;
            end

            // Re-issue op that previously missed cache
            else if (evicted[0].s.valid && !evicted[0].issued) begin
                OUT_uopSt.valid <= 1;
                OUT_uopSt.id <= evicted[0].id;
                OUT_uopSt.addr <= {evicted[0].s.addr, 2'b0};
                OUT_uopSt.data <= evicted[0].s.data;
                OUT_uopSt.wmask <= evicted[0].s.wmask;
                OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(evicted[0].s.addr);
                evicted[0].issued <= 1;
            end
        end
        
        // Set Availability
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (entries[i].valid && dataAvail[i])
                entries[i].avail <= 1;
        end

        // Write Loaded Data
        if (loadValid) begin
            reg[$clog2(NUM_ENTRIES)-1:0] idx = loadIndex;
            entries[idx].avail <= 1;
            entries[idx].loaded <= 1;
            entries[idx].data <= loadData;
            
            if (nextloadBaseIndex[$clog2(NUM_ENTRIES)-1:0] == loadIndex)
                nextloadBaseIndex = nextloadBaseIndex + 1;
        end
        else if (entries[loadIndex].valid && entries[loadIndex].loaded)
            nextloadBaseIndex = nextloadBaseIndex + 1;

        // Invalidate
        if (IN_branch.taken) begin
            reg[$clog2(NUM_ENTRIES):0] highestValidIdx = 0;

            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ($signed(entries[i].sqN - IN_branch.sqN) > 0 && !entries[i].ready) begin
                    entries[i] <= 'x;
                    entries[i].valid <= 0;
                end
                else if (entries[i].valid) highestValidIdx = i[$clog2(NUM_ENTRIES):0];
            end
            
            if (IN_branch.flush)
                baseIndex = IN_branch.storeSqN + 1;
            
            // TODO: set this to last known valid index instead of base index
            nextloadBaseIndex = baseIndex[$clog2(NUM_ENTRIES):0];
            flushing <= IN_branch.flush;
        end
    
        // Enqueue
        if (IN_uopSt.valid && (!IN_branch.taken || $signed(IN_uopSt.sqN - IN_branch.sqN) <= 0)) begin
            reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uopSt.storeSqN[$clog2(NUM_ENTRIES)-1:0];
            assert(IN_uopSt.storeSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1);
            assert(entries[index].valid);
            entries[index].addr <= IN_uopSt.addr[31:2];
            entries[index].wmask <= IN_uopSt.wmask;
            entries[index].addrAvail <= 1;

            if (IN_uopSt.exception != AGU_NO_EXCEPTION)
                entries[index].wmask <= 0;

            if (IN_uopSt.wmask == 0) begin
                entries[index].loaded <= 1;
                entries[index].avail <= 1;
            end
            doingEnqueue = 1;
        end

        // Enqueue
        for (integer i = 0; i < WIDTH_RN; i=i+1)
            if (IN_rnUOp[i].valid && (!IN_branch.taken || $signed(IN_rnUOp[i].sqN - IN_branch.sqN) <= 0) &&
                (IN_rnUOp[i].fu == FU_ST || IN_rnUOp[i].fu == FU_ATOMIC)) begin
                
                reg[$clog2(NUM_ENTRIES)-1:0] index = IN_rnUOp[i].storeSqN[$clog2(NUM_ENTRIES)-1:0];
                assert(IN_rnUOp[i].storeSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1);
                
                entries[index].data <= 'x;
                entries[index].wmask <= 'x;
                entries[index].addr <= 0;

                entries[index].valid <= 1;
                entries[index].ready <= 0;
                entries[index].loaded <= 0;
                entries[index].avail <= IN_rnUOp[i].availB;

                for (integer j = 0; j < RESULT_BUS_COUNT; j=j+1)
                    if (IN_resultUOp[j].valid && !IN_resultUOp[j].tagDst[6] && IN_rnUOp[i].tagB == IN_resultUOp[j].tagDst)
                        entries[index].avail <= 1;

                entries[index].addrAvail <= 0;

                entries[index].data.m.tag <= IN_rnUOp[i].tagB;
                entries[index].sqN <= IN_rnUOp[i].sqN;

                if (IN_rnUOp[i].tagB[6]) begin
                    entries[index].loaded <= 1;
                    entries[index].avail <= 1;
                    entries[index].data <= {{26{IN_rnUOp[i].tagB[5]}}, IN_rnUOp[i].tagB[5:0]};
                end
                doingEnqueue = 1;
            end

        OUT_empty <= empty && !doingEnqueue;
        if (OUT_empty) flushing <= 0;
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        
        if (IN_uopLd.valid) begin
            OUT_fwd.valid <= 1;
            OUT_fwd.data <= lookupData;
            OUT_fwd.mask <= lookupMask;
            OUT_fwd.conflict <= lookupConflict;
        end

        evictedIn <= nextEvictedIn;
        loadBaseIndex <= nextloadBaseIndex;
    end
end
endmodule
