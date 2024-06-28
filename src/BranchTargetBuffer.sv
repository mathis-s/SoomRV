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
    logic isCall;
    logic compr;
    logic valid;
    logic[30:0] dst;
    logic[`BTB_TAG_SIZE-1:0] src;
    FetchOff_t offs;
} BTBEntry;

localparam LENGTH = `BTB_ENTRIES;


(* ram_style = "block" *)
BTBEntry entries[LENGTH-1:0];

(* ram_style = "block" *)
logic multiple[LENGTH-1:0];

logic[U_CNT_LEN-1:0] useful[LENGTH-1:0];

// Predict
struct packed
{
    BTBEntry entry;
    logic multiple;
    logic[30:0] pc;
} fetched;
always_ff@(posedge clk) begin
    if (IN_pcValid) begin
        fetched.entry <= entries[IN_pc[$clog2(LENGTH)-1:0]];
        fetched.multiple <= multiple[IN_pc[$clog2(LENGTH)-1:0]];
        fetched.pc <= IN_pc;
    end
end
// Do the tag check after the register such that a synchronous memory can be inferred.
always_comb begin
    OUT_branchFound = 0;
    OUT_multipleBranches = 'x;
    OUT_branchDst = 'x;
    OUT_branchIsJump = 0;
    OUT_branchIsCall = 0;
    OUT_branchCompr = 0;
    OUT_branchSrcOffs = 'x;
    
    if (fetched.entry.valid && 
        fetched.entry.src == fetched.pc[$clog2(LENGTH)+:`BTB_TAG_SIZE] &&
        // ignore predictions in the same line but before the current PC
        fetched.entry.offs >= fetched.pc[0+:$bits(FetchOff_t)]
    ) begin
        OUT_branchFound = 1;
        OUT_multipleBranches = fetched.multiple;
        OUT_branchDst = fetched.entry.dst;
        OUT_branchIsJump = fetched.entry.isJump;
        OUT_branchIsCall = fetched.entry.isCall;
        OUT_branchCompr = fetched.entry.compr;
        OUT_branchSrcOffs = fetched.entry.offs;
    end
end

typedef struct packed
{
    logic[$clog2(LENGTH)-1:0] idx;
    logic valid;
} SetMultiple;
SetMultiple setMult;

// Update
always_ff@(posedge clk) begin
    
    if (rst) begin
        setMult <= SetMultiple'{valid: 0, default: 'x};
    end
    else begin
        if (IN_btUpdate.valid) begin
            reg[$clog2(LENGTH)-1:0] idx = {IN_btUpdate.src[$clog2(LENGTH):$bits(FetchOff_t)+1], IN_btUpdate.fetchStartOffs};
            if (IN_btUpdate.clean) begin
                entries[idx] <= 'x;
                entries[idx].valid <= 0;
            end
            else begin
                
                if (IN_btUpdate.multiple) begin
                    // Special handling for multiple branches in the same fetch package:
                    // For previous branch, set "multiple" to end fetch package after not-taken prediction.
                    
                    // To avoid two writes to multiple in a single cycle, we cache the write instead of performing it right away.
                    //multiple[idx] <= 1;
                    setMult.valid <= 1;
                    setMult.idx <= idx;

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

                assert((IN_btUpdate.src[1+:$bits(FetchOff_t)]) >= idx[0+:$bits(FetchOff_t)]);

                multiple[idx] <= 0;
            end
        end
        else begin
            if (setMult.valid) begin
                multiple[setMult.idx] <= 1;
                setMult <= SetMultiple'{valid: 0, default: 'x};
            end
            if (OUT_branchFound) begin
                reg[$clog2(LENGTH)-1:0] idx = fetched.pc[$clog2(LENGTH)-1:0];
                if (useful[idx] != {U_CNT_LEN{1'b1}})
                    useful[idx] <= useful[idx] + 1;
            end
        end
    end
end

endmodule
