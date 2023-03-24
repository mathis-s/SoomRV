module PreDecode
#(
    parameter NUM_INSTRS_IN=8,
    parameter NUM_INSTRS_OUT=4,
    parameter BUF_SIZE=4
)
(
    input wire clk,
    input wire rst,
    input wire ifetchValid,
    input wire outEn,
    input wire mispred,
    
    output reg OUT_full,
    
    input IF_Instr IN_instrs,
    output PD_Instr OUT_instrs[NUM_INSTRS_OUT-1:0]
    
);

typedef struct packed
{
    logic[27:0] pc;
    FetchID_t fetchID;
    logic[2:0] firstValid;
    logic[2:0] lastValid;
    logic[2:0] predPos;
    logic predTaken;
    logic[30:0] predTarget;
    logic[7:0][15:0] instr;
} PDEntry;

integer i;
PDEntry buffer[BUF_SIZE-1:0];

reg[$clog2(BUF_SIZE)-1:0] bufIndexIn;
reg[$clog2(BUF_SIZE)-1:0] bufIndexOut;
reg[$clog2(NUM_INSTRS_IN)-1:0] subIndexOut;

// TODO: Make this based on bufIndexIn/bufIndexOut
reg[$clog2(BUF_SIZE):0] freeEntries;

always_ff@(posedge clk) begin
    
    if (rst) begin
        bufIndexIn = 0;
        bufIndexOut = 0;
        for (i = 0; i < NUM_INSTRS_OUT; i=i+1)
            OUT_instrs[i].valid <= 0;
        freeEntries = BUF_SIZE;
    end
    else if (!mispred) begin

        if (outEn) begin
            for (i = 0; i < NUM_INSTRS_OUT; i=i+1) begin
                
                if ((bufIndexOut != bufIndexIn || freeEntries == 0)) begin
                    
                    PDEntry cur = buffer[bufIndexOut];
                    reg[15:0] instr = cur.instr[subIndexOut];
                    
                    // TRICKY: IFetch marks predicted branches in the second halfword (such that the branch is taken
                    // only after the entire instruction has been fetched). If we find a predicted branch in the first
                    // halfword of an instruction, there has been a branch source misspeculation.
                    reg invalidBranch = (instr[1:0] == 2'b11) && buffer[bufIndexOut].predTaken && buffer[bufIndexOut].predPos == subIndexOut;
                    assert(subIndexOut >= cur.firstValid && subIndexOut <= cur.lastValid);
                    
                    if (instr[1:0] == 2'b11 && (((bufIndexOut + 2'b1) != bufIndexIn) || subIndexOut != cur.lastValid) && !invalidBranch) begin
                        
                        OUT_instrs[i].valid <= 1;
                        OUT_instrs[i].pc <= {buffer[bufIndexOut].pc, subIndexOut};
                        OUT_instrs[i].predInvalid <= 0;
                        
                        if (subIndexOut == cur.lastValid) begin
                            bufIndexOut = bufIndexOut + 1;
                            freeEntries = freeEntries + 1;
                            subIndexOut = buffer[bufIndexOut].firstValid;
                        end
                        else subIndexOut = subIndexOut + 1;
                        
                        OUT_instrs[i].instr <= {buffer[bufIndexOut].instr[subIndexOut], instr};
                        OUT_instrs[i].fetchID <= buffer[bufIndexOut].fetchID;
                        OUT_instrs[i].predTaken <= (buffer[bufIndexOut].predTaken && buffer[bufIndexOut].predPos == subIndexOut);
                        OUT_instrs[i].predTarget <= buffer[bufIndexOut].predTarget;
                        
                        
                        if (subIndexOut == buffer[bufIndexOut].lastValid) begin
                            bufIndexOut = bufIndexOut + 1;
                            freeEntries = freeEntries + 1;
                            subIndexOut = buffer[bufIndexOut].firstValid;
                        end
                        else subIndexOut = subIndexOut + 1;
                        
                    end
                    else if (instr[1:0] != 2'b11 || invalidBranch) begin
                        OUT_instrs[i].pc <= {buffer[bufIndexOut].pc, subIndexOut};
                        OUT_instrs[i].instr <= {16'bx, instr};
                        OUT_instrs[i].fetchID <= buffer[bufIndexOut].fetchID;
                        OUT_instrs[i].predTaken <= buffer[bufIndexOut].predTaken && buffer[bufIndexOut].predPos == subIndexOut;
                        OUT_instrs[i].predTarget <= buffer[bufIndexOut].predTarget;
                        OUT_instrs[i].valid <= 1;
                        OUT_instrs[i].predInvalid <= invalidBranch;
                        
                        
                        if (subIndexOut == cur.lastValid) begin
                            bufIndexOut = bufIndexOut + 1;
                            freeEntries = freeEntries + 1;
                            subIndexOut = buffer[bufIndexOut].firstValid;
                        end
                        else subIndexOut = subIndexOut + 1;
                        
                    end
                    else OUT_instrs[i].valid <= 0;
                end
                else OUT_instrs[i].valid <= 0;
            end
        end
        
        if (ifetchValid && IN_instrs.valid) begin

            buffer[bufIndexIn].pc <= IN_instrs.pc;
            buffer[bufIndexIn].fetchID <= IN_instrs.fetchID;
            buffer[bufIndexIn].firstValid <= IN_instrs.firstValid;
            buffer[bufIndexIn].lastValid <= IN_instrs.lastValid;
            buffer[bufIndexIn].predPos <= IN_instrs.predPos;
            buffer[bufIndexIn].predTaken <= IN_instrs.predTaken;
            buffer[bufIndexIn].instr <= IN_instrs.instrs;
            buffer[bufIndexIn].predTarget <= IN_instrs.predTarget;
            
            if (bufIndexIn == bufIndexOut) 
                subIndexOut = IN_instrs.firstValid;
            
            bufIndexIn = bufIndexIn + 1;
            freeEntries = freeEntries - 1;
        end


    end
    else begin
        bufIndexIn = 0;
        bufIndexOut = 0;
        for (i = 0; i < NUM_INSTRS_OUT; i=i+1)
            OUT_instrs[i].valid <= 0;
        freeEntries = BUF_SIZE;
    end
    
    OUT_full <= (freeEntries == 0);
end

endmodule
