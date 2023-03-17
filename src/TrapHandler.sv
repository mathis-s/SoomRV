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

    input wire IN_irq,
    input wire IN_MEM_busy,
    input wire IN_allowBreak,

    output reg OUT_fence,
    output reg OUT_clearICache,
    output wire OUT_disableIFetch,
    output reg OUT_halt
);

reg memoryWait;
reg instrFence;
reg externalIRQ;

assign OUT_disableIFetch = memoryWait;


assign OUT_pcReadAddr = IN_trapInstr.fetchID;
wire[30:0] baseIndexPC = {IN_pcReadData.pc[30:3], IN_trapInstr.fetchOffs} - (IN_trapInstr.compressed ? 0 : 1);
BHist_t baseIndexHist;
BranchPredInfo baseIndexBPI;
always_comb begin
    if (IN_pcReadData.bpi.predicted && !IN_pcReadData.bpi.isJump && IN_trapInstr.fetchOffs > IN_pcReadData.branchPos)
        baseIndexHist = {IN_pcReadData.hist[$bits(BHist_t)-2:0], IN_pcReadData.bpi.taken};
    else
        baseIndexHist = IN_pcReadData.hist;
        
        baseIndexBPI = (IN_trapInstr.fetchOffs == IN_pcReadData.branchPos) ?
            IN_pcReadData.bpi :
            0;
end

always_ff@(posedge clk) begin
    
    OUT_halt <= 0;
    OUT_fence <= 0;
    OUT_clearICache <= 0;
    
    OUT_bpUpdate <= 'x;
    OUT_bpUpdate.valid <= 0;
    OUT_branch <= 'x;
    OUT_branch.taken <= 0;
    OUT_trapInfo <= 'x;
    OUT_trapInfo.valid <= 0;
    
    if (rst) begin
        memoryWait <= 0;
        instrFence <= 0;
        externalIRQ <= 0;
    end
    else begin
        
        externalIRQ <= externalIRQ | IN_irq;
        
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
            if ((IN_trapInstr.flags == FLAGS_TRAP && IN_allowBreak && IN_trapInstr.name == TRAP_BREAK[4:0]) || 
                IN_trapInstr.flags == FLAGS_FENCE || IN_trapInstr.flags == FLAGS_ORDERING) begin
                
                if (IN_trapInstr.flags == FLAGS_TRAP)
                    OUT_halt <= 1;
                else if (IN_trapInstr.flags == FLAGS_ORDERING) begin
                    memoryWait <= 1;
                end
                else if (IN_trapInstr.flags == FLAGS_FENCE) begin
                    instrFence <= 1;
                    memoryWait <= 1;
                    OUT_fence <= 1;
                end
                
                OUT_branch.taken <= 1;
                OUT_branch.dstPC <= {baseIndexPC + (IN_trapInstr.compressed ? 31'd1 : 31'd2), 1'b0};
                OUT_branch.sqN <= IN_trapInstr.sqN;
                OUT_branch.flush <= 1;
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= 0;//IN_trapInstr.fetchID;
                OUT_branch.history <= baseIndexHist;
            end
            else if ((IN_trapInstr.flags >= FLAGS_ILLEGAL_INSTR && IN_trapInstr.flags <= FLAGS_XRET) || externalIRQ) begin
                
                
                OUT_branch.taken <= 1;
                
                if (IN_trapInstr.flags == FLAGS_XRET)
                    OUT_branch.dstPC <= {IN_trapControl.retvec, 1'b0};
                else begin
                    reg[3:0] trapCause;
                    reg delegate;
                    reg isInterrupt = !(IN_trapInstr.flags >= FLAGS_ILLEGAL_INSTR && IN_trapInstr.flags <= FLAGS_ST_PF);
                        
                    // TODO: add all trap reasons
                    if (isInterrupt) begin
                        trapCause = 0;
                        externalIRQ <= 0;
                    end
                    else begin
                        case (IN_trapInstr.flags)
                            FLAGS_TRAP: trapCause = IN_trapInstr.name[3:0];
                            FLAGS_LD_MA: trapCause = 4;
                            FLAGS_LD_AF: trapCause = 5;
                            FLAGS_LD_PF: trapCause = 13;
                            FLAGS_ST_MA: trapCause = 6;
                            FLAGS_ST_AF: trapCause = 7;
                            FLAGS_ST_PF: trapCause = 15;
                            FLAGS_ILLEGAL_INSTR: trapCause = 2; 
                            default: trapCause = 7;
                        endcase
                        
                        // Distinguish between ecall in different priv levels
                        if (trapCause == TRAP_ECALL_M[3:0]) begin
                            case (IN_trapControl.priv)
                                PRIV_SUPERVISOR: trapCause = TRAP_ECALL_S[3:0];
                                PRIV_USER: trapCause = TRAP_ECALL_U[3:0];
                                default: begin end
                            endcase
                        end
                    end
                    
                    delegate = (IN_trapControl.priv != PRIV_MACHINE) && 
                        (isInterrupt ? IN_trapControl.mideleg[trapCause] : IN_trapControl.medeleg[trapCause]);
                    
                    OUT_branch.dstPC <= {delegate ? IN_trapControl.stvec : IN_trapControl.mtvec, 2'b0};
                    
                    OUT_trapInfo.valid <= 1;
                    OUT_trapInfo.trapPC <= {baseIndexPC, 1'b0};
                    OUT_trapInfo.cause <= trapCause;
                    OUT_trapInfo.delegate <= delegate;
                    OUT_trapInfo.isInterrupt <= isInterrupt;
                end
                    
                OUT_branch.sqN <= IN_trapInstr.sqN;
                OUT_branch.flush <= 1;
                // These don't matter, the entire pipeline will be flushed
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= IN_trapInstr.fetchID;
                OUT_branch.history <= baseIndexHist;
            end
            else begin
                OUT_bpUpdate.valid <= 1;
                OUT_bpUpdate.pc <= IN_pcReadData.pc;
                OUT_bpUpdate.compressed <= IN_trapInstr.compressed;
                OUT_bpUpdate.history <= IN_pcReadData.hist;
                OUT_bpUpdate.bpi <= IN_pcReadData.bpi;
                OUT_bpUpdate.branchTaken <= IN_trapInstr.flags == FLAGS_PRED_TAKEN;
            end
        end
    end

end

endmodule
