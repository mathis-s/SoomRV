module TagePredictor
#(
    parameter NUM_STAGES=3,
    parameter FACTOR=2,
    parameter TABLE_SIZE=64,
    parameter TAG_SIZE=8
)
(
    input wire clk,
    input wire rst,
    
    input wire[30:0] IN_predAddr,
    input BHist_t IN_predHistory,
    output reg[2:0] OUT_predTageID,
    output TageUseful_t OUT_predUseful,
    output reg OUT_predTaken,
    
    input wire IN_writeValid,
    input wire[30:0] IN_writeAddr,
    input BHist_t IN_writeHistory,
    input wire[2:0] IN_writeTageID,
    input wire IN_writeTaken,
    input TageUseful_t IN_writeUseful,
    input wire IN_writePred
);

localparam HASH_SIZE = $clog2(TABLE_SIZE);

wire[NUM_STAGES-1:0] valid;
wire[NUM_STAGES-1:0] predictions;

// Base bimodal predictor
BranchPredictionTable basePredictor
(
    .clk(clk),
    .rst(rst),
    .IN_readAddr(IN_predAddr[7:0]),
    .OUT_taken(predictions[0]),
    
    .IN_writeEn(IN_writeValid),
    .IN_writeAddr(IN_writeAddr[7:0]),
    .IN_writeTaken(IN_writeTaken)
);
// Base Predictor is always valid
assign valid[0] = 1;

reg[HASH_SIZE-1:0] predHashes[NUM_STAGES-2:0];
reg[HASH_SIZE-1:0] writeHashes[NUM_STAGES-2:0];
reg[TAG_SIZE-1:0] predTags[NUM_STAGES-2:0];
reg[TAG_SIZE-1:0] writeTags[NUM_STAGES-2:0];

always_comb begin
    
    for (integer i = 0; i < NUM_STAGES-1; i=i+1) begin
        
        predTags[i] = IN_predAddr[TAG_SIZE-1:0];
        writeTags[i] = IN_writeAddr[TAG_SIZE-1:0];
        
        predHashes[i] = 0;
        writeHashes[i] = 0;
        
        for (integer j = 0; j < ($bits(IN_predAddr)/HASH_SIZE); j=j+1) begin
            predHashes[i] = predHashes[i] ^ IN_predAddr[j*HASH_SIZE+:HASH_SIZE];
            writeHashes[i] = writeHashes[i] ^ IN_writeAddr[j*HASH_SIZE+:HASH_SIZE];
        end
        
        
        for (integer j = 0; j < ((FACTOR ** i)); j=j+1) begin
        
            predHashes[i] = predHashes[i] ^ IN_predHistory[TAG_SIZE*j+:HASH_SIZE] ^ {4'b0, IN_predHistory[TAG_SIZE*j+HASH_SIZE+:2]};
            writeHashes[i] = writeHashes[i] ^ IN_writeHistory[TAG_SIZE*j+:HASH_SIZE] ^ {4'b0, IN_writeHistory[TAG_SIZE*j+HASH_SIZE+:2]};
            
            predTags[i] = predTags[i] ^ IN_predHistory[TAG_SIZE*j+:TAG_SIZE];
            writeTags[i] = writeTags[i] ^ IN_writeHistory[TAG_SIZE*j+:TAG_SIZE];
            
            predTags[i] = predTags[i] ^ {IN_predHistory[TAG_SIZE*j+:(TAG_SIZE-1)], 1'b0};
            writeTags[i] = writeTags[i] ^ {IN_writeHistory[TAG_SIZE*j+:(TAG_SIZE-1)], 1'b0};
        end
        
        /*case (i)
            0: begin
                predHashes[i] = predHashes[i] ^ {IN_predHistory[0+:4], 2'b0};
                writeHashes[i] = writeHashes[i] ^ {IN_writeHistory[0+:4], 2'b0};
                
                predTags[i] = predTags[i] ^ {4'b0, IN_predHistory[0+:4]} ^ {3'b0, IN_predHistory[0+:4], 1'b0};
                writeTags[i] = writeTags[i] ^ {4'b0, IN_writeHistory[0+:4]} ^ {3'b0, IN_writeHistory[0+:4], 1'b0};
            end
            
            1: begin
                predHashes[i] = predHashes[i] ^ {IN_predHistory[0+:6]} ^ {IN_predHistory[6+:2], 4'b0};
                writeHashes[i] = writeHashes[i] ^ {IN_writeHistory[0+:6]} ^ {IN_writeHistory[6+:2], 4'b0};
                
                predTags[i] = predTags[i] ^ {IN_predHistory[0+:8]} ^ {IN_predHistory[0+:7], 1'b0};
                writeTags[i] = writeTags[i] ^ {IN_writeHistory[0+:8]} ^ {IN_writeHistory[0+:7], 1'b0};
            end
            
            2: begin
                predHashes[i] = predHashes[i] ^ {IN_predHistory[0+:6]} ^ {IN_predHistory[6+:6]} ^ {IN_predHistory[12+:4], 2'b0};
                writeHashes[i] = writeHashes[i] ^ {IN_writeHistory[0+:6]} ^ {IN_writeHistory[6+:6]} ^ {IN_writeHistory[12+:4], 2'b0};
                
                predTags[i] = predTags[i] ^ {IN_predHistory[0+:8]} ^ {IN_predHistory[8+:8]};
                writeTags[i] = writeTags[i] ^ {IN_writeHistory[0+:8]} ^ {IN_writeHistory[8+:8]};
            end
        endcase*/
        
    end
end

/* verilator lint_off UNOPTFLAT */
wire[NUM_STAGES-1:0] alloc;
assign alloc[0] = 0;
generate 
    for (genvar ii = 1; ii < NUM_STAGES; ii=ii+1) begin
        
        TageTable tage
        (
            .clk(clk),
            .rst(rst),
            .IN_readAddr(predHashes[ii-1]),
            .IN_readTag(predTags[ii-1]),
            .OUT_readValid(valid[ii]),
            .OUT_readTaken(predictions[ii]),
            
            .IN_writeAddr(writeHashes[ii-1]),
            .IN_writeTag(writeTags[ii-1]),
            .IN_writeTaken(IN_writeTaken),
            .IN_writeValid(IN_writeValid),
            .IN_writeNew(IN_writeTaken != IN_writePred && !alloc[ii-1] && ii > IN_writeTageID),
            .IN_writeUseful(IN_writeUseful[ii] == IN_writeTaken && IN_writeUseful[ii] != IN_writeUseful[ii-1]),
            .IN_writeUpdate(ii == IN_writeTageID),
            .OUT_writeAlloc(alloc[ii]),
            .IN_anyAlloc(|alloc)
        );
    end
endgenerate


always_comb begin
    
    OUT_predTaken = 0;
    OUT_predTageID = 0;
    
    for (integer i = 0; i < NUM_STAGES; i=i+1) begin
        if (valid[i]) begin
            OUT_predTageID = i[2:0];
            OUT_predTaken = predictions[i];
        end
        OUT_predUseful[i] = OUT_predTaken;
    end
    
end
endmodule
