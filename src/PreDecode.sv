
typedef struct packed
{
    logic[27:0] pc;
    FetchID_t fetchID;
    logic[2:0] firstValid;
    logic[2:0] lastValid;
    logic[2:0] predPos;
    logic predTaken;
    
    logic[7:0][15:0] instr;
} PDEntry;

module PreDecode
#(
    parameter NUM_INSTRS_IN=8,
    parameter NUM_INSTRS_OUT=4,
    parameter BUF_SIZE=8
)
(
    input wire clk,
    input wire rst,
    input wire ifetchValid,
    input wire outEn,
    input wire mispred,
    
    output reg OUT_full,
    
    input IF_Instr IN_instrs[NUM_INSTRS_IN-1:0],
    output PD_Instr OUT_instrs[NUM_INSTRS_OUT-1:0]
    
);

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
                
                if (bufIndexOut != bufIndexIn) begin
                    
                    PDEntry cur = buffer[bufIndexOut];
                    reg[15:0] instr = cur.instr[subIndexOut];
                    assert(subIndexOut >= cur.firstValid && subIndexOut <= cur.lastValid);
                    
                    if (instr[1:0] == 2'b11 && (((bufIndexOut + 2'b1) != bufIndexIn) || subIndexOut != cur.lastValid)) begin
                        
                        OUT_instrs[i].pc <= {buffer[bufIndexOut].pc, subIndexOut};
                        OUT_instrs[i].valid <= 1;
                        
                        if (subIndexOut == cur.lastValid) begin
                            bufIndexOut = bufIndexOut + 1;
                            freeEntries = freeEntries + 1;
                            subIndexOut = buffer[bufIndexOut].firstValid;
                        end
                        else subIndexOut = subIndexOut + 1;
                        
                        OUT_instrs[i].instr <= {buffer[bufIndexOut].instr[subIndexOut], instr};
                        OUT_instrs[i].fetchID <= buffer[bufIndexOut].fetchID;
                        OUT_instrs[i].predTaken <= buffer[bufIndexOut].predTaken && buffer[bufIndexOut].predPos == subIndexOut;
                        
                        if (subIndexOut == buffer[bufIndexOut].lastValid) begin
                            bufIndexOut = bufIndexOut + 1;
                            freeEntries = freeEntries + 1;
                            subIndexOut = buffer[bufIndexOut].firstValid;
                        end
                        else subIndexOut = subIndexOut + 1;
                        
                    end
                    else if (instr[1:0] != 2'b11) begin
                        OUT_instrs[i].pc <= {buffer[bufIndexOut].pc, subIndexOut};
                        OUT_instrs[i].instr <= {16'bx, instr};
                        OUT_instrs[i].fetchID <= buffer[bufIndexOut].fetchID;
                        OUT_instrs[i].predTaken <= buffer[bufIndexOut].predTaken && buffer[bufIndexOut].predPos == subIndexOut;
                        OUT_instrs[i].valid <= 1;
                        
                        
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
        
        if (ifetchValid && (IN_instrs[0].valid||IN_instrs[1].valid||IN_instrs[2].valid||IN_instrs[3].valid||IN_instrs[4].valid||IN_instrs[5].valid||IN_instrs[6].valid||IN_instrs[7].valid)) begin
            
            buffer[bufIndexIn].predTaken <= 0;
            
            for (i = 0; i < NUM_INSTRS_IN; i=i+1) begin
                if (IN_instrs[i].valid) begin
                    buffer[bufIndexIn].instr[i] <= IN_instrs[i].instr;
                    buffer[bufIndexIn].lastValid <= i[2:0];
                    
                    if (IN_instrs[i].predTaken) begin
                        buffer[bufIndexIn].predTaken <= 1;
                        buffer[bufIndexIn].predPos <= i[2:0];
                    end
                end
            end
            
            for (i = NUM_INSTRS_IN-1; i >= 0; i=i-1)
                if (IN_instrs[i].valid) begin
                    buffer[bufIndexIn].firstValid <= i[2:0];
                    if (bufIndexIn == bufIndexOut) subIndexOut = i[2:0];
                end
            
            buffer[bufIndexIn].pc <= IN_instrs[0].pc[30:3];
            buffer[bufIndexIn].fetchID <= IN_instrs[0].fetchID;
            
            bufIndexIn = bufIndexIn + 1;
            assert(bufIndexIn != bufIndexOut);
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
    
    OUT_full <= (freeEntries < 2);
end

endmodule
