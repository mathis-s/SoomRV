module TrapHandler
(
    input wire clk,
    input wire rst,

    input Trap_UOp IN_trapInstr,

    output PCFileReadReqTH OUT_pcRead,
    input PCFileEntry IN_pcReadData,

    input TrapControlState IN_trapControl,
    output TrapInfoUpdate OUT_trapInfo,

    output BranchProv OUT_branch,

    input wire IN_MEM_busy,

    output reg OUT_flushTLB,
    output reg OUT_fence,
    output reg OUT_clearICache,
    output wire OUT_disableIFetch,

    output reg[31:0] OUT_dbgStallPC
);

reg memoryWait;

assign OUT_disableIFetch = memoryWait;

assign OUT_pcRead.prio = IN_trapInstr.flags != FLAGS_NX;
assign OUT_pcRead.addr = IN_trapInstr.fetchID;
assign OUT_pcRead.valid = IN_trapInstr.valid;

FetchOff_t fetchOffs;
always_ff@(posedge clk)
    fetchOffs <= IN_trapInstr.fetchOffs;

wire[30:0] finalHalfwPC = {IN_pcReadData.pc[30:$bits(FetchOff_t)], fetchOffs};
always_comb begin
    OUT_trapInfo = trapInfo_r;
    case (trapPCSpec_r)
        BR_TGT_MANUAL: ;
        BR_TGT_NEXT: OUT_trapInfo.trapPC = {finalHalfwPC, 1'b0} + 2;
        BR_TGT_CUR16: OUT_trapInfo.trapPC = {finalHalfwPC, 1'b0};
        BR_TGT_CUR32: OUT_trapInfo.trapPC = {finalHalfwPC, 1'b0} - 2;
    endcase
end

logic[31:0] OUT_dbgStallPC_c;
logic OUT_fence_c;
logic OUT_clearICache_c;
BranchProv OUT_branch_c;
TrapInfoUpdate trapInfo_r;
TrapInfoUpdate trapInfo_c;
BranchTargetSpec trapPCSpec_c;
BranchTargetSpec trapPCSpec_r;

logic OUT_flushTLB_c;
logic setMemoryWait;
always_ff@(posedge clk) begin
    OUT_fence <= OUT_fence_c;
    OUT_clearICache <= OUT_clearICache_c;
    trapInfo_r <= trapInfo_c;
    trapPCSpec_r <= trapPCSpec_c;
    OUT_flushTLB <= OUT_flushTLB_c;
    OUT_dbgStallPC <= OUT_dbgStallPC_c;

    if (rst)
        memoryWait <= 0;
    else if (setMemoryWait)
        memoryWait <= 1;
    else if (memoryWait && !IN_MEM_busy)
        memoryWait <= 0;

end

assign OUT_branch = OUT_branch_c;
always_comb begin
    OUT_fence_c = 0;
    OUT_clearICache_c = 0;

    OUT_branch_c = 'x;
    OUT_branch_c.taken = 0;
    trapInfo_c = 'x;
    trapInfo_c.valid = 0;
    trapPCSpec_c = '0;

    OUT_flushTLB_c = 0;

    setMemoryWait = 0;

    OUT_dbgStallPC_c = OUT_dbgStallPC;

    if (rst) ;
    else begin
        // Exception and branch prediction update handling
        if (IN_trapInstr.valid) begin
            // Instructions requiring pipeline flush and MRET/SRET handling
            if (IN_trapInstr.flags == FLAGS_FENCE ||
                IN_trapInstr.flags == FLAGS_ORDERING ||
                IN_trapInstr.flags == FLAGS_XRET ||
                (IN_trapInstr.flags == FLAGS_TRAP && IN_trapInstr.rd == 5'(TRAP_V_SFENCE_VMA))
            ) begin

                case (IN_trapInstr.flags)
                    FLAGS_ORDERING: begin
                        OUT_branch_c.tgtSpec = BR_TGT_NEXT;
                    end
                    FLAGS_FENCE: begin
                        OUT_clearICache_c = 1;
                        setMemoryWait = 1;
                        OUT_fence_c = 1;
                        OUT_branch_c.tgtSpec = BR_TGT_NEXT;
                    end
                    FLAGS_XRET: begin
                        OUT_branch_c.tgtSpec = BR_TGT_MANUAL;
                        OUT_branch_c.dstPC = {IN_trapControl.retvec, 1'b0};
                    end

                    FLAGS_TRAP: begin // TRAP_V_SFENCE_VMA
                        OUT_flushTLB_c = 1;
                        OUT_branch_c.tgtSpec = BR_TGT_NEXT;
                    end
                    default: begin end
                endcase

                // When an interrupt is pending after mret/sret or FLAGS_ORDERING (includes CSR write), execute it immediately
                if (IN_trapInstr.flags == FLAGS_XRET || IN_trapInstr.flags == FLAGS_ORDERING)
                    if (IN_trapControl.interruptPending) begin
                        trapInfo_c.valid = 1;

                        if (IN_trapInstr.flags == FLAGS_XRET) begin
                            trapInfo_c.trapPC = {IN_trapControl.retvec, 1'b0};
                            trapPCSpec_c = BR_TGT_MANUAL;
                        end
                        else begin
                            trapInfo_c.trapPC = 'x;
                            trapPCSpec_c = BR_TGT_NEXT;
                        end

                        trapInfo_c.cause = IN_trapControl.interruptCause;
                        trapInfo_c.delegate = IN_trapControl.interruptDelegate;
                        trapInfo_c.isInterrupt = 1;

                        OUT_branch_c.tgtSpec = BR_TGT_MANUAL;
                        OUT_branch_c.dstPC = {(IN_trapControl.interruptDelegate) ? IN_trapControl.stvec : IN_trapControl.mtvec, 2'b0};
                    end

                OUT_branch_c.taken = 1;
                OUT_branch_c.sqN = IN_trapInstr.sqN;
                OUT_branch_c.flush = 1;

                OUT_branch_c.storeSqN = IN_trapInstr.storeSqN;
                OUT_branch_c.loadSqN = IN_trapInstr.loadSqN;

                OUT_branch_c.fetchID = IN_trapInstr.fetchID;
                OUT_branch_c.fetchOffs = IN_trapInstr.fetchOffs;
                OUT_branch_c.histAct = HIST_NONE;
                OUT_branch_c.retAct = RET_NONE;
                OUT_branch_c.isSCFail = 0;
                OUT_branch_c.cause = FLUSH_ORDERING;
            end


            // Traps, Exceptions, Interrupts Handling
            else if ((IN_trapInstr.flags >= FLAGS_ILLEGAL_INSTR && IN_trapInstr.flags <= FLAGS_ST_PF)) begin

                reg[3:0] trapCause = RVP_TRAP_ILLEGAL;
                reg delegate;
                reg isInterrupt = IN_trapInstr.flags == FLAGS_TRAP && IN_trapInstr.rd == 5'(TRAP_V_INTERRUPT);

                if (isInterrupt) begin
                    trapCause = IN_trapControl.interruptCause;
                end
                else begin
                    case (IN_trapInstr.flags)
                        FLAGS_TRAP: trapCause = IN_trapInstr.rd[3:0];
                        FLAGS_LD_MA: trapCause = RVP_TRAP_LD_MA;
                        FLAGS_LD_AF: trapCause = RVP_TRAP_LD_AF;
                        FLAGS_LD_PF: trapCause = RVP_TRAP_LD_PF;
                        FLAGS_ST_MA: trapCause = RVP_TRAP_ST_MA;
                        FLAGS_ST_AF: trapCause = RVP_TRAP_ST_AF;
                        FLAGS_ST_PF: trapCause = RVP_TRAP_ST_PF;
                        FLAGS_ILLEGAL_INSTR: trapCause = RVP_TRAP_ILLEGAL;
                        default: ;
                    endcase

                    // Distinguish between ecall in different priv levels
                    if (trapCause == 4'(TRAP_ECALL_M)) begin
                        case (IN_trapControl.priv)
                            PRIV_SUPERVISOR: trapCause = RVP_TRAP_ECALL_S;
                            PRIV_USER: trapCause = RVP_TRAP_ECALL_U;
                            default: ;
                        endcase
                    end
                end

                delegate = (IN_trapControl.priv != PRIV_MACHINE) &&
                    (isInterrupt ? IN_trapControl.mideleg[trapCause] : IN_trapControl.medeleg[trapCause]);

                trapInfo_c.valid = 1;
                trapInfo_c.trapPC = 'x;
                trapPCSpec_c = IN_trapInstr.compressed ? BR_TGT_CUR16 : BR_TGT_CUR32;
                trapInfo_c.cause = trapCause;
                trapInfo_c.delegate = delegate;
                trapInfo_c.isInterrupt = isInterrupt;

                OUT_branch_c.taken = 1;
                OUT_branch_c.dstPC = {delegate ? IN_trapControl.stvec : IN_trapControl.mtvec, 2'b0};
                OUT_branch_c.sqN = IN_trapInstr.sqN;
                OUT_branch_c.flush = 1;

                OUT_branch_c.storeSqN = IN_trapInstr.storeSqN;
                OUT_branch_c.loadSqN = IN_trapInstr.loadSqN;

                if (IN_trapInstr.flags == FLAGS_ST_MA || IN_trapInstr.flags == FLAGS_ST_AF || IN_trapInstr.flags == FLAGS_ST_PF)
                    OUT_branch_c.storeSqN = IN_trapInstr.storeSqN - 1;

                OUT_branch_c.fetchID = IN_trapInstr.fetchID;
                OUT_branch_c.fetchOffs = IN_trapInstr.fetchOffs;
                OUT_branch_c.histAct = HIST_NONE;
                OUT_branch_c.retAct = RET_NONE;
                OUT_branch_c.isSCFail = 0;
                OUT_branch_c.tgtSpec = BR_TGT_MANUAL;
                OUT_branch_c.cause = FLUSH_ORDERING;
            end
            else begin
                // If the not-executed flag is still set, this is not a trap uop but a request to look up the PC
                // of the instruction we're stalled on. This is only used for debugging.
                assert(IN_trapInstr.flags == FLAGS_NX);
                OUT_dbgStallPC_c = {finalHalfwPC, 1'b0};
            end
        end
    end
end

endmodule
