typedef struct packed
{
    bit valid;
    bit ready;
    SqN sqN;
    bit[29:0] addr;
    bit[31:0] data;
    // wmask == 0 is escape sequence for special operations
    bit[3:0] wmask;
} SQEntry;

module StoreQueue
#(
    parameter NUM_ENTRIES=`SQ_SIZE
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
    
    output reg[31:0] OUT_lookupData,
    output reg[3:0] OUT_lookupMask,
    
    output wire OUT_flush,
    output SqN OUT_maxStoreSqN
    
);


SQEntry entries[NUM_ENTRIES-1:0];
SqN baseIndex;

reg didCSRwrite;

reg empty;
always_comb begin
    empty = 1;
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].valid)
            empty = 0;
    end
end

SQEntry evicted[1:0];

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
    
    for (integer i = 0; i < 2; i=i+1) begin
        if (/*IN_uopLd.isLoad && */evicted[i].valid && evicted[i].addr == IN_uopLd.addr[31:2] && !`IS_MMIO_PMA_W(evicted[i].addr)) begin
            if (evicted[i].wmask[0])
                lookupData[7:0] = evicted[i].data[7:0];
            if (evicted[i].wmask[1])
                lookupData[15:8] = evicted[i].data[15:8];
            if (evicted[i].wmask[2])
                lookupData[23:16] = evicted[i].data[23:16];
            if (evicted[i].wmask[3])
                lookupData[31:24] = evicted[i].data[31:24];
                
            lookupMask = lookupMask | evicted[i].wmask;
        end
    end
    
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (/*IN_uopLd.isLoad && */entries[i].valid && entries[i].addr == IN_uopLd.addr[31:2] && ($signed(entries[i].sqN - IN_uopLd.sqN) < 0 || entries[i].ready) && !`IS_MMIO_PMA_W(entries[i].addr)) begin
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

assign OUT_done = (!entries[0].valid || (!entries[0].ready && !($signed(IN_curSqN - entries[0].sqN) > 0))) && !IN_stallSt;

reg flushing;
assign OUT_flush = flushing;
reg doingEnqueue;
always_ff@(posedge clk) begin
    didCSRwrite <= 0;
    doingEnqueue = 0;
    if (!IN_stallLd) begin
        OUT_lookupMask <= 'x;
        OUT_lookupData <= 'x;
    end

    if (rst) begin
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        
        evicted[0].valid <= 0;
        evicted[1].valid <= 0;
        
        baseIndex = 0;
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        OUT_empty <= 1;
        OUT_uopSt.valid <= 0;
        flushing <= 0;
    end
    
    else begin

        // Set entries of committed instructions to ready
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            if ($signed(IN_curSqN - entries[i].sqN) > 0) begin
                entries[i].ready <= 1;
            end
        end
        
        // Dequeue
        if (!IN_stallSt && entries[0].valid && !IN_branch.taken && entries[0].ready &&
            // Don't issue Memory Mapped IO ops while IO is not ready
            (!(didCSRwrite) || `IS_MMIO_PMA_W(entries[0].addr))) begin
                
            entries[NUM_ENTRIES-1].valid <= 0;
            
            didCSRwrite <= `IS_MMIO_PMA_W(entries[0].addr);
            if (!flushing)
                baseIndex = baseIndex + 1;
            
            OUT_uopSt.valid <= 1;
            OUT_uopSt.addr <= {entries[0].addr, 2'b0};
            OUT_uopSt.data <= entries[0].data;
            OUT_uopSt.wmask <= entries[0].wmask;
            OUT_uopSt.isMMIO <= 'x;
            
            for (integer i = 1; i < NUM_ENTRIES; i=i+1) begin
                entries[i-1] <= entries[i];
                if ($signed(IN_curSqN - entries[i].sqN) > 0)
                    entries[i-1].ready <= 1;
            end

            evicted[1] <= entries[0];
            evicted[0] <= evicted[1];
        end
        else if (!IN_stallSt) OUT_uopSt.valid <= 0;
        
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
        
        if (flushing)
            for (integer i = 0; i < 2; i=i+1)
                evicted[i].valid <= 0;

        OUT_empty <= empty && !doingEnqueue;
        if (OUT_empty) flushing <= 0;
        OUT_maxStoreSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        
        if (!IN_stallLd && IN_uopLd.valid) begin
            OUT_lookupData <= lookupData;
            OUT_lookupMask <= lookupMask;
        end
    end
    
end


endmodule
