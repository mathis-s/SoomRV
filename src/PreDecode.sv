
module PreDecode
#(
    parameter NUM_INSTRS_IN=4,
    parameter NUM_INSTRS_OUT=4,
    parameter BUF_SIZE=16
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

IF_Instr buffer[BUF_SIZE-1:0];

reg[$clog2(BUF_SIZE)-1:0] bufIndexIn;
reg[$clog2(BUF_SIZE)-1:0] bufIndexOut;

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
            
                if (bufIndexIn != bufIndexOut) begin
                    // 32-bit Instruction
                    if ((buffer[bufIndexOut].instr[1:0] == 2'b11) && ((bufIndexOut + 4'b1) != bufIndexIn)) begin
                        OUT_instrs[i].instr <= {buffer[bufIndexOut + 1].instr, buffer[bufIndexOut].instr};
                        OUT_instrs[i].pc <= buffer[bufIndexOut].pc;
                        OUT_instrs[i].branchID <= buffer[bufIndexOut + 1].branchID;
                        OUT_instrs[i].branchPred <= buffer[bufIndexOut + 1].branchPred;
                        OUT_instrs[i].predicted <= buffer[bufIndexOut + 1].predicted;
                        OUT_instrs[i].valid <= 1;
                        bufIndexOut = bufIndexOut + 2;
                        freeEntries = freeEntries + 2;
                    end
                    // 16-bit Instruction
                    else if (buffer[bufIndexOut].instr[1:0] != 2'b11) begin
                        OUT_instrs[i].instr <= {16'bx, buffer[bufIndexOut].instr};
                        OUT_instrs[i].pc <= buffer[bufIndexOut].pc;
                        OUT_instrs[i].branchID <= buffer[bufIndexOut].branchID;
                        OUT_instrs[i].branchPred <= buffer[bufIndexOut].branchPred;
                        OUT_instrs[i].predicted <= buffer[bufIndexOut].predicted;
                        OUT_instrs[i].valid <= 1;
                        bufIndexOut = bufIndexOut + 1;
                        freeEntries = freeEntries + 1;
                    end
                    else OUT_instrs[i].valid <= 0;
                end
                else OUT_instrs[i].valid <= 0;
            end
        end
        
        for (i = 0; i < NUM_INSTRS_IN; i=i+1) begin
            if (ifetchValid && IN_instrs[i].valid) begin
                buffer[bufIndexIn] <= IN_instrs[i];
                bufIndexIn = bufIndexIn + 1;
                freeEntries = freeEntries - 1;
                assert(bufIndexIn != bufIndexOut);
            end
        end

    end
    else begin
        bufIndexIn = 0;
        bufIndexOut = 0;
        for (i = 0; i < NUM_INSTRS_OUT; i=i+1)
            OUT_instrs[i].valid <= 0;
        freeEntries = BUF_SIZE;
    end
    
    OUT_full <= (freeEntries < 5);
end

endmodule
