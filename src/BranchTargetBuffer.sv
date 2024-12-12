module BranchTargetBuffer
(
    input wire clk,
    input wire rst,

    input wire IN_pcValid,
    input wire[30:0] IN_pc,

    output PredBranch OUT_branch,

    input BTUpdate IN_btUpdate
);

typedef struct packed
{
    BranchType btype;
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

    OUT_branch = PredBranch'{valid: 0, default: 'x};

    if (fetched.entry.valid &&
        fetched.entry.src == fetched.pc[$clog2(LENGTH)+:`BTB_TAG_SIZE] &&
        // ignore predictions in the same line but before the current PC
        fetched.entry.offs >= fetched.pc[0+:$bits(FetchOff_t)]
    ) begin
        OUT_branch.valid = 1;
        OUT_branch.multiple = fetched.multiple;
        OUT_branch.dst = fetched.entry.dst;
        OUT_branch.btype = fetched.entry.btype;
        OUT_branch.compr = fetched.entry.compr;
        OUT_branch.offs = fetched.entry.offs;
        OUT_branch.taken = fetched.entry.btype == BT_CALL || fetched.entry.btype == BT_JUMP;
        OUT_branch.dirOnly = 0;
    end
end

typedef struct packed
{
    logic[$clog2(LENGTH)-1:0] idx;
    logic valid;
} SetMultiple;
SetMultiple setMult;

logic[$clog2(LENGTH):0] resetIdx;

always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst) begin
        setMult <= SetMultiple'{valid: 0, default: 'x};
        resetIdx <= 0;
    end
    else if (!resetIdx[$clog2(LENGTH)]) begin
        multiple[resetIdx[$clog2(LENGTH)-1:0]] <= 0;
        entries[resetIdx[$clog2(LENGTH)-1:0]] <= '0;
        resetIdx <= resetIdx + 1;
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
                entries[idx].btype <= IN_btUpdate.btype;
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
        end
    end
end

endmodule
