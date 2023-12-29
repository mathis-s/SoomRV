module PreDecode
#(
    parameter NUM_INSTRS_IN=(1<<(`FSIZE_E-1)),
    parameter NUM_INSTRS_OUT=`DEC_WIDTH,
    parameter BUF_SIZE=`PD_BUF_SIZE
)
(
    input wire clk,
    input wire rst,
    input wire outEn,
    input wire mispred,
    
    output reg OUT_full,
    
    input IF_Instr IN_instrs,
    output PD_Instr OUT_instrs[NUM_INSTRS_OUT-1:0]
    
);

typedef struct packed
{
    logic[31-`FSIZE_E:0] pc;
    FetchID_t fetchID;
    IFetchFault fetchFault;
    FetchOff_t firstValid;
    FetchOff_t lastValid;
    FetchOff_t predPos;
    logic predTaken;
    logic[30:0] predTarget;
    RetStackIdx_t rIdx;
    logic[NUM_INSTRS_IN-1:0][15:0] instr;
} PDEntry;

PDEntry buffer[BUF_SIZE-1:0];

reg[$clog2(BUF_SIZE)-1:0] bufIndexIn;
reg[$clog2(BUF_SIZE)-1:0] bufIndexOut;
reg[$clog2(NUM_INSTRS_IN)-1:0] subIndexOut;

reg[$clog2(BUF_SIZE):0] freeEntries;

always_ff@(posedge clk) begin
    
    if (rst) begin
        bufIndexIn = 0;
        bufIndexOut = 0;
        for (integer i = 0; i < NUM_INSTRS_OUT; i=i+1)
            OUT_instrs[i].valid <= 0;
        freeEntries = BUF_SIZE;
    end
    else if (!mispred) begin

        if (outEn) begin
            for (integer i = 0; i < NUM_INSTRS_OUT; i=i+1) begin
                
                if ((bufIndexOut != bufIndexIn || freeEntries == 0)) begin
                    
                    PDEntry cur = buffer[bufIndexOut];
                    reg[15:0] instr = cur.instr[subIndexOut];
                    
                    reg invalidBranch = 0;
                    
                    assert(subIndexOut >= cur.firstValid && subIndexOut <= cur.lastValid);
                    
                    if (instr[1:0] == 2'b11 && 
                        (((bufIndexOut + 1'b1) != bufIndexIn) || subIndexOut != cur.lastValid) && 
                        !invalidBranch &&
                        cur.fetchFault == IF_FAULT_NONE
                        ) begin
                        
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
                        OUT_instrs[i].targetIsRetAddr <= !buffer[bufIndexOut].predTaken;
                        OUT_instrs[i].fetchFault <= buffer[bufIndexOut].fetchFault;
                        OUT_instrs[i].rIdx <= buffer[bufIndexOut].rIdx;
                        OUT_instrs[i].is16bit <= 0;
                        OUT_instrs[i].fetchStartOffs <= buffer[bufIndexOut].firstValid;
                        OUT_instrs[i].fetchPredOffs <= buffer[bufIndexOut].predPos;
                        
                        
                        if (subIndexOut == buffer[bufIndexOut].lastValid) begin
                            bufIndexOut = bufIndexOut + 1;
                            freeEntries = freeEntries + 1;
                            subIndexOut = buffer[bufIndexOut].firstValid;
                        end
                        else subIndexOut = subIndexOut + 1;
                        
                    end
                    else if (instr[1:0] != 2'b11 || invalidBranch || cur.fetchFault != IF_FAULT_NONE) begin
                        OUT_instrs[i].pc <= {buffer[bufIndexOut].pc, subIndexOut};
                        OUT_instrs[i].fetchStartOffs <= buffer[bufIndexOut].firstValid;
                        OUT_instrs[i].fetchPredOffs <= buffer[bufIndexOut].predPos;
                        OUT_instrs[i].instr <= invalidBranch ? 32'bx : {16'bx, instr};
                        OUT_instrs[i].fetchID <= buffer[bufIndexOut].fetchID;
                        OUT_instrs[i].predTaken <= buffer[bufIndexOut].predTaken && buffer[bufIndexOut].predPos == subIndexOut;
                        OUT_instrs[i].predTarget <= buffer[bufIndexOut].predTarget;
                        OUT_instrs[i].targetIsRetAddr <= !buffer[bufIndexOut].predTaken;
                        OUT_instrs[i].valid <= 1;
                        OUT_instrs[i].predInvalid <= invalidBranch;
                        OUT_instrs[i].fetchFault <= buffer[bufIndexOut].fetchFault;
                        OUT_instrs[i].rIdx <= buffer[bufIndexOut].rIdx;
                        OUT_instrs[i].is16bit <= 1;
                        
                        
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
        
        if (!OUT_full && IN_instrs.valid) begin

            buffer[bufIndexIn].pc <= IN_instrs.pc;
            buffer[bufIndexIn].fetchID <= IN_instrs.fetchID;
            buffer[bufIndexIn].fetchFault <= IN_instrs.fetchFault;
            buffer[bufIndexIn].firstValid <= IN_instrs.firstValid;
            buffer[bufIndexIn].lastValid <= IN_instrs.lastValid;
            buffer[bufIndexIn].predPos <= IN_instrs.predPos;
            buffer[bufIndexIn].predTaken <= IN_instrs.predTaken;
            buffer[bufIndexIn].instr <= IN_instrs.instrs;
            buffer[bufIndexIn].predTarget <= IN_instrs.predTarget;
            buffer[bufIndexIn].rIdx <= IN_instrs.rIdx;
            
            if (bufIndexIn == bufIndexOut) 
                subIndexOut = IN_instrs.firstValid;
            
            bufIndexIn = bufIndexIn + 1;
            freeEntries = freeEntries - 1;
        end


    end
    else begin
        bufIndexIn = 0;
        bufIndexOut = 0;
        for (integer i = 0; i < NUM_INSTRS_OUT; i=i+1)
            OUT_instrs[i].valid <= 0;
        freeEntries = BUF_SIZE;
    end
    
    OUT_full <= (freeEntries == 0);
end

endmodule
