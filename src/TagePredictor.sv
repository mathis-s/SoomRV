module TagePredictor
#(
    parameter NUM_STAGES=3,
    parameter FACTOR=2,
    parameter BASE=6,
    parameter TABLE_SIZE=64,
    parameter TAG_SIZE=9
)
(
    input wire clk,
    input wire rst,
    
    input wire IN_predValid,
    input wire[30:0] IN_predAddr,
    input BHist_t IN_predHistory,

    output TageID_t OUT_predTageID,
    output reg OUT_altPred,
    output reg OUT_predTaken,
    
    input wire IN_writeValid,
    input wire[30:0] IN_writeAddr,
    input BHist_t IN_writeHistory,
    input TageID_t IN_writeTageID,
    input wire IN_writeTaken,
    input wire IN_writeAltPred,
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

    .IN_readValid(IN_predValid),
    .IN_readAddr(IN_predAddr[`BP_BASEP_ID_LEN-1:0]),
    .OUT_taken(predictions[0]),
    
    .IN_writeEn(IN_writeValid),
    .IN_writeAddr(IN_writeAddr[`BP_BASEP_ID_LEN-1:0]),
    .IN_writeInit(1'b0), // base predictor does not use explicit allocation
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
        

        for (integer j = 0; j < (BASE * (FACTOR ** i)); j=j+1) begin
            predHashes[i][j % HASH_SIZE] = predHashes[i][j % HASH_SIZE] ^ IN_predHistory[j];
            writeHashes[i][j % HASH_SIZE] = writeHashes[i][j % HASH_SIZE] ^ IN_writeHistory[j];

            predTags[i][j % TAG_SIZE] = predTags[i][j % TAG_SIZE] ^ IN_predHistory[j] ^ IN_predHistory[(j+1) % $bits(BHist_t)];
            writeTags[i][j % TAG_SIZE] = writeTags[i][j % TAG_SIZE] ^ IN_writeHistory[j] ^ IN_writeHistory[(j+1) % $bits(BHist_t)];
        end
    end
end

reg[7:0] random;
always_ff@(posedge clk) begin
    if (rst) random[0] <= 1;
    else random <= {random[6:0], random[7] ^ random[5] ^ random[4] ^ random[3]};
end

wire[NUM_STAGES-1:0] avail;
assign avail[0] = 0;

reg[NUM_STAGES-1:0] doAlloc;
reg allocFailed;
always_comb begin
    reg[NUM_STAGES-1:0] followingAllocAvail = '0;
    reg temp = 0;
    doAlloc = '0;
    allocFailed = 0;

    // Try to allocate a bigger entry on mispredict
    if (IN_writeTaken != IN_writePred) begin
        for (integer i = 0; i < NUM_STAGES; i=i+1) begin
            for (integer j = i + 1; j < NUM_STAGES; j=j+1)
                followingAllocAvail[i] |= avail[j];
        end

        for (integer i = 0; i < NUM_STAGES; i=i+1) begin
            if (i > IN_writeTageID && avail[i] && temp == 0 &&
                // Allocate with 75% chance if other slots are available
                (!followingAllocAvail[i] || random[(i%4)*2+:2] != 2'b00)) begin
                temp = 1;
                doAlloc[i] = 1;
            end
        end
        allocFailed = !temp;
    end
end

generate 
    for (genvar i = 1; i < NUM_STAGES; i=i+1) begin
        
        TageTable#(.SIZE(TABLE_SIZE), .TAG_SIZE(TAG_SIZE)) tage
        (
            .clk(clk),
            .rst(rst),

            // Lookup/Prediction
            .IN_readValid(IN_predValid),
            .IN_readAddr(predHashes[i-1]),
            .IN_readTag(predTags[i-1]),
            .OUT_readValid(valid[i]),
            .OUT_readTaken(predictions[i]),
            
            // General info of current update
            .IN_writeValid(IN_writeValid),
            .IN_writeAddr(writeHashes[i-1]),
            .IN_writeTag(writeTags[i-1]),
            .IN_writeTaken(IN_writeTaken),
            
            // Update existing entries
            .IN_writeUpdate(i == IN_writeTageID),
            .IN_writeUseful(IN_writePred != IN_writeAltPred),
            .IN_writeCorrect(IN_writePred == IN_writeTaken),
                        
            // New entry allocation
            .OUT_allocAvail(avail[i]),
            .IN_doAlloc(doAlloc[i]),
            .IN_allocFailed(allocFailed && i > IN_writeTageID)
        );
    end
endgenerate

always_comb begin
    OUT_altPred = predictions[0];
    OUT_predTaken = predictions[0];
    OUT_predTageID = 0;
    
    for (integer i = 0; i < NUM_STAGES; i=i+1) begin
        if (valid[i]) begin
            OUT_predTageID = i[$bits(TageID_t)-1:0];
            OUT_altPred = OUT_predTaken;
            OUT_predTaken = predictions[i];
        end
    end
end
endmodule
