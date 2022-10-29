module TagePredictor
#(
    parameter NUM_STAGES=3,
    parameter L_0=4,
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
    output reg[4:0] OUT_predUseful,
    output reg OUT_predTaken,
    
    input wire IN_writeValid,
    input wire[30:0] IN_writeAddr,
    input BHist_t IN_writeHistory,
    input wire[2:0] IN_writeTageID,
    input wire IN_writeTaken,
    input wire[4:0] IN_writeUseful,
    input wire IN_writePred
);

localparam HASH_SIZE = $clog2(TABLE_SIZE);
integer i;
integer j;

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
    for (i = 0; i < NUM_STAGES-1; i=i+1) begin
        
        predTags[i] = IN_predAddr[TAG_SIZE-1:0];
        writeTags[i] = IN_writeAddr[TAG_SIZE-1:0];
    
        predHashes[i] = IN_predAddr[HASH_SIZE-1:0] ^ IN_predAddr[2*HASH_SIZE-1:HASH_SIZE];
        writeHashes[i] = IN_writeAddr[HASH_SIZE-1:0] ^ IN_writeAddr[2*HASH_SIZE-1:HASH_SIZE];
        
        for (j = 0; j < ((FACTOR ** i)); j=j+1) begin
            predHashes[i] = predHashes[i] ^ IN_predHistory[HASH_SIZE*j+:HASH_SIZE];
            writeHashes[i] = writeHashes[i] ^ IN_writeHistory[HASH_SIZE*j+:HASH_SIZE];
            
            predTags[i] = predTags[i] ^ IN_predHistory[TAG_SIZE*j+:TAG_SIZE];
            writeTags[i] = writeTags[i] ^ IN_writeHistory[TAG_SIZE*j+:TAG_SIZE];
            
            //predTags[i] = predTags[i] ^ IN_predHistory[(TAG_SIZE*j-1)+:TAG_SIZE];
            //writeTags[i] = writeTags[i] ^ IN_writeHistory[(TAG_SIZE*j-1)+:TAG_SIZE];
        end
    end
end

/* verilator lint_off UNOPT */
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
    
    for (i = 0; i < NUM_STAGES; i=i+1) begin
        if (valid[i]) begin
            OUT_predTageID = i[2:0];
            OUT_predTaken = predictions[i];
        end
        OUT_predUseful[i] = OUT_predTaken;
    end
    
end
endmodule
