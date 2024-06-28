module LoadBuffer
#(
    parameter NUM_PORTS=2,
    parameter NUM_ENTRIES=`LB_SIZE
)
(
    input wire clk,
    input wire rst,

    input MemController_Res IN_memc,
    input MemController_Req IN_LSU_memc,
    
    input SqN IN_comLoadSqN,
    input SqN IN_comSqN,
    
    input wire IN_stall[`NUM_AGUS-1:0],
    input AGU_UOp IN_uop[`NUM_AGUS-1:0],
    
    input LD_Ack IN_ldAck[`NUM_AGUS-1:0],
    input wire IN_SQ_done,

    output LD_UOp OUT_uopAGULd[`NUM_AGUS-1:0],
    output LD_UOp OUT_uopLd[`NUM_AGUS-1:0],
    
    input BranchProv IN_branch,
    output BranchProv OUT_branch,
    
    output SqN OUT_maxLoadSqN,
    
    output ComLimit OUT_comLimit
);

localparam TAG_SIZE = $bits(SqN) - $clog2(NUM_ENTRIES);

typedef struct packed
{
    AGU_Exception exception;
    SqN sqN;
    Tag tagDst;
    logic[TAG_SIZE-1:0] highLdSqN;
    logic[1:0] size;
    logic[31:0] addr;
    logic signExtend;
    logic doNotCommit;
    logic nonSpec;
    logic noReIssue;
    logic issued;
    logic hasRsv; // also set if not valid
    logic valid;
} LBEntry;

typedef struct packed
{
    SqN sqN;
    logic[29:0] addr;
    logic valid;
} LoadRsv;

typedef struct packed
{
    logic[$clog2(NUM_ENTRIES)-1:0] idx;
    logic valid;
} IdxN;

LBEntry entries[NUM_ENTRIES-1:0];

wire SqN baseIndex = IN_comLoadSqN;
SqN lastBaseIndex;
wire[$clog2(NUM_ENTRIES)-1:0] deqIndex = baseIndex[$clog2(NUM_ENTRIES)-1:0];

LD_UOp lateLoadUOp[`NUM_AGUS-1:0];
reg delayLoad[`NUM_AGUS-1:0];
reg nonSpeculative[`NUM_AGUS-1:0];
reg doNotReIssue[`NUM_AGUS-1:0];
always_comb begin
    for (integer h = 0; h < `NUM_AGUS; h=h+1) begin
        OUT_uopAGULd[h] = 'x;
        OUT_uopAGULd[h].valid = 0;
        OUT_uopLd[h] = 'x;
        OUT_uopLd[h].valid = 0;

        doNotReIssue[h] = 0;
        for (integer i = 0; i < `AXI_NUM_TRANS; i=i+1)
            if (IN_memc.transfers[i].valid && 
                IN_memc.transfers[i].readAddr[31:`CLSIZE_E] == IN_uop[h].addr[31:`CLSIZE_E] &&
                IN_memc.transfers[i].progress < {1'b0, IN_uop[h].addr[`CLSIZE_E-1:2]} - {1'b0, IN_memc.transfers[i].readAddr[`CLSIZE_E-1:2]}
            ) begin
                doNotReIssue[h] = 1;
            end
        if ((IN_LSU_memc.cmd == MEMC_REPLACE || IN_LSU_memc.cmd == MEMC_CP_EXT_TO_CACHE) &&
            (IN_LSU_memc.readAddr[31:`CLSIZE_E] == IN_uop[h].addr[31:`CLSIZE_E])
        ) begin
            doNotReIssue[h] = 1;
        end
            
        
        nonSpeculative[h] = IN_uop[h].valid && `IS_MMIO_PMA(IN_uop[h].addr) && IN_uop[h].exception == AGU_NO_EXCEPTION;
        delayLoad[h] = doNotReIssue[h] || nonSpeculative[h] || IN_uop[h].earlyLoadFailed;
        
        // If it needs forwarding from current cycle's store, we also delay the load.
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            if (i != h) begin
                if (IN_uop[h].valid && IN_uop[h].isLoad && $signed(IN_uop[i].loadSqN - IN_uop[h].loadSqN) <= 0 &&
                    IN_uop[i].valid && IN_uop[i].isStore &&
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
            OUT_uopAGULd[h].data = 'x; 
            OUT_uopAGULd[h].dataValid = 0; 
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
        
        OUT_uopLd[h] = lateLoadUOp[h];
    end
end


logic[31:0] wAddrToMatch[`NUM_AGUS-1:0];
typedef enum logic[1:0] 
{
    STORE,
    LD_FWD,
    LD_NACK
} AddrCompareType;

AddrCompareType addrCompT[`NUM_AGUS-1:0];

always_comb begin
    for (integer h = 0; h < `NUM_AGUS; h=h+1) begin
        wAddrToMatch[h] = 'x;
        addrCompT[h] = STORE;

        if (IN_uop[h].valid && IN_uop[h].isStore) begin
            wAddrToMatch[h] = IN_uop[h].addr;
        end
        else if (IN_memc.ldDataFwd.valid) begin
            addrCompT[h] = LD_FWD;
            wAddrToMatch[h] = IN_memc.ldDataFwd.addr;
        end
        else if (IN_ldAck[h].valid) begin
            addrCompT[h] = LD_NACK;
            wAddrToMatch[h] = IN_ldAck[h].addr;
        end
    end
end

logic[NUM_ENTRIES-1:0] wAddrMatch[`NUM_AGUS-1:0];
always_comb begin
    for (integer h = 0; h < `NUM_AGUS; h=h+1) begin
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            wAddrMatch[h][i] = ((entries[i].valid && entries[i].addr[31:`CLSIZE_E] == wAddrToMatch[h][31:`CLSIZE_E]) &&
                                (addrCompT[h] != LD_FWD || 
                                    entries[i].addr[`CLSIZE_E-1:$clog2(`AXI_WIDTH/8)] == 
                                    wAddrToMatch[h][`CLSIZE_E-1:$clog2(`AXI_WIDTH/8)]) &&
                                (addrCompT[h] != STORE  || 
                                    entries[i].addr[`CLSIZE_E-1:2] == 
                                    wAddrToMatch[h][`CLSIZE_E-1:2])
                            );
        end
    end
end

logic[NUM_ENTRIES-1:0] isBefore[`NUM_AGUS-1:0];
always_comb begin
    for (integer h = 0; h < `NUM_AGUS; h=h+1)
        for (integer i = 0; i < NUM_ENTRIES; i=i+1)
            isBefore[h][i] = $signed(IN_uop[h].loadSqN - {entries[i].highLdSqN, i[$clog2(NUM_ENTRIES)-1:0]}) <= 0;
end

// For store-conditional, check if a reservation exists
logic storeHasRsv[`NUM_AGUS-1:0];
always_comb begin
    // Currently, SCs are issued non-speculatively, so we only have to check
    // the committed load reservation
    for (integer h = 0; h < `NUM_AGUS; h=h+1) begin
        storeHasRsv[h] = 
            IN_uop[h].isStore && IN_uop[h].isLrSc &&
            comRsv.valid && comRsv.addr == IN_uop[h].addr[31:2];
    end
end

// For every store, check if we previously speculatively loaded from the address written to
// (if so, flush pipeline)
logic storeIsConflict[`NUM_AGUS-1:0];
always_comb begin
    for (integer h = 0; h < `NUM_AGUS; h=h+1) begin
        storeIsConflict[h] = 0;
        // The order we check loads here does not matter as we reset all the way back to the store on collision.
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            if (wAddrMatch[h][i] && entries[i].issued && IN_uop[h].isStore && isBefore[h][i] &&
                (!IN_uop[h].doNotCommit || IN_uop[h].loadSqN != {entries[i].highLdSqN, i[$clog2(NUM_ENTRIES)-1:0]}) &&
                    (IN_uop[h].size == 2 ||
                    (IN_uop[h].size == 1 && (entries[i].size > 1 || entries[i].addr[1] == IN_uop[h].addr[1])) ||
                    (IN_uop[h].size == 0 && (entries[i].size > 0 || entries[i].addr[1:0] == IN_uop[h].addr[1:0])))
            ) begin
                storeIsConflict[h] = 1;
            end
        end
    end
end

typedef struct packed
{
    logic[$clog2(NUM_ENTRIES)-1:0] idx;
    logic isLdFwd;
    logic valid;
} LateIssue;

LateIssue ltIssue[`NUM_AGUS-1:0];
always_comb begin
    logic memcNotBusy = !IN_memc.transfers[0].valid;
    
   for (integer h = 0; h < `NUM_AGUS; h=h+1) begin
        
        logic[NUM_ENTRIES-1:0] issueCandidates = 0;

        ltIssue[h] = LateIssue'{valid: 0, default: 'x};
        // Out-of-order late ltIssue (regular loads)
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            issueCandidates[i] =
                entries[i].valid && (!entries[i].issued) && !entries[i].nonSpec && 
                    (!entries[i].noReIssue || (addrCompT[h] == LD_FWD && wAddrMatch[h][i]) || memcNotBusy);
        end

        for (integer i = 0; i < h; i=i+1) begin
            if (ltIssue[i].valid)
                issueCandidates[ltIssue[i].idx] = 0;
        end

        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            logic[$clog2(NUM_ENTRIES)-1:0] idx = i[$clog2(NUM_ENTRIES)-1:0] + deqIndex;
            logic isLdDataFwd = (addrCompT[h] == LD_FWD) && wAddrMatch[h][idx];
            if (issueCandidates[idx] && (!ltIssue[h].valid || isLdDataFwd)) begin
                ltIssue[h].isLdFwd = isLdDataFwd;
                ltIssue[h].valid = 1;
                ltIssue[h].idx = idx[$clog2(NUM_ENTRIES)-1:0];
            end
        end

        // In-order late ltIssue (MMIO)
        if (h == 0 &&
            entries[deqIndex].valid && !entries[deqIndex].issued && entries[deqIndex].nonSpec &&
            ((IN_comSqN == entries[deqIndex].sqN && IN_SQ_done))
        ) begin
            // Overwrite. This load is in-order, so it always has top priority.
            ltIssue[h].isLdFwd = 0;
            ltIssue[h].valid = 1;
            ltIssue[h].idx = deqIndex;
        end
    end
end

logic[2*NUM_ENTRIES-1:0] hasRsvOrInvalid;
always_comb begin
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        hasRsvOrInvalid[i] = entries[i].hasRsv;
        hasRsvOrInvalid[i+NUM_ENTRIES] = entries[i].hasRsv;
    end
    hasRsvOrInvalid &= {{NUM_ENTRIES{1'b0}}, {NUM_ENTRIES{1'b1}}} << baseIndex[$clog2(NUM_ENTRIES)-1:0];
end

IdxN loadRsv;
wire[$clog2(NUM_ENTRIES):0] PENC_idx;
wire PENC_valid;
PriorityEncoder#(2*NUM_ENTRIES) penc(hasRsvOrInvalid, {PENC_idx}, {PENC_valid});
always_comb begin
    loadRsv.idx = ($clog2(NUM_ENTRIES))'(PENC_idx);
    loadRsv.valid = PENC_valid;
    if (loadRsv.valid && !entries[loadRsv.idx].valid)
        loadRsv = IdxN'{valid: 0, default: 'x};
end


// Generate invalidation mask based on last cycle's and current baseIndex
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
    OUT_comLimit.sqN <= 'x;
    OUT_comLimit.valid <= 0;

    if (rst) ;
    else begin
        OUT_comLimit.valid <= loadRsv.valid;
        if (loadRsv.valid)
            OUT_comLimit.sqN <= {entries[loadRsv.idx].highLdSqN, loadRsv.idx};
    end
end


always_comb begin
    
    reg prevStoreConflict = 0;
    SqN prevStoreConflictSqN = 'x;

    OUT_branch = 'x;
    OUT_branch.taken = 0;

    for (integer i = 0; i < `NUM_AGUS; i=i+1)
        if (IN_uop[i].valid && IN_uop[i].isStore && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
            if ((storeIsConflict[i] || (IN_uop[i].isLrSc && !storeHasRsv[i])) && 
                (!prevStoreConflict || $signed(IN_uop[i].sqN - prevStoreConflictSqN) < 0)) begin
                // We reset back to the op after the store when a load collision occurs, even though you only need to
                // go back to the offending load. This way we don't need to keep a snapshot of IFetch state for every load
                // in the buffer, we just use the store's snapshot.
                OUT_branch.taken = 1;
                OUT_branch.dstPC = 'x;//IN_uop[i].pc + (IN_uop[i].compressed ? 2 : 4);
                OUT_branch.sqN = IN_uop[i].sqN;
                OUT_branch.loadSqN = IN_uop[i].loadSqN + ((IN_uop[i].isLoad && IN_uop[i].isStore) ? 1 : 0);
                OUT_branch.storeSqN = IN_uop[i].storeSqN;
                OUT_branch.fetchID = IN_uop[i].fetchID;
                OUT_branch.fetchOffs = IN_uop[i].fetchOffs;
                OUT_branch.flush = 0;
                OUT_branch.histAct = HIST_NONE;
                OUT_branch.retAct = RET_NONE;
                OUT_branch.isSCFail = 0;
                OUT_branch.tgtSpec = BR_TGT_NEXT;
                OUT_branch.cause = FLUSH_MEM_ORDER;
                
                // For failed SCs we also roll back the SC itself. The SC is then re-run as `li rd, 1`.
                // This saves as from needing a real register file write port for stores. Instead, all
                // of this can be handled in rename.
                if (IN_uop[i].isLrSc && !storeHasRsv[i]) begin
                    OUT_branch.dstPC = 'x;//IN_uop[i].pc;
                    OUT_branch.sqN = IN_uop[i].sqN - 1;
                    OUT_branch.storeSqN = IN_uop[i].storeSqN - 1;
                    OUT_branch.isSCFail = 1;
                    OUT_branch.tgtSpec = IN_uop[i].compressed ? BR_TGT_CUR16 : BR_TGT_CUR32;
                end

                prevStoreConflict = 1;
                prevStoreConflictSqN = IN_uop[i].sqN;

            end
        end
end

LoadRsv specRsv;
LoadRsv comRsv;
always_ff@(posedge clk) begin
    
    lastBaseIndex <= baseIndex;

    if (rst) begin
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i] <= LBEntry'{valid: 0, hasRsv: 1, default: 'x};
        end
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            lateLoadUOp[i] <= 'x;
            lateLoadUOp[i].valid <= 0;
        end

        lastBaseIndex <= 0;

        specRsv <= LoadRsv'{valid: 0, default: 'x};
        comRsv <= LoadRsv'{valid: 0, default: 'x};
    end
    else begin
        
        reg[`NUM_AGUS-1:0] lateLoadPassthru = 0;
        
        // Handle late load outputs
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            if (!IN_stall[i]) begin
                lateLoadUOp[i] <= 'x;
                lateLoadUOp[i].valid <= 0;
            end
            else if (lateLoadUOp[i].valid && IN_memc.ldDataFwd.valid &&
                     lateLoadUOp[i].addr[31:$clog2(`AXI_WIDTH/8)] == IN_memc.ldDataFwd.addr[31:$clog2(`AXI_WIDTH/8)]
            ) begin
                lateLoadUOp[i].dataValid <= 1;
                lateLoadUOp[i].data <= IN_memc.ldDataFwd.data[(lateLoadUOp[i].addr[$clog2(`AXI_WIDTH/8)-1:2])*32+:32];
            end
            else begin
                lateLoadUOp[i].dataValid <= 0;
                lateLoadUOp[i].data <= 'x;
            end
        end

        // Process negative load acks
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin

            if (addrCompT[i] == LD_NACK) begin
                for (integer j = 0; j < NUM_ENTRIES; j=j+1) begin
                    if (wAddrMatch[i][j]) entries[j].noReIssue <= 1;
                end
            end

            if (IN_ldAck[i].valid && IN_ldAck[i].fail && !IN_ldAck[i].external) begin
                reg[$clog2(NUM_ENTRIES)-1:0] index = IN_ldAck[i].loadSqN[$clog2(NUM_ENTRIES)-1:0];
                entries[index].issued <= 0;
                entries[index].noReIssue <= IN_ldAck[i].doNotReIssue;
            end
        end

        // Delete reservation on SC
        for (integer i = 0; i < `NUM_AGUS; i=i+1) begin
            if (IN_uop[i].valid && 
                (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0) &&
                IN_uop[i].isStore && IN_uop[i].isLrSc
            ) begin
                comRsv <= LoadRsv'{valid: 0, default: 'x};
            end
        end

        // Commit Load Reservations
        if (specRsv.valid && (!IN_branch.taken || $signed(specRsv.sqN - IN_branch.sqN) < 0) && 
            ($signed(specRsv.sqN - IN_comSqN) < 0)
        ) begin
            comRsv <= specRsv;
            specRsv <= LoadRsv'{valid: 0, default: 'x};
        end
        
        // Invalidate misspeculated state
        if (IN_branch.taken) begin
            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ((invalMask[i] && !($signed(IN_branch.loadSqN - baseIndex) >= NUM_ENTRIES)) || IN_branch.flush) begin
                    entries[i] <= LBEntry'{valid: 0, hasRsv: 1, default: 'x};
                end
            end
            
            for (integer i = 0; i < `NUM_AGUS; i=i+1)
                if ($signed(lateLoadUOp[i].sqN - IN_branch.sqN) > 0 || IN_branch.flush) begin
                    lateLoadUOp[i] <= 'x;
                    lateLoadUOp[i].valid <= 0;
                end

            if (specRsv.valid && $signed(specRsv.sqN - IN_branch.sqN) >= 0)
                specRsv <= LoadRsv'{valid: 0, default: 'x};
        end
        else begin
            // Issue Late Loads          
            for (integer i = 0; i < `NUM_AGUS; i=i+1) begin

                if (!lateLoadUOp[i].valid || !IN_stall[i] || ltIssue[i].isLdFwd) begin

                    if (IN_stall[i] && lateLoadUOp[i].valid)
                        entries[lateLoadUOp[i].loadSqN[$clog2(NUM_ENTRIES)-1:0]].issued <= 0;

                    // Issue non-speculative or cache missed loads, currently only on port 0.
                    if (ltIssue[i].valid) begin
                        LBEntry e = entries[ltIssue[i].idx];

                        entries[ltIssue[i].idx].issued <= 1;
                        lateLoadUOp[i].data <= ltIssue[i].isLdFwd ? (IN_memc.ldDataFwd.data[32*e.addr[$clog2(`AXI_WIDTH/8)-1:2]+:32]) : 'x;
                        lateLoadUOp[i].dataValid <= ltIssue[i].isLdFwd;
                        lateLoadUOp[i].addr <= e.addr;
                        lateLoadUOp[i].signExtend <= e.signExtend;
                        lateLoadUOp[i].size <= e.size;
                        lateLoadUOp[i].loadSqN <= {e.highLdSqN, ltIssue[i].idx};
                        lateLoadUOp[i].tagDst <= e.tagDst;
                        lateLoadUOp[i].sqN <= e.sqN;
                        lateLoadUOp[i].doNotCommit <= e.doNotCommit;
                        lateLoadUOp[i].external <= 0;
                        lateLoadUOp[i].exception <= e.exception;
                        lateLoadUOp[i].isMMIO <= `IS_MMIO_PMA(e.addr);
                        lateLoadUOp[i].valid <= 1;
                    end
                    else begin
                        
                        // Use the read port on entries to move load reservations into dedicated registers
                        if (i == 0 && !specRsv.valid && loadRsv.valid) begin
                            entries[loadRsv.idx].hasRsv <= 0;
                            specRsv.valid <= 1;
                            specRsv.sqN <= entries[loadRsv.idx].sqN;
                            specRsv.addr <= entries[loadRsv.idx].addr[31:2];
                        end

                        // Try to pass through ops for which early lookup failed
                        if (IN_uop[i].valid && IN_uop[i].isLoad && delayLoad[i] && !nonSpeculative[i] && !doNotReIssue[i]) begin
                            lateLoadUOp[i].data <= 'x;
                            lateLoadUOp[i].dataValid <= 0;

                            lateLoadUOp[i].addr <= IN_uop[i].addr;
                            lateLoadUOp[i].signExtend <= IN_uop[i].signExtend;
                            lateLoadUOp[i].size <= IN_uop[i].size;
                            lateLoadUOp[i].loadSqN <= IN_uop[i].loadSqN;
                            lateLoadUOp[i].tagDst <= IN_uop[i].tagDst;
                            lateLoadUOp[i].sqN <= IN_uop[i].sqN;
                            lateLoadUOp[i].doNotCommit <= IN_uop[i].doNotCommit;
                            lateLoadUOp[i].external <= 0;
                            lateLoadUOp[i].exception <= IN_uop[i].exception;
                            lateLoadUOp[i].isMMIO <= `IS_MMIO_PMA(IN_uop[i].addr);
                            lateLoadUOp[i].valid <= 1;

                            lateLoadPassthru[i] = 1;
                        end
                    end
                end
            end

            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if (invalMask[i]) begin
                    entries[i] <= LBEntry'{valid: 0, hasRsv: 1, default: 'x};
                end
            end
        end

        // Insert new entries, check stores
        for (integer i = 0; i < `NUM_AGUS; i=i+1)
            if (IN_uop[i].valid && IN_uop[i].isLoad && (!IN_branch.taken || $signed(IN_uop[i].sqN - IN_branch.sqN) <= 0)) begin
                
                reg[$clog2(NUM_ENTRIES)-1:0] index = IN_uop[i].loadSqN[$clog2(NUM_ENTRIES)-1:0];
                entries[index].exception <= IN_uop[i].exception;
                entries[index].sqN <= IN_uop[i].sqN;
                entries[index].tagDst <= IN_uop[i].tagDst;
                entries[index].signExtend <= IN_uop[i].signExtend;
                entries[index].addr <= IN_uop[i].addr;
                entries[index].size <= IN_uop[i].size;
                entries[index].hasRsv <= IN_uop[i].isLrSc;
                entries[index].doNotCommit <= IN_uop[i].doNotCommit;
                entries[index].highLdSqN <= IN_uop[i].loadSqN[$bits(SqN)-1:$clog2(NUM_ENTRIES)];
                entries[index].issued <= !delayLoad[i] || lateLoadPassthru[i];
                entries[index].noReIssue <= doNotReIssue[i];
                entries[index].nonSpec <= nonSpeculative[i];
                entries[index].valid <= 1;
            end
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
    end
end

endmodule
