module LoadBuffer
#(
    parameter NUM_PORTS=2,
    parameter NUM_ENTRIES=`LB_SIZE
)
(
    input wire clk,
    input wire rst,
    
    input SqN IN_comLoadSqN,
    input SqN IN_comSqN,
    
    input wire IN_stall,
    input AGU_UOp IN_uopLd,
    input AGU_UOp IN_uopSt,
    
    input LD_Ack IN_ldAck,
    input wire IN_SQ_done,

    output LD_UOp OUT_uopAGULd,
    output LD_UOp OUT_uopLd,
    
    input BranchProv IN_branch,
    output BranchProv OUT_branch,
    
    output SqN OUT_maxLoadSqN
);

localparam TAG_SIZE = $bits(SqN) - $clog2(NUM_ENTRIES);

typedef struct packed
{
    SqN sqN;
    Tag tagDst;
    logic[TAG_SIZE-1:0] highLdSqN;
    logic[1:0] size;
    logic[31:0] addr;
    logic signExtend;
    logic doNotCommit; // could encode doNotCommit as size == 3
    
    logic nonSpec;
    logic issued;
    logic valid;
} LBEntry;

LBEntry entries[NUM_ENTRIES-1:0];

SqN baseIndex = IN_comLoadSqN + 1;
SqN lastBaseIndex;
wire[$clog2(NUM_ENTRIES)-1:0] deqIndex = baseIndex[$clog2(NUM_ENTRIES)-1:0];

LD_UOp lateLoadUOp;
reg issueLateLoad;
reg delayLoad;
reg nonSpeculative;
always_comb begin
    OUT_uopAGULd = 'x;
    OUT_uopAGULd.valid = 0;
    OUT_uopLd = 'x;
    OUT_uopLd.valid = 0;
    
    issueLateLoad = 0;
    nonSpeculative = IN_uopLd.valid && `IS_MMIO_PMA(IN_uopLd.addr) && IN_uopLd.exception == AGU_NO_EXCEPTION;
    delayLoad = nonSpeculative;
    
    // If it needs forwarding from current cycle's store, we also delay the load.
    if (IN_uopLd.valid && $signed(IN_uopSt.loadSqN - IN_uopLd.loadSqN) <= 0 &&
        IN_uopSt.valid &&
        (!IN_uopSt.doNotCommit || IN_uopSt.loadSqN != IN_uopLd.loadSqN) &&
        IN_uopLd.exception == AGU_NO_EXCEPTION &&
        IN_uopLd.addr[31:2] == IN_uopSt.addr[31:2] &&
            (IN_uopSt.size == 2 ||
            (IN_uopSt.size == 1 && (IN_uopLd.size > 1 || IN_uopLd.addr[1] == IN_uopSt.addr[1])) ||
            (IN_uopSt.size == 0 && (IN_uopLd.size > 0 || IN_uopLd.addr[1:0] == IN_uopSt.addr[1:0])))
        )
        delayLoad = 1;
    
    if (!delayLoad) begin
        OUT_uopAGULd.addr = IN_uopLd.addr; 
        OUT_uopAGULd.signExtend = IN_uopLd.signExtend; 
        OUT_uopAGULd.size = IN_uopLd.size; 
        OUT_uopAGULd.loadSqN = IN_uopLd.loadSqN; 
        OUT_uopAGULd.tagDst = IN_uopLd.tagDst; 
        OUT_uopAGULd.sqN = IN_uopLd.sqN; 
        OUT_uopAGULd.doNotCommit = IN_uopLd.doNotCommit; 
        OUT_uopAGULd.external = 0;
        OUT_uopAGULd.exception = IN_uopLd.exception; 
        OUT_uopAGULd.isMMIO = `IS_MMIO_PMA(IN_uopLd.addr); 
        OUT_uopAGULd.valid = IN_uopLd.valid; 
    end
    
    OUT_uopLd = lateLoadUOp;
end

// For every store, check if we previously speculatively loaded from the address written to
// (if so, flush pipeline)
logic storeIsConflict;
always_comb begin
    storeIsConflict = 0;
    
    // The order we check loads here does not matter, as we reset all the way back to the store on collision.
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].valid && entries[i].issued &&
            $signed(IN_uopSt.loadSqN - {entries[i].highLdSqN, i[$clog2(NUM_ENTRIES)-1:0]}) <= 0 &&
            (!IN_uopSt.doNotCommit || IN_uopSt.loadSqN != {entries[i].highLdSqN, i[$clog2(NUM_ENTRIES)-1:0]}) &&
            entries[i].addr[31:2] == IN_uopSt.addr[31:2] &&
                (IN_uopSt.size == 2 ||
                (IN_uopSt.size == 1 && (entries[i].size > 1 || entries[i].addr[1] == IN_uopSt.addr[1])) ||
                (IN_uopSt.size == 0 && (entries[i].size > 0 || entries[i].addr[1:0] == IN_uopSt.addr[1:0])))
            ) begin
            storeIsConflict = 1;
        end
    end
end

// Select late load to issue
logic[$clog2(NUM_ENTRIES)-1:0] issueIdx;
logic issueIdxValid;
always_comb begin
    logic[NUM_ENTRIES-1:0] issueCandidates = 0;
    issueIdx = 'x;
    issueIdxValid = 0;
    
    // Out-of-order late issue (regular loads)
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        issueCandidates[i] =
            entries[i].valid && !entries[i].issued && !entries[i].nonSpec;
    end
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        logic[$clog2(NUM_ENTRIES)-1:0] idx = i[$clog2(NUM_ENTRIES)-1:0] + deqIndex;
        if (issueCandidates[idx] && !issueIdxValid) begin
            issueIdxValid = 1;
            issueIdx = idx[$clog2(NUM_ENTRIES)-1:0];
        end
    end

    // In-order late issue (MMIO)
    if (entries[deqIndex].valid && !entries[deqIndex].issued &&
        (!entries[deqIndex].nonSpec || (IN_comSqN == entries[deqIndex].sqN && IN_SQ_done))
    ) begin
        // Overwrite. This load is in-order, so it always has top priority.
        issueIdxValid = 1;
        issueIdx = deqIndex;
    end
end

// Circular Logic for range-based invalidation
// verilator lint_off UNOPTFLAT
reg[NUM_ENTRIES-1:0] invalMask;
generate
for (genvar i = 0; i < NUM_ENTRIES; i=i+1)
always_comb begin
    integer prev = ((i-1) >= 0) ? (i-1) : (NUM_ENTRIES-1);

    // We use range invalidation on mispredict to remove incorrectly speculated loads,
    // and on regular commit to remove correct and committed loads.
    SqN invalSqN = IN_branch.taken ? IN_branch.loadSqN : lastBaseIndex;
    
    // invalidate from branch sqn (incl) to baseIndex (excl)
    if (IN_branch.taken) begin
        if (invalSqN[$clog2(NUM_ENTRIES)-1:0] == i[$clog2(NUM_ENTRIES)-1:0])
            invalMask[i] = 1;
        else if (baseIndex[$clog2(NUM_ENTRIES)-1:0] == i[$clog2(NUM_ENTRIES)-1:0])
            invalMask[i] = 0;
        else
            invalMask[i] = invalMask[prev];
    end
    else begin
        if (baseIndex[$clog2(NUM_ENTRIES)-1:0] == i[$clog2(NUM_ENTRIES)-1:0])
            invalMask[i] = 0;
        else if (invalSqN[$clog2(NUM_ENTRIES)-1:0] == i[$clog2(NUM_ENTRIES)-1:0])
            invalMask[i] = 1;
        else
            invalMask[i] = invalMask[prev];
    end
end
endgenerate
// verilator lint_on UNOPTFLAT

always_ff@(posedge clk) begin
    
    OUT_branch <= 'x;
    OUT_branch.taken <= 0;
    lastBaseIndex <= baseIndex;

    if (rst) begin
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        lateLoadUOp <= 'x;
        lateLoadUOp.valid <= 0;
        lastBaseIndex <= 0;
    end
    else begin
        if (!IN_stall) begin
            lateLoadUOp <= 'x;
            lateLoadUOp.valid <= 0;
        end
        
        // Process negative load acks
        if (IN_ldAck.valid && IN_ldAck.fail && !IN_ldAck.external) begin
            reg[$clog2(NUM_ENTRIES)-1:0] index = IN_ldAck.loadSqN[$clog2(NUM_ENTRIES)-1:0];
            entries[index].issued <= 0;
        end
        

        if (IN_branch.taken) begin
            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if (invalMask[i] || IN_branch.flush) begin
                    entries[i] <= 'x;
                    entries[i].valid <= 0;
                end
            end

            if ($signed(lateLoadUOp.sqN - IN_branch.sqN) > 0 || IN_branch.flush) begin
                lateLoadUOp <= 'x;
                lateLoadUOp.valid <= 0;
            end
        end
        else begin
            // Issue Late Loads
            // We do not have the same problem as below with multiple commits here, 
            // as the ROB can't commit beyond the load we issue with this,
            // and will need more than a cycle after this runs to commit anything again.
            if (!lateLoadUOp.valid && issueIdxValid) begin
                entries[issueIdx].issued <= 1;

                lateLoadUOp.addr <= entries[issueIdx].addr;
                lateLoadUOp.signExtend <= entries[issueIdx].signExtend;
                lateLoadUOp.size <= entries[issueIdx].size;
                lateLoadUOp.loadSqN <= {entries[issueIdx].highLdSqN, issueIdx};
                lateLoadUOp.tagDst <= entries[issueIdx].tagDst;
                lateLoadUOp.sqN <= entries[issueIdx].sqN;
                lateLoadUOp.doNotCommit <= entries[issueIdx].doNotCommit;
                lateLoadUOp.external <= 0;
                lateLoadUOp.exception <= AGU_NO_EXCEPTION;
                lateLoadUOp.isMMIO <= `IS_MMIO_PMA(entries[issueIdx].addr);
                lateLoadUOp.valid <= 1;
            end
            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if (invalMask[i]) begin
                    entries[i] <= 'x;
                    entries[i].valid <= 0;
                end
            end
        end

        // Insert new entries, check stores
        if (IN_uopLd.valid && (!IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)) begin
            
            reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uopLd.loadSqN[$clog2(NUM_ENTRIES)-1:0];
            entries[index].sqN <= IN_uopLd.sqN;
            entries[index].tagDst <= IN_uopLd.tagDst;
            entries[index].signExtend <= IN_uopLd.signExtend;
            entries[index].addr <= IN_uopLd.addr;
            entries[index].size <= IN_uopLd.size;
            entries[index].doNotCommit <= IN_uopLd.doNotCommit;
            entries[index].highLdSqN <= IN_uopLd.loadSqN[$bits(SqN)-1:$clog2(NUM_ENTRIES)];
            entries[index].issued <= !delayLoad;
            entries[index].nonSpec <= nonSpeculative;
            entries[index].valid <= 1;
        end
        
        if (IN_uopSt.valid && (!IN_branch.taken || $signed(IN_uopSt.sqN - IN_branch.sqN) <= 0)) begin
            if (storeIsConflict) begin
                // We reset back to the op after the store when a load collision occurs, even though you only need to
                // go back to the offending load. This way we don't need to keep a snapshot of IFetch state for every load
                // in the buffer, we just use the store's snapshot.
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= IN_uopSt.pc + (IN_uopSt.compressed ? 2 : 4);
                OUT_branch.sqN <= IN_uopSt.sqN;
                // TODO: dedicated field for atomic
                OUT_branch.loadSqN <= IN_uopSt.loadSqN + (IN_uopSt.doNotCommit ? 1 : 0);
                OUT_branch.storeSqN <= IN_uopSt.storeSqN;
                OUT_branch.fetchID <= IN_uopSt.fetchID;
                OUT_branch.flush <= 0;
                OUT_branch.histAct <= HIST_NONE;
                OUT_branch.retAct <= RET_NONE;
            end
        end
        
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
    end

end

endmodule
