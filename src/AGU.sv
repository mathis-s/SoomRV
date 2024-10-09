module AGU
#(parameter RQ_ID=2)
(
    input wire clk,
    input wire rst,
    input wire IN_stall,
    output wire OUT_stall,

    output wire[$clog2(`DTLB_MISS_QUEUE_SIZE):0] OUT_TMQ_free,

    input BranchProv IN_branch,

    input VirtMemState IN_vmem,
    output PageWalk_Req OUT_pw,
    input PageWalk_Res IN_pw,

    output TLB_Req OUT_tlb,
    input TLB_Res IN_tlb,

    output TValProv OUT_tvalProv,

    input EX_UOp IN_uop,
    output AGU_UOp OUT_aguOp,
    output ELD_UOp OUT_eldOp,
    output RES_UOp OUT_uop
);

function logic IsPermFault(logic[2:0] pte_rwx, logic pte_user, logic isLoad, logic isStore);
    logic r;
    r = (isLoad  && !(pte_rwx[2] || (pte_rwx[0] && IN_vmem.makeExecReadable))) ||
        (isStore && !pte_rwx[1]) ||
        (IN_vmem.priv == PRIV_USER && !pte_user) ||
        (IN_vmem.priv == PRIV_SUPERVISOR && pte_user && !IN_vmem.supervUserMemory);
    return r;
endfunction

reg pageWalkActive;
reg pageWalkAccepted;
reg eldIsPageWalkOp;
assign OUT_stall = (OUT_TMQ_free == 0);


wire[31:0] addr = IN_uop.srcA + IN_uop.srcB;

// Address Calculation for incoming UOps
AGU_UOp aguUOp_c;
TValProv tvalProv_c;
reg isIllegalInstr_c;

// do not commit atomics
// sc.w needs tagDst = 7'h40

always_comb begin
    aguUOp_c = 'x;
    aguUOp_c.valid = 0;
    tvalProv_c = 'x;
    tvalProv_c.valid = 0;
    isIllegalInstr_c = 0;

    aguUOp_c.addr = addr;
    aguUOp_c.tagDst = IN_uop.tagDst;
    aguUOp_c.sqN = IN_uop.sqN;
    aguUOp_c.storeSqN = IN_uop.storeSqN;
    aguUOp_c.loadSqN = IN_uop.loadSqN;
    aguUOp_c.fetchID = IN_uop.fetchID;
    aguUOp_c.fetchOffs = IN_uop.fetchOffs;
    aguUOp_c.isLrSc = 0;
    aguUOp_c.compressed = IN_uop.compressed;
    aguUOp_c.valid = IN_uop.valid && (IN_uop.fu == FU_AGU || IN_uop.fu == FU_ATOMIC);

    if (IN_uop.opcode < LSU_SC_W) begin // is load
        aguUOp_c.isLoad = 1;
        aguUOp_c.isStore = 0;
        aguUOp_c.doNotCommit = 0;

        case (IN_uop.opcode)
            LSU_LB: begin
                aguUOp_c.size = 0;
                aguUOp_c.signExtend = 1;
            end
            LSU_LH: begin
                aguUOp_c.size = 1;
                aguUOp_c.signExtend = 1;
            end
            LSU_LR_W: begin
                aguUOp_c.isLrSc = 1;
                aguUOp_c.size = 2;
                aguUOp_c.signExtend = 0;
            end
            LSU_LW: begin
                aguUOp_c.size = 2;
                aguUOp_c.signExtend = 0;
            end
            LSU_LBU: begin
                aguUOp_c.size = 0;
                aguUOp_c.signExtend = 0;
            end
            LSU_LHU: begin
                aguUOp_c.size = 1;
                aguUOp_c.signExtend = 0;
            end
            default: ;
        endcase
    end
    else begin // is store
        aguUOp_c.isLoad = 0;
        aguUOp_c.isStore = 1;
        aguUOp_c.doNotCommit = 0;

        // default
        aguUOp_c.wmask = 4'b1111;
        aguUOp_c.size = 2;

        case (IN_uop.opcode)

            LSU_SB: begin
                aguUOp_c.size = 0;
                case (addr[1:0])
                    0: begin
                        aguUOp_c.wmask = 4'b0001;
                    end
                    1: begin
                        aguUOp_c.wmask = 4'b0010;
                    end
                    2: begin
                        aguUOp_c.wmask = 4'b0100;
                    end
                    3: begin
                        aguUOp_c.wmask = 4'b1000;
                    end
                endcase
            end

            LSU_SH: begin
                aguUOp_c.size = 1;
                case (addr[1])
                    0: begin
                        aguUOp_c.wmask = 4'b0011;
                    end
                    1: begin
                        aguUOp_c.wmask = 4'b1100;
                    end
                endcase
            end

            LSU_SC_W: begin
                aguUOp_c.isLrSc = 1;
                aguUOp_c.wmask = 4'b1111;
                // The 0/1 write is handled by rename, do not write anything.
                aguUOp_c.tagDst = 7'h40;
            end

            LSU_SW: begin
                aguUOp_c.wmask = 4'b1111;
            end

            LSU_CBO_CLEAN: begin
                aguUOp_c.wmask = 0;
                if (!IN_vmem.cbcfe) begin
                    isIllegalInstr_c = 1;
                end
            end

            LSU_CBO_INVAL: begin
                aguUOp_c.wmask = 0;
                if (IN_vmem.cbie == 2'b00) begin
                    isIllegalInstr_c = 1;
                end
            end

            LSU_CBO_FLUSH: begin
                aguUOp_c.wmask = 0;
                if (!IN_vmem.cbcfe) begin
                    isIllegalInstr_c = 1;
                end
            end

            ATOMIC_AMOSWAP_W,
            ATOMIC_AMOADD_W,
            ATOMIC_AMOXOR_W,
            ATOMIC_AMOAND_W,
            ATOMIC_AMOOR_W,
            ATOMIC_AMOMIN_W,
            ATOMIC_AMOMAX_W,
            ATOMIC_AMOMINU_W,
            ATOMIC_AMOMAXU_W: begin
                // The integer uop commits atomics,
                // except for amoswap where there isn't one.
                if (IN_uop.opcode != ATOMIC_AMOSWAP_W)
                    aguUOp_c.doNotCommit = 1;

                aguUOp_c.isLoad = 1;
                aguUOp_c.size = 2;
                aguUOp_c.signExtend = 0;
            end
            default: ;
        endcase
    end
end

logic TMQ_enqueue;
logic TMQ_uopReady;

logic TMQ_dequeue;
AGU_UOp TMQ_uop;
logic TMQ_ready;
TLBMissQueue#(`DTLB_MISS_QUEUE_SIZE) tmq
(
    .clk(clk),
    .rst(rst),

    .OUT_free(OUT_TMQ_free),
    .OUT_ready(TMQ_ready),

    .IN_branch(IN_branch),
    .IN_vmem(IN_vmem),
    .IN_pw(IN_pw),
    .IN_pwActive(pageWalkActive),

    .IN_enqueue(TMQ_enqueue),
    .IN_uopReady(TMQ_uopReady),
    .IN_uop(issUOp_c),

    .IN_dequeue(TMQ_dequeue),
    .OUT_uop(TMQ_uop)
);

// Select waiting op from TLB queue or incoming uop
// for execution
AGU_UOp issUOp_c;
RES_UOp issResUOp_c;
always_comb begin
    issUOp_c = 'x;
    issUOp_c.valid = 0;
    issResUOp_c = 'x;
    issResUOp_c.valid = 0;

    TMQ_dequeue = 0;

    if (aguUOp_c.valid && !OUT_stall) begin
        issUOp_c = aguUOp_c;
        issResUOp_c.valid = aguUOp_c.valid;
        issResUOp_c.doNotCommit = aguUOp_c.doNotCommit;
        issResUOp_c.flags = isIllegalInstr_c ? FLAGS_ILLEGAL_INSTR : FLAGS_NONE;
        issResUOp_c.sqN = aguUOp_c.sqN;
        issResUOp_c.tagDst = aguUOp_c.tagDst;
        issResUOp_c.result = 'x;
    end
    else if (TMQ_uop.valid) begin

        TMQ_dequeue = 1;
        issUOp_c = TMQ_uop;
        issResUOp_c.valid = TMQ_uop.valid;
        issResUOp_c.doNotCommit = TMQ_uop.doNotCommit;
        issResUOp_c.flags = FLAGS_NONE;
        issResUOp_c.sqN = TMQ_uop.sqN;
        issResUOp_c.tagDst = TMQ_uop.tagDst;
        issResUOp_c.result = 'x;
    end
end

// Output early load op for VIPT
always_comb begin
    OUT_eldOp = 'x;
    OUT_eldOp.valid =
        !rst && issUOp_c.valid && issUOp_c.isLoad && (!IN_branch.taken || $signed(issUOp_c.sqN - IN_branch.sqN) <= 0);

    if (OUT_eldOp.valid)
        OUT_eldOp.addr = issUOp_c.addr[11:0];
end

// TLB Request
always_comb begin
    OUT_tlb.valid =
        (IN_vmem.sv32en) &&
        !(rst) &&
        (issUOp_c.valid);

    OUT_tlb.vpn = issUOp_c.addr[31:12];
end


wire[31:0] phyAddr = IN_vmem.sv32en ? {IN_tlb.ppn, issUOp_c.addr[11:0]} : issUOp_c.addr; // super is already handled in TLB
Flags exceptFlags;
always_comb begin
    exceptFlags = FLAGS_NONE;

    // Cache Management Ops are encoded with wmask 0 and
    // are ordering
    if (issUOp_c.isStore && issUOp_c.wmask == 0)
        exceptFlags = FLAGS_ORDERING;

    if (IN_vmem.sv32en && IN_tlb.hit &&
        (IN_tlb.pageFault || IsPermFault(IN_tlb.rwx, IN_tlb.user, issUOp_c.isLoad, issUOp_c.isStore))
    ) begin
        exceptFlags = issUOp_c.isStore ? FLAGS_ST_PF : FLAGS_LD_PF;
    end
    else if ((!`IS_LEGAL_ADDR(phyAddr) || IN_tlb.accessFault) && !(IN_vmem.sv32en && !IN_tlb.hit)) begin
        exceptFlags = issUOp_c.isStore ? FLAGS_ST_AF : FLAGS_LD_AF;
    end

    // Misalign has higher priority than access fault
    if (issUOp_c.isStore) begin
        case (issUOp_c.size)
            0: ;
            1: begin
                if (phyAddr[0]) begin
                    exceptFlags = FLAGS_ST_MA;
                end
            end
            default: begin
                if (phyAddr[0] || phyAddr[1]) begin
                    exceptFlags = FLAGS_ST_MA;
                end
            end
        endcase
    end
    else begin
        case (issUOp_c.size)
            0: ;
            1: begin
                if (phyAddr[0]) begin
                    exceptFlags = FLAGS_LD_MA;
                end
            end
            default: begin
                if (phyAddr[0] || phyAddr[1]) begin
                    exceptFlags = FLAGS_LD_MA;
                end
            end
        endcase
    end

    // Previous exception has highest priority.
    if (issResUOp_c.flags != FLAGS_NONE) begin
        exceptFlags = issResUOp_c.flags;
    end
end

// TLB Miss Handling
reg tlbMiss;
always_comb begin
    tlbMiss = 0;
    TMQ_enqueue = 0;
    TMQ_uopReady = 'x;

    if (!rst && issUOp_c.valid &&
        (!IN_branch.taken || $signed(issUOp_c.sqN - IN_branch.sqN) <= 0) &&
        (IN_vmem.sv32en && exceptFlags == FLAGS_NONE && !IN_tlb.hit)
    ) begin
        tlbMiss = 1;
        TMQ_enqueue = 1;
        TMQ_uopReady = 0;
    end
end

reg[31:0] pageWalkAddr;
always_ff@(posedge clk) begin

    OUT_pw.valid <= 0;

    OUT_tvalProv <= 'x;
    OUT_tvalProv.valid <= 0;
    OUT_uop <= 'x;
    OUT_uop.valid <= 0;
    OUT_aguOp <= 'x;
    OUT_aguOp.valid <= 0;

    if (rst) begin
        pageWalkActive <= 0;
    end
    else begin

        // Page Walk Request Logic
        if (pageWalkActive) begin
            if (!pageWalkAccepted) begin
                if (IN_pw.busy && IN_pw.rqID == $bits(IN_pw.rqID)'(RQ_ID)) begin
                    pageWalkAccepted <= 1;
                end
                else begin
                    OUT_pw.valid <= 1;
                    OUT_pw.rootPPN <= IN_vmem.rootPPN;
                    OUT_pw.addr <= pageWalkAddr;
                end
            end
            else if (IN_pw.valid) begin
                pageWalkActive <= 0;
                pageWalkAccepted <= 0;
            end
        end

        // Pipeline
        if (issUOp_c.valid &&
            (!IN_branch.taken || $signed(issUOp_c.sqN - IN_branch.sqN) <= 0)
        ) begin

            reg doIssue = 1;
            if (exceptFlags != FLAGS_ILLEGAL_INSTR) begin
                if (tlbMiss) begin
                    if (!pageWalkActive) begin
                        pageWalkActive <= 1;
                        pageWalkAccepted <= 0;
                        pageWalkAddr <= issUOp_c.addr;
                    end
                    doIssue = 0;
                end

                if (exceptFlags != FLAGS_NONE) begin
                    OUT_tvalProv.valid <= 1;
                    OUT_tvalProv.sqN <= issUOp_c.sqN;
                    OUT_tvalProv.tval <= issUOp_c.addr;
                end
            end

            if (doIssue) begin

                reg isLoad = issUOp_c.isLoad && !issUOp_c.isStore;
                reg isStore = !issUOp_c.isLoad && issUOp_c.isStore;
                reg isAtomic = issUOp_c.isLoad && issUOp_c.isStore;

                // Stores generate a RES_UOp right away (no result, just for tracking completion in ROB).
                // Loads/atomics only generate one early (ie right now) on exception.
                if (((isLoad || isAtomic) && exceptFlags != FLAGS_NONE) || isStore) begin
                    OUT_uop <= issResUOp_c;
                    OUT_uop.flags <= exceptFlags;
                    // doNotCommit might be set for atomics.
                    // Since there's an exception we want to commit right away though!
                    OUT_uop.doNotCommit <= 0;
                end

                // Issue the AGU_UOp only if there's no exception
                if (exceptFlags == FLAGS_NONE) begin
                    OUT_aguOp <= issUOp_c;
                    OUT_aguOp.earlyLoadFailed <= IN_stall;
                    if (IN_vmem.sv32en)
                        OUT_aguOp.addr <= phyAddr;
                end

            end

        end
    end
end
endmodule
