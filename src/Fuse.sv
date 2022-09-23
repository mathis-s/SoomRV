module Fuse
#(
    parameter NUM_UOPS_IN=4,
    parameter NUM_UOPS_OUT=2,
    parameter BUF_SIZE=8
)
(
    input wire clk,
    input wire frontEn,
    input wire rst,
    input wire mispredict,
    
    output reg OUT_full,
    
    input D_UOp IN_uop[NUM_UOPS_IN-1:0],
    output D_UOp OUT_uop[NUM_UOPS_OUT-1:0]
);

integer i;

D_UOp uop[NUM_UOPS_IN-1:0];


D_UOp fusedUOps[NUM_UOPS_IN-1:0];
D_UOp next_uop[NUM_UOPS_IN-1:0];
// We need a window of NUM_UOPS_IN+1 to be able to do (all) fusions of two ops
D_UOp fusionWindow[NUM_UOPS_IN:0];

D_UOp bufInsertUOps[NUM_UOPS_IN-1:0];

reg[$clog2(BUF_SIZE)-1:0] obufIndexIn;
reg[$clog2(BUF_SIZE)-1:0] obufIndexOut;
reg[$clog2(BUF_SIZE):0] freeEntries;
D_UOp outBuffer[BUF_SIZE-1:0];

always_comb begin
    
    reg lastFused = 0;
    
    // Prepare fusion NUM_UOPS_IN
    for (i = 0; i < NUM_UOPS_IN; i=i+1)
        fusionWindow[i] = uop[i];
    fusionWindow[NUM_UOPS_IN] = IN_uop[0];
    
    // Default is just passthrough
    for (i = 0; i < NUM_UOPS_IN; i=i+1) begin
        fusedUOps[i] = uop[i];
        next_uop[i] = IN_uop[i];
    end
    
    for (i = 0; i < NUM_UOPS_IN; i=i+1) begin
        
        // Fuse auipc/lui + addi
        if (!lastFused && fusionWindow[i+0].valid && fusionWindow[i+1].valid &&
            fusionWindow[i+0].fu == FU_INT && (fusionWindow[i+0].opcode == INT_LUI || fusionWindow[i+0].opcode == INT_AUIPC) &&
            fusionWindow[i+1].fu == FU_INT && fusionWindow[i+1].opcode == INT_ADD && fusionWindow[1].immB &&
            fusionWindow[i+1].rs0 == fusionWindow[i+1].rd &&
            fusionWindow[i+0].rd == fusionWindow[i+1].rd) begin
            
            // Output fused op
            fusedUOps[i+0] = fusionWindow[i+0];
            fusedUOps[i+0].opcode = INT_ADD;
            fusedUOps[i+0].imm = {fusionWindow[i+0].imm[31:12], 12'b0} + {{20{fusionWindow[i+1].imm[11]}}, fusionWindow[i+1].imm[11:0]};
            
            // Invalidate upper op as is fused into lower
            if (i+1 < NUM_UOPS_IN)
                fusedUOps[i+1].valid = 0;
            else
                next_uop[0].valid = 0;
            
            // Can't fuse an op twice
            lastFused = 1;
        end
        
        else lastFused = 0;
        
    end

end

always_ff@(posedge clk) begin
    
    if (rst) begin
        for (i = 0; i < NUM_UOPS_OUT; i=i+1)
            OUT_uop[i].valid = 0;
            
        for (i = 0; i < NUM_UOPS_IN; i=i+1) begin
            uop[i].valid = 0;
            bufInsertUOps[i].valid <= 0;
        end

        obufIndexIn = 0;
        obufIndexOut = 0;
        freeEntries = BUF_SIZE;
    end
    else if (!mispredict) begin
        
        if (frontEn) begin
            for (i = 0; i < NUM_UOPS_OUT; i=i+1) begin
                if (obufIndexOut != obufIndexIn) begin
                    OUT_uop[i] <= outBuffer[obufIndexOut];
                    OUT_uop[i].valid <= 1'b1;
                    obufIndexOut = obufIndexOut + 1;
                    freeEntries = freeEntries + 1;
                end
                else OUT_uop[i].valid <= 0;
            end
        end
        
        if (!OUT_full) begin
            bufInsertUOps <= fusedUOps;
            uop <= next_uop;
            for (i = 0; i < NUM_UOPS_IN; i=i+1) begin
                if (bufInsertUOps[i].valid) begin
                    outBuffer[obufIndexIn] <= bufInsertUOps[i];
                    obufIndexIn = obufIndexIn + 1;
                    assert(obufIndexIn != obufIndexOut);
                    freeEntries = freeEntries - 1;
                end
            end
        end
    
    end
    else if (mispredict) begin
        for (i = 0; i < NUM_UOPS_OUT; i=i+1)
            OUT_uop[i].valid = 0;
        for (i = 0; i < NUM_UOPS_IN; i=i+1) begin
            uop[i].valid = 0;
            bufInsertUOps[i].valid <= 0;
        end
        obufIndexIn = 0;
        obufIndexOut = 0;
        freeEntries = BUF_SIZE;
    end
    
    OUT_full <= (freeEntries < 5);

end

endmodule
