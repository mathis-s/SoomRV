module LoadBuffer
#(
    parameter NUM_PORTS=2,
    parameter NUM_ENTRIES=`LB_SIZE
)
(
    input wire clk,
    input wire rst,
    
    input SqN commitSqN,
    
    input wire IN_stall,
    input AGU_UOp IN_uopLd,
    input AGU_UOp IN_uopSt,
    output wire OUT_isDelayLoad,
    
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

SqN baseIndex;
SqN indexIn;
wire[$clog2(NUM_ENTRIES)-1:0] deqIndex = baseIndex[$clog2(NUM_ENTRIES)-1:0];

LBEntry lateLoadUOp;
reg issueLateLoad;
reg delayLoad;
reg nonSpeculative;
assign OUT_isDelayLoad = delayLoad;
always_comb begin
    OUT_uopAGULd = 'x;
    OUT_uopAGULd.valid = 0;
    OUT_uopLd = 'x;
    OUT_uopLd.valid = 0;
    
    issueLateLoad = 0;
    nonSpeculative = IN_uopLd.valid && `IS_MMIO_PMA(IN_uopLd.addr) && IN_uopLd.exception == AGU_NO_EXCEPTION;
    delayLoad = nonSpeculative;
    
    // If it needs forwarding from current cycle's store, we also delay the load.
    if (IN_uopLd.valid && !IN_stall &&
        $signed(IN_uopSt.loadSqN - IN_uopLd.loadSqN) <= 0 &&
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
    
    OUT_uopLd.addr = lateLoadUOp.addr; 
    OUT_uopLd.signExtend = lateLoadUOp.signExtend; 
    OUT_uopLd.size = lateLoadUOp.size; 
    OUT_uopLd.loadSqN = {lateLoadUOp.highLdSqN, deqIndex};
    OUT_uopLd.tagDst = lateLoadUOp.tagDst;
    OUT_uopLd.sqN = lateLoadUOp.sqN; 
    OUT_uopLd.doNotCommit = lateLoadUOp.doNotCommit; 
    OUT_uopLd.external = 0;
    OUT_uopLd.exception = AGU_NO_EXCEPTION;
    OUT_uopLd.isMMIO = `IS_MMIO_PMA(lateLoadUOp.addr); 
    OUT_uopLd.valid = lateLoadUOp.valid; 
end

logic storeIsCollision;
always_comb begin
    storeIsCollision = 0;
    
    // The order we check loads here does not matter, as we reset all the way back to the store on collision.
    for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
        if (entries[i].valid && entries[i].issued &&
            $signed(IN_uopSt.loadSqN - {entries[i].highLdSqN, i[$clog2(NUM_ENTRIES)-1:0]}) <= 0 &&
            entries[i].addr[31:2] == IN_uopSt.addr[31:2] &&
                (IN_uopSt.size == 2 ||
                (IN_uopSt.size == 1 && (entries[i].size > 1 || entries[i].addr[1] == IN_uopSt.addr[1])) ||
                (IN_uopSt.size == 0 && (entries[i].size > 0 || entries[i].addr[1:0] == IN_uopSt.addr[1:0])))
            ) begin
            storeIsCollision = 1;
        end
    end
end

always_ff@(posedge clk) begin
    
    OUT_branch <= 'x;
    OUT_branch.taken <= 0;

    if (rst) begin
        for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
            entries[i].valid <= 0;
        end
        baseIndex = 0;
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
        lateLoadUOp <= 'x;
        lateLoadUOp.valid <= 0;
    end
    else begin
        if (!IN_stall) begin
            lateLoadUOp <= 'x;
            lateLoadUOp.valid <= 0;
        end

        if (IN_ldAck.valid && IN_ldAck.fail) begin
            reg[$clog2(NUM_ENTRIES)-1:0] index = IN_ldAck.loadSqN[$clog2(NUM_ENTRIES)-1:0];
            entries[index].issued <= 0;
        end

        if (IN_branch.taken) begin
            for (integer i = 0; i < NUM_ENTRIES; i=i+1) begin
                if ($signed(entries[i].sqN - IN_branch.sqN) >= 0) begin
                    entries[i] <= 'x;
                    entries[i].valid <= 0;
                end
            end
            
            if (IN_branch.flush)
                baseIndex = IN_branch.loadSqN;

            if ($signed(lateLoadUOp.sqN - IN_branch.sqN) >= 0) begin
                lateLoadUOp <= 'x;
                lateLoadUOp.valid <= 0;
            end
        end
        else begin
            // Issue Late Loads
            // We do not have the same problem as below with multiple commits here, 
            // as the ROB can't commit beyond the load we issue with this,
            // and will need more than a cycle after this runs to commit anything again.
            if (entries[deqIndex].valid && !entries[deqIndex].issued && !lateLoadUOp.valid &&
                (!entries[deqIndex].nonSpec || (commitSqN == entries[deqIndex].sqN && IN_SQ_done))
            ) begin
                lateLoadUOp <= entries[deqIndex];
                entries[deqIndex].issued <= 1;
            end
            
            // Delete entries that have been committed. To keep pace with ROB commit speed, 
            // we have to be able to delete 4 entries per cycle. The alternative to this
            // would be marking entries as "committed", and ignoring their SqN then.
            // TODO: Analyze, what's better after synthesis?
            else begin
                reg temp = 1;
                for (integer i = 0; i < 4; i=i+1) begin
                    reg[$clog2(NUM_ENTRIES)-1:0] index = deqIndex + i[$clog2(NUM_ENTRIES)-1:0];
                    if (temp && entries[index].valid && entries[index].issued && $signed(commitSqN - entries[index].sqN) > 0) begin
                        entries[index].valid <= 0;
                        baseIndex = baseIndex + 1;
                    end
                    else temp = 0;
                end
            end
        end
        // Insert new entries, check stores
        if (IN_uopLd.valid && (!IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) < 0)) begin
            
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
        
        if (IN_uopSt.valid && (!IN_branch.taken || $signed(IN_uopSt.sqN - IN_branch.sqN) < 0)) begin
            if (storeIsCollision) begin
                // We reset back to the op after the store when a load collision occurs, even though you only need to
                // go back to the offending load. This way we don't need to keep a snapshot of IFetch state for every load
                // in the buffer, we just use the store's snapshot.
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= IN_uopSt.pc + (IN_uopSt.compressed ? 2 : 4);
                OUT_branch.sqN <= IN_uopSt.sqN;
                OUT_branch.loadSqN <= IN_uopSt.loadSqN;
                OUT_branch.storeSqN <= IN_uopSt.storeSqN;
                OUT_branch.fetchID <= IN_uopSt.fetchID;
                OUT_branch.history <= IN_uopSt.history;
                OUT_branch.rIdx <= IN_uopSt.rIdx;
                OUT_branch.flush <= 0;
            end
        end
        
        OUT_maxLoadSqN <= baseIndex + NUM_ENTRIES[$bits(SqN)-1:0] - 1;
    end

end

endmodule
