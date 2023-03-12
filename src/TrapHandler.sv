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
    
    OUT_bpUpdate.valid <= 0;
    OUT_halt <= 0;
    OUT_fence <= 0;
    OUT_branch.taken <= 0;
    OUT_trapInfo.valid <= 0;
    OUT_clearICache <= 0;
    
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
                OUT_branch.fetchID <= IN_trapInstr.fetchID;
                OUT_branch.history <= baseIndexHist;
            end
            else if (IN_trapInstr.flags == FLAGS_ILLEGAL_INSTR || IN_trapInstr.flags == FLAGS_TRAP || 
                IN_trapInstr.flags == FLAGS_ACCESS_FAULT || IN_trapInstr.flags == FLAGS_XRET || externalIRQ) begin
                
                OUT_branch.taken <= 1;
                
                if (IN_trapInstr.flags == FLAGS_XRET)
                    OUT_branch.dstPC <= {IN_trapControl.retvec, 1'b0};
                else begin
                    OUT_branch.dstPC <= {IN_trapControl.mtvec, 2'b0};
                    OUT_trapInfo.valid <= 1;
                    OUT_trapInfo.trapPC <= {baseIndexPC, 1'b0};
                    
                    // TODO: add all trap reasons
                    case (IN_trapInstr.flags)
                        FLAGS_TRAP: OUT_trapInfo.cause <= IN_trapInstr.name[3:0];
                        FLAGS_ACCESS_FAULT: OUT_trapInfo.cause <= 4; // FIXME: could also be 5, 6, 7, 8
                        FLAGS_ILLEGAL_INSTR: OUT_trapInfo.cause <= 2; 
                        default: OUT_trapInfo.cause <= 7;
                    endcase
                    
                    OUT_trapInfo.isInterrupt <= !(IN_trapInstr.flags == FLAGS_ILLEGAL_INSTR || 
                        IN_trapInstr.flags == FLAGS_TRAP || IN_trapInstr.flags == FLAGS_ACCESS_FAULT);
                end
                    
                OUT_branch.sqN <= IN_trapInstr.sqN;
                OUT_branch.flush <= 1;
                // These don't matter, the entire pipeline will be flushed
                OUT_branch.storeSqN <= 0;
                OUT_branch.loadSqN <= 0;
                OUT_branch.fetchID <= IN_trapInstr.fetchID;
                OUT_branch.history <= baseIndexHist;
                    
                // FIXME: Handle external IRQ if a synchronous exception happens simultaneously
                externalIRQ <= 0;
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
