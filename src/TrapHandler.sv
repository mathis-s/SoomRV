module TrapHandler
(
    input wire clk,
    input wire rst,
    
    input Trap_UOp IN_trapInstr,

    output FetchID_t OUT_pcReadAddr,
    input PCFileEntry IN_pcReadData,

    input TrapControlState IN_trapControl,
    output TrapInfoUpdate OUT_trapInfo,

    output BPUpdate OUT_bpUpdate,
    output BranchProv OUT_branch,

    input wire IN_MEM_busy,
    
    output reg OUT_flushTLB,
    output reg OUT_fence,
    output reg OUT_clearICache,
    output wire OUT_disableIFetch
);

reg memoryWait;
reg instrFence;

assign OUT_disableIFetch = memoryWait;


assign OUT_pcReadAddr = IN_trapInstr.fetchID;
wire[30:0] baseIndexPC = {IN_pcReadData.pc[30:3], IN_trapInstr.fetchOffs} - (IN_trapInstr.compressed ? 0 : 1);
wire[31:0] nextInstr = {baseIndexPC + (IN_trapInstr.compressed ? 31'd1 : 31'd2), 1'b0};

BHist_t baseIndexHist;
BranchPredInfo baseIndexBPI;
always_comb begin
    if (IN_pcReadData.bpi.predicted && !IN_pcReadData.bpi.isJump && IN_trapInstr.fetchOffs > IN_pcReadData.branchPos)
        baseIndexHist = {IN_pcReadData.hist[$bits(BHist_t)-2:0], IN_pcReadData.bpi.taken};
    else
        baseIndexHist = IN_pcReadData.hist;
        
    baseIndexBPI = IN_pcReadData.bpi;
end

always_ff@(posedge clk) begin
    
    OUT_fence <= 0;
    OUT_clearICache <= 0;
    
    OUT_bpUpdate <= 'x;
    OUT_bpUpdate.valid <= 0;
    OUT_branch <= 'x;
    OUT_branch.taken <= 0;
    OUT_trapInfo <= 'x;
    OUT_trapInfo.valid <= 0;
    OUT_flushTLB <= 0;
    
    if (rst) begin
        memoryWait <= 0;
        instrFence <= 0;
    end
    else begin
        
        if (memoryWait && !IN_MEM_busy) begin
            if (instrFence) begin
                instrFence <= 0;
                OUT_clearICache <= 1;
            end
            else begin
                memoryWait <= 0;
            end
        end
            
        // Exception and branch prediction update handling
        if (IN_trapInstr.valid) begin
            
            // Instructions requiring pipeline flush and MRET/SRET handling
            if (IN_trapInstr.flags == FLAGS_FENCE || 
                IN_trapInstr.flags == FLAGS_ORDERING || 
                IN_trapInstr.flags == FLAGS_XRET ||
                (IN_trapInstr.flags == FLAGS_TRAP && IN_trapInstr.name == 5'(TRAP_V_SFENCE_VMA)) 
            ) begin
                
                case (IN_trapInstr.flags)
                    FLAGS_ORDERING: begin
                        memoryWait <= 1;
                        OUT_branch.dstPC <= nextInstr;
                    end
                    FLAGS_FENCE: begin
                        instrFence <= 1;
                        memoryWait <= 1;
                        OUT_fence <= 1;
                        OUT_branch.dstPC <= nextInstr;
                    end
                    FLAGS_XRET: begin
                        OUT_branch.dstPC <= {IN_trapControl.retvec, 1'b0};
                    end

                    FLAGS_TRAP: begin // TRAP_V_SFENCE_VMA
                        OUT_flushTLB <= 1;
                        OUT_branch.dstPC <= nextInstr;
                    end
                    default: begin end
                endcase
                
                // When an interrupt is pending after mret/sret or FLAGS_ORDERING (includes CSR write), execute it immediately
                if (IN_trapInstr.flags == FLAGS_XRET || IN_trapInstr.flags == FLAGS_ORDERING)
                    if (IN_trapControl.interruptPending) begin
                        OUT_trapInfo.valid <= 1;
                        OUT_trapInfo.trapPC <= IN_trapInstr.flags == FLAGS_XRET ? {IN_trapControl.retvec, 1'b0} : nextInstr;
                        OUT_trapInfo.cause <= IN_trapControl.interruptCause;
                        OUT_trapInfo.delegate <= IN_trapControl.interruptDelegate;
                        OUT_trapInfo.isInterrupt <= 1;
                        OUT_branch.dstPC <= {(IN_trapControl.interruptDelegate) ? IN_trapControl.stvec : IN_trapControl.mtvec, 2'b0};
                    end
                
                OUT_branch.taken <= 1;
                OUT_branch.sqN <= IN_trapInstr.sqN;
                OUT_branch.flush <= 1;
                OUT_branch.history <= baseIndexHist;
                OUT_branch.rIdx <= baseIndexBPI.rIdx;
                
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= 0;
            end


            // Traps, Exceptions, Interrupts Handling
            else if ((IN_trapInstr.flags >= FLAGS_ILLEGAL_INSTR && IN_trapInstr.flags <= FLAGS_ST_PF)) begin
                
                reg[3:0] trapCause;
                reg delegate;
                reg isInterrupt = IN_trapInstr.flags == FLAGS_TRAP && IN_trapInstr.name == 5'(TRAP_V_INTERRUPT);
                        
                if (isInterrupt) begin
                    trapCause = IN_trapControl.interruptCause;
                end
                else begin
                    case (IN_trapInstr.flags)
                        FLAGS_TRAP: trapCause = IN_trapInstr.name[3:0];
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
                
                OUT_trapInfo.valid <= 1;
                OUT_trapInfo.trapPC <= {baseIndexPC, 1'b0};
                OUT_trapInfo.cause <= trapCause;
                OUT_trapInfo.delegate <= delegate;
                OUT_trapInfo.isInterrupt <= isInterrupt;

                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= {delegate ? IN_trapControl.stvec : IN_trapControl.mtvec, 2'b0};
                OUT_branch.sqN <= IN_trapInstr.sqN;
                OUT_branch.flush <= 1;
                OUT_branch.history <= baseIndexHist;
                OUT_branch.rIdx <= baseIndexBPI.rIdx;
                // These don't matter, the entire pipeline will be flushed
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= 0;
            end

            // Branch Prediction Updates
            else begin
                if (IN_trapInstr.flags == FLAGS_PRED_TAKEN || IN_trapInstr.flags == FLAGS_PRED_NTAKEN) begin
                    OUT_bpUpdate.valid <= 1;
                    OUT_bpUpdate.pc <= IN_pcReadData.pc;
                    OUT_bpUpdate.compressed <= IN_trapInstr.compressed;
                    OUT_bpUpdate.history <= IN_pcReadData.hist;
                    OUT_branch.rIdx <= baseIndexBPI.rIdx;

                    OUT_bpUpdate.bpi <= IN_pcReadData.bpi;
                    OUT_bpUpdate.branchTaken <= IN_trapInstr.flags == FLAGS_PRED_TAKEN;
                end
            end
        end
    end

end

endmodule
