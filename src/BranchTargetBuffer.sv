module BranchTargetBuffer
(
    input wire clk,
    input wire rst,
    
    input wire IN_pcValid,
    input wire[30:0] IN_pc,
    
    output reg OUT_branchFound,
    output reg[30:0] OUT_branchDst,
    output FetchOff_t OUT_branchSrcOffs,
    output reg OUT_branchIsJump,
    output reg OUT_branchIsCall,
    output reg OUT_branchCompr,
    output reg OUT_multipleBranches,
    
    input BTUpdate IN_btUpdate
);

typedef struct packed
{
    logic isJump;
    logic isCall; // TODO unify fields
    logic compr;
    logic valid;
    logic[30:0] dst;
    logic[`BTB_TAG_SIZE-1:0] src;
    FetchOff_t offs;
} BTBEntry;

localparam LENGTH = `BTB_ENTRIES;/// `BTB_ASSOC;

BTBEntry entries[LENGTH-1:0];
logic multiple[LENGTH-1:0];

always_ff@(posedge clk) begin

    BTBEntry fetched = entries[IN_pc[$clog2(LENGTH)-1:0]];
    
    if (IN_pcValid) begin
        OUT_branchFound <= 0;
        OUT_multipleBranches <= 'x;
        OUT_branchDst <= 'x;
        OUT_branchIsJump <= 0;
        OUT_branchIsCall <= 0;
        OUT_branchCompr <= 0;
        OUT_branchSrcOffs <= 'x;
        
        if (fetched.valid && fetched.src == IN_pc[$clog2(LENGTH)+:`BTB_TAG_SIZE]) begin
            OUT_branchFound <= 1;
            OUT_multipleBranches <= multiple[IN_pc[$clog2(LENGTH)-1:0]];
            OUT_branchDst <= fetched.dst;
            OUT_branchIsJump <= fetched.isJump;
            OUT_branchIsCall <= fetched.isCall;
            OUT_branchCompr <= fetched.compr;
            OUT_branchSrcOffs <= fetched.offs;
        end
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin

    end
    else begin
        if (IN_btUpdate.valid) begin
            reg[$clog2(LENGTH)-1:0] idx = {IN_btUpdate.src[$clog2(LENGTH):4], IN_btUpdate.fetchStartOffs};
            if (IN_btUpdate.clean) begin
                entries[idx] <= 'x;
                entries[idx].valid <= 0;
            end
            else begin
                
                if (IN_btUpdate.multiple) begin
                    // Special handling for multiple branches in the same fetch package:
                    // For previous branch, set "multiple" to end fetch package after not-taken prediction.
                    multiple[idx] <= 1;
                    // Write target of following branch into entry after previous branch.
                    idx[$bits(FetchOff_t)-1:0] = IN_btUpdate.multipleOffs;
                end

                entries[idx].valid <= 1;
                entries[idx].compr <= IN_btUpdate.compressed;
                entries[idx].isJump <= IN_btUpdate.isJump;
                entries[idx].isCall <= IN_btUpdate.isCall;
                entries[idx].dst <= IN_btUpdate.dst[31:1];
                entries[idx].src <= IN_btUpdate.src[$clog2(LENGTH)+1 +: `BTB_TAG_SIZE];
                entries[idx].offs <= IN_btUpdate.src[1 +: $bits(FetchOff_t)];
                multiple[idx] <= 0;
            end
        end
    end
end

logic[$clog2(`BTB_ENTRIES):0] dbgOcc;

logic[`BTB_ENTRIES-1:0] dbgValid;
logic[`BTB_ENTRIES-1:0] dbgUsed;

always_comb begin
    dbgOcc = 0;
    dbgValid = 0;
    dbgUsed = 0;
    for (integer i = 0; i < LENGTH; i=i+1)
        if (entries[i].valid) begin
            dbgOcc = dbgOcc + 1;
            dbgValid[i] = 1;
        end
end

endmodule
