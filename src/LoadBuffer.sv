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
    
    input wire IN_stall[1:0],
    input AGU_UOp IN_uop[`NUM_AGUS-1:0],
    
    input LD_Ack IN_ldAck[`NUM_AGUS-1:0],
    input wire IN_SQ_done,

    output LD_UOp OUT_uopAGULd[`NUM_AGUS-1:0],
    output LD_UOp OUT_uopLd[`NUM_AGUS-1:0],
    
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

SqN baseIndex = IN_comLoadSqN;
SqN lastBaseIndex;
wire[$clog2(NUM_ENTRIES)-1:0] deqIndex = baseIndex[$clog2(NUM_ENTRIES)-1:0];

LD_UOp lateLoadUOp;
reg issueLateLoad[`NUM_AGUS-1:0];
reg delayLoad[`NUM_AGUS-1:0];
reg nonSpeculative[`NUM_AGUS-1:0];
always_comb begin
    for (integer h = 0; h < `NUM_AGUS; h=h+1) begin
        OUT_uopAGULd[h] = 'x;
        OUT_uopAGULd[h].valid = 0;
        OUT_uopLd[h] = 'x;
        OUT_uopLd[h].valid = 0;
        
        issueLateLoad[h] = 0;
        nonSpeculative[h] = IN_uop[h].valid && `IS_MMIO_PMA(IN_uop[h].addr) && IN_uop[h].exception == AGU_NO_EXCEPTION;
        delayLoad[h] = nonSpeculative[h];
        
        // If it needs forwarding from current cycle's store, we also delay the load.
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            if (i != h) begin
                if (IN_uop[h].valid && $signed(IN_uop[i].loadSqN - IN_uop[h].loadSqN) <= 0 &&
                    IN_uop[i].valid && !IN_uop[i].isLoad &&
                    (!IN_uop[i].doNotCommit || IN_uop[i].loadSqN != IN_uop[h].loadSqN) &&
                    IN_uop[h].exception == AGU_NO_EXCEPTION &&
                    IN_uop[h].addr[31:2] == IN_uop[i].addr[31:2] &&
                        (IN_uop[i].size == 2 ||
                        (IN_uop[i].size == 1 && (IN_uop[h].size > 1 || IN_uop[h].addr[1] == IN_uop[i].addr[1])) ||
                        (IN_uop[i].size == 0 && (IN_uop[h].size > 0 || IN_uop[h].addr[1:0] == IN_uop[i].addr[1:0])))
                    )
                    delayLoad[h] = 1;
            end
        end
        
        if (!delayLoad[h]) begin
            OUT_uopAGULd[h].addr = IN_uop[h].addr; 
            OUT_uopAGULd[h].signExtend = IN_uop[h].signExtend; 
            OUT_uopAGULd[h].size = IN_uop[h].size; 
            OUT_uopAGULd[h].loadSqN = IN_uop[h].loadSqN; 
            OUT_uopAGULd[h].tagDst = IN_uop[h].tagDst; 
            OUT_uopAGULd[h].sqN = IN_uop[h].sqN; 
            OUT_uopAGULd[h].doNotCommit = IN_uop[h].doNotCommit; 
            OUT_uopAGULd[h].external = 0;
            OUT_uopAGULd[h].exception = IN_uop[h].exception; 
            OUT_uopAGULd[h].isMMIO = `IS_MMIO_PMA(IN_uop[h].addr); 
            OUT_uopAGULd[h].valid = IN_uop[h].valid; 
        end
        
        if (h == 0) OUT_uopLd[h] = lateLoadUOp;
    end
end

// For every store, check if we previously speculatively loaded from the address written to
// (if so, flush pipeline)
logic storeIsConflict[`NUM_AGUS-1:0];
always_comb begin
    for (integer h = 0; h < `NUM_AGUS; h=h+1) begin
        storeIsConflict[h] = 0;
        // The order we check loads here does not matter, as we reset all the way back to the store on collision.
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (entries[i].valid && entries[i].issued &&
                $signed(IN_uop[h].loadSqN - {entries[i].highLdSqN, i[$clog2(NUM_ENTRIES)-1:0]}) <= 0 &&
                (!IN_uop[h].doNotCommit || IN_uop[h].loadSqN != {entries[i].highLdSqN, i[$clog2(NUM_ENTRIES)-1:0]}) &&
                entries[i].addr[31:2] == IN_uop[h].addr[31:2] &&
                    (IN_uop[h].size == 2 ||
                    (IN_uop[h].size == 1 && (entries[i].size > 1 || entries[i].addr[1] == IN_uop[h].addr[1])) ||
                    (IN_uop[h].size == 0 && (entries[i].size > 0 || entries[i].addr[1:0] == IN_uop[h].addr[1:0])))
                ) begin
                storeIsConflict[h] = 1;
            end
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

wire SqN invalSqN = IN_branch.taken ? IN_branch.loadSqN : lastBaseIndex;
wire[NUM_ENTRIES-1:0] beginOneHot = (1 << invalSqN[$clog2(NUM_ENTRIES)-1:0]);
wire[NUM_ENTRIES-1:0] endOneHot = (1 << baseIndex[$clog2(NUM_ENTRIES)-1:0]);

reg[NUM_ENTRIES-1:0] invalMask;
always_comb begin
    reg active;
    if (IN_branch.taken)
        active = baseIndex[$clog2(NUM_ENTRIES)-1:0] <= invalSqN[$clog2(NUM_ENTRIES)-1:0];
    else
        active = baseIndex[$clog2(NUM_ENTRIES)-1:0] < invalSqN[$clog2(NUM_ENTRIES)-1:0];
        
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (IN_branch.taken) begin
            if (beginOneHot[i]) active = 1;
            else if (endOneHot[i]) active = 0;
        end
        else begin
            if (endOneHot[i]) active = 0;
            else if (beginOneHot[i]) active = 1;
        end
        invalMask[i] = active;
    end
end


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
        if (!IN_stall[0]) begin
            // fixme: currently late loads only on port 0 
            lateLoadUOp <= 'x;
            lateLoadUOp.valid <= 0;
        end
        
        // Process negative load acks
        for (integer i = 0; i < `NUM_AGUS; i=i+1)
            if (IN_ldAck[i].valid && IN_ldAck[i].fail && !IN_ldAck[i].external) begin
                reg[$clog2(NUM_ENTRIES)-1:0] index = IN_ldAck[i].loadSqN[$clog2(NUM_ENTRIES)-1:0];
                entries[index].issued <= 0;
            end
        

        if (IN_branch.taken) begin
            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ((invalMask[i] && !($signed(IN_branch.loadSqN - baseIndex) >= NUM_ENTRIES)) || IN_branch.flush) begin
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
        for (integer i = 0; i < `NUM_AGUS; i=i+1)
            if (IN_uop[i].valid && IN_uop[i].isLoad && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
                
                reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uop[i].loadSqN[$clog2(NUM_ENTRIES)-1:0];
                entries[index].sqN <= IN_uop[i].sqN;
                entries[index].tagDst <= IN_uop[i].tagDst;
                entries[index].signExtend <= IN_uop[i].signExtend;
                entries[index].addr <= IN_uop[i].addr;
                entries[index].size <= IN_uop[i].size;
                entries[index].doNotCommit <= IN_uop[i].doNotCommit;
                entries[index].highLdSqN <= IN_uop[i].loadSqN[$bits(SqN)-1:$clog2(NUM_ENTRIES)];
                entries[index].issued <= !delayLoad[i];
                entries[index].nonSpec <= nonSpeculative[i];
                entries[index].valid <= 1;
            end
        
        for (integer i = 0; i < `NUM_AGUS; i=i+1)
            if (IN_uop[i].valid && !IN_uop[i].isLoad && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
                if (storeIsConflict[i]) begin
                    // We reset back to the op after the store when a load collision occurs, even though you only need to
                    // go back to the offending load. This way we don't need to keep a snapshot of IFetch state for every load
                    // in the buffer, we just use the store's snapshot.
                    OUT_branch.taken <= 1;
                    OUT_branch.dstPC <= IN_uop[i].pc + (IN_uop[i].compressed ? 2 : 4);
                    OUT_branch.sqN <= IN_uop[i].sqN;
                    OUT_branch.loadSqN <= IN_uop[i].loadSqN + (IN_uop[i].doNotCommit ? 1 : 0);
                    OUT_branch.storeSqN <= IN_uop[i].storeSqN;
                    OUT_branch.fetchID <= IN_uop[i].fetchID;
                    OUT_branch.flush <= 0;
                    OUT_branch.histAct <= HIST_NONE;
                    OUT_branch.retAct <= RET_NONE;
                end
            end
        
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
    end

end

endmodule
