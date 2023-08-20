typedef struct packed
{
    logic valid;
    logic ready;
    SqN sqN;
    logic[29:0] addr;
    logic[31:0] data;
    // wmask == 0 is escape sequence for special operations
    logic[3:0] wmask;
} SQEntry;

module StoreQueue
#(
    parameter NUM_ENTRIES=`SQ_SIZE,
    parameter NUM_EVICTED=4
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
    
    input SqN IN_curSqN,
    
    input BranchProv IN_branch,
    
    output ST_UOp OUT_uopSt,
    output StFwdResult OUT_fwd,
    
    input ST_Ack IN_stAck,
    
    output wire OUT_flush,
    output SqN OUT_maxStoreSqN
);


SQEntry entries[NUM_ENTRIES-1:0];
SqN baseIndex;

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

reg[3:0] lookupMask;
reg[31:0] lookupData;
always_comb begin
    // Store queue lookup
    
    // Bytes that are not read by this op are set to available in the lookup mask
    // (could also do this in LSU)
    case (IN_uopLd.size)
        0: lookupMask = ~(4'b1 << IN_uopLd.addr[1:0]);
        1: lookupMask = ~((IN_uopLd.addr[1:0] == 2) ? 4'b1100 : 4'b0011);
        default: lookupMask = 0;
    endcase
    
    lookupData = 32'bx;
    
    for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
        if (evicted[i].s.valid && evicted[i].s.addr == IN_uopLd.addr[31:2] && !`IS_MMIO_PMA_W(evicted[i].s.addr)) begin
            if (evicted[i].s.wmask[0])
                lookupData[7:0] = evicted[i].s.data[7:0];
            if (evicted[i].s.wmask[1])
                lookupData[15:8] = evicted[i].s.data[15:8];
            if (evicted[i].s.wmask[2])
                lookupData[23:16] = evicted[i].s.data[23:16];
            if (evicted[i].s.wmask[3])
                lookupData[31:24] = evicted[i].s.data[31:24];
                
            lookupMask = lookupMask | evicted[i].s.wmask;
        end
    end
    
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].valid && entries[i].addr == IN_uopLd.addr[31:2] && ($signed(entries[i].sqN - IN_uopLd.sqN) < 0 || entries[i].ready) && !`IS_MMIO_PMA_W(entries[i].addr)) begin
            // this is pretty neat!
            if (entries[i].wmask[0])
                lookupData[7:0] = entries[i].data[7:0];
            if (entries[i].wmask[1])
                lookupData[15:8] = entries[i].data[15:8];
            if (entries[i].wmask[2])
                lookupData[23:16] = entries[i].data[23:16];
            if (entries[i].wmask[3])
                lookupData[31:24] = entries[i].data[31:24];
                
            lookupMask = lookupMask | entries[i].wmask;
        end
    end
end

assign OUT_done = 
    (!entries[0].valid || (!entries[0].ready && !($signed(IN_curSqN - entries[0].sqN) > 0))) && 
    evictedIn == 0 &&
    !IN_stallSt;

// Do not re-order stores before stores at the same address; and do not re-order MMIO stores.
reg allowDequeue;
always_comb begin
    allowDequeue = 1;
    for (integer i = 0; i < NUM_EVICTED; i=i+1) begin
        if (evicted[i].s.valid && !evicted[i].issued &&
            ((evicted[i].s.addr == entries[0].addr) || (`IS_MMIO_PMA_W(evicted[i].s.addr) && `IS_MMIO_PMA_W(entries[0].addr))))
            allowDequeue = 0;
    end

    if (IN_stAck.valid && IN_stAck.fail)
        allowDequeue = 0;
    if (stAck_r.valid && stAck_r.fail)
        allowDequeue = 0;
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
    end
    
    else begin

        reg doingEnqueue = 0;
        reg[$clog2(NUM_EVICTED):0] nextEvictedIn = evictedIn;

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
            // Try storing new op
            if (entries[0].valid && !IN_branch.taken && 
                entries[0].ready && nextEvictedIn < NUM_EVICTED &&
                allowDequeue
            ) begin
                assert(evictedNextIdValid);

                entries[NUM_ENTRIES-1].valid <= 0;
            
                if (!flushing)
                    baseIndex = baseIndex + 1;
                
                OUT_uopSt.valid <= 1;
                OUT_uopSt.id <= evictedNextId;
                OUT_uopSt.addr <= {entries[0].addr, 2'b0};
                OUT_uopSt.data <= entries[0].data;
                OUT_uopSt.wmask <= entries[0].wmask;
                OUT_uopSt.isMMIO <= `IS_MMIO_PMA_W(entries[0].addr);
                
                for (integer i = 1; i < NUM_ENTRIES; i=i+1) begin
                    entries[i-1] <= entries[i];
                    if ($signed(IN_curSqN - entries[i].sqN) > 0)
                        entries[i-1].ready <= 1;
                end
                
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].s <= entries[0];
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].issued <= 1;
                evicted[nextEvictedIn[$clog2(NUM_EVICTED)-1:0]].id <= evictedNextId;
                nextEvictedIn = nextEvictedIn + 1;
                    
                evictedUsedIds[evictedNextId] <= 1;
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
        
        // Invalidate
        if (IN_branch.taken) begin
            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ($signed(entries[i].sqN - IN_branch.sqN) > 0 && !entries[i].ready)
                    entries[i].valid <= 0;
            end
            
            if (IN_branch.flush)
                baseIndex = IN_branch.storeSqN + 1;
                
            flushing <= IN_branch.flush;
        end
    
        // Enqueue
        if (IN_uopSt.valid && (!IN_branch.taken || $signed(IN_uopSt.sqN - IN_branch.sqN) <= 0) && IN_uopSt.exception == AGU_NO_EXCEPTION) begin
            reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uopSt.storeSqN[$clog2(NUM_ENTRIES)-1:0] - baseIndex[$clog2(NUM_ENTRIES)-1:0];
            assert(IN_uopSt.storeSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1);
            entries[index].valid <= 1;
            entries[index].ready <= 0;
            entries[index].sqN <= IN_uopSt.sqN;
            entries[index].addr <= IN_uopSt.addr[31:2];
            entries[index].data <= IN_uopSt.data;
            entries[index].wmask <= IN_uopSt.wmask;
            doingEnqueue = 1;
        end

        OUT_empty <= empty && !doingEnqueue;
        if (OUT_empty) flushing <= 0;
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        
        if (IN_uopLd.valid) begin
            OUT_fwd.valid <= 1;
            OUT_fwd.data <= lookupData;
            OUT_fwd.mask <= lookupMask;
        end

        evictedIn <= nextEvictedIn;
    end
end


endmodule
