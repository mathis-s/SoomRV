module BranchHandler#(parameter NUM_INST=8)
(
    input wire clk,
    input wire rst,

    input wire IN_clear,
    input wire IN_accept,
    input IFetchOp IN_op,
    input wire[NUM_INST-1:0][15:0] IN_instrs,

    output FetchBranchProv OUT_decBranch,
    output BTUpdate OUT_btUpdate,
    output ReturnDecUpdate OUT_retUpdate,
    output logic OUT_endOffsValid,
    output FetchOff_t OUT_endOffs,

    output logic OUT_newPredTaken,
    output FetchOff_t OUT_newPredPos
);

logic[15:0] lastInstr;
logic[31:0] lastInstrPC;
logic lastInstrValid;

wire[NUM_INST:0][15:0] instrsView = {IN_instrs, lastInstr};
logic[NUM_INST:0] is16bit;
logic[NUM_INST:0] is32bit;

wire FetchOff_t firstValid = lastInstrValid ? 0 : IN_op.pc[1+:$bits(FetchOff_t)];

// Propagate instruction boundaries
always_comb begin
    // for >32-bit instructions, this will have to be a counter
    logic validInstrStart = 1;

    is16bit = 0;
    is32bit = 0;

    if (lastInstrValid && IN_op.pc[1+:$bits(FetchOff_t)] == 0) begin
        is32bit[0] = 1;
        validInstrStart = 0;
    end

    for (integer i = 1; i < NUM_INST+1; i=i+1) begin

        // only accept instructions within the package's boundaries
        if (FetchOff_t'(i - 1) < firstValid)
            validInstrStart = 0;
        if (FetchOff_t'(i - 1) == firstValid && !lastInstrValid)
            validInstrStart = 1;
        if (FetchOff_t'(i - 1) > IN_op.lastValid)
            validInstrStart = 0;

        if (validInstrStart) begin
            // 32-bit instruction
            if (instrsView[i][1:0] == 2'b11) begin
                is32bit[i] = 1;
                validInstrStart = 0;
            end
            // 16-bit instruction
            else begin
                is16bit[i] = 1;
                validInstrStart = 1;
            end
        end
        else begin
            // If the current halfword was the second half of a 32-bit instruction,
            // the next halfword is a valid instruction start again.
            validInstrStart = 1;
        end
    end
end

// Compute PCs for all instructions
logic[31:0] pc[NUM_INST:0];
always_comb begin
    pc[0] = lastInstrPC;
    for (integer i = 1; i < NUM_INST+1; i=i+1)
        pc[i] = {IN_op.pc[31:1+$bits(FetchOff_t)], FetchOff_t'(0), 1'b0} + (i - 1) * 2;
end

// Compute Branch Targets for all possible boundaries and instructions
logic[31:0] CJ_target[NUM_INST:0];
logic[31:0] CB_target[NUM_INST:0];
logic[31:0] J_target[NUM_INST-1:0];
logic[31:0] B_target[NUM_INST-1:0];
always_comb begin
    for (integer i = 0; i < NUM_INST+1; i=i+1) begin
        logic[15:0] i16 = instrsView[i];

        CJ_target[i] = pc[i] +
            {{20{i16[12]}}, i16[12], i16[8], i16[10:9], i16[6], i16[7], i16[2], i16[11], i16[5:3], 1'b0};

        CB_target[i] = pc[i] +
            {{23{i16[12]}}, i16[12], i16[6:5], i16[2], i16[11:10], i16[4:3], 1'b0};
    end

    for (integer i = 0; i < NUM_INST; i=i+1) begin
        logic[31:0] i32 = {instrsView[i+1], instrsView[i]};

        J_target[i] = pc[i] + {{12{i32[31]}}, i32[19:12], i32[20], i32[30:21], 1'b0};
        B_target[i] = pc[i] + {{20{i32[31]}}, i32[7], i32[30:25], i32[11:8], 1'b0};
    end
end

// Find Branches
typedef enum logic[2:0]
{
    // This enum is not to be confused with Include.sv/BranchType, which does not
    // distinguish between direct and indirect branches. Indirect-ness is stored
    // in the least significant bit, i.e. when divided by two, this enum is in the
    // same order as the regular BranchType type.
    JUMP, IJUMP, CALL, ICALL, BRANCH, PAD0___, PAD1___, RETURN
} BH_BranchType;

typedef struct packed
{
    logic[31:0] target;
    logic[31:0] pc;
    logic[31:0] fhPC; // final halfword pc
    BH_BranchType btype;
    logic compr;
    logic valid;
} Branch;

Branch branch[NUM_INST-1:0];

always_comb begin

    for (integer i = 0; i < NUM_INST; i=i+1)
        branch[i] = Branch'{valid: 0, default: 'x};

    for (integer i = 0; i < NUM_INST; i=i+1) begin
        if (is16bit[i+1]) begin
            logic[15:0] i16 = instrsView[i+1];
            unique casez (i16)
                16'b001???????????01, // c.jal
                16'b101???????????01: begin // c.j
                    branch[i].valid = 1;
                    branch[i].compr = 1;
                    branch[i].btype = (i16[15-:3] == 3'b001) ? CALL : JUMP;
                    branch[i].target = CJ_target[i+1];
                    branch[i].pc = pc[i+1];
                    branch[i].fhPC = pc[i+1];
                end
                16'b1000?????0000010: if (i16[11:7] != 0) begin // c.jr
                    branch[i].valid = 1;
                    branch[i].compr = 1;
                    branch[i].btype = (i16[11:7] == 1) ? RETURN : IJUMP;
                    branch[i].target = 'x;
                    branch[i].pc = pc[i+1];
                    branch[i].fhPC = pc[i+1];
                end
                16'b1001?????0000010: if (i16[11:7] != 0) begin // c.jalr
                    branch[i].valid = 1;
                    branch[i].compr = 1;
                    branch[i].btype = ICALL;
                    branch[i].target = 'x;
                    branch[i].pc = pc[i+1];
                    branch[i].fhPC = pc[i+1];
                end
                16'b111???????????01, // c.bnez
                16'b110???????????01: begin // c.beqz
                    branch[i].valid = 1;
                    branch[i].compr = 1;
                    branch[i].btype = BRANCH;
                    branch[i].target = CB_target[i+1];
                    branch[i].pc = pc[i+1];
                    branch[i].fhPC = pc[i+1];
                end
                default: ;
            endcase
        end
    end

    for (integer i = 0; i < NUM_INST; i=i+1) begin
        if (is32bit[i]) begin
            logic[31:0] i32 = {instrsView[i+1], instrsView[i]};
            unique casez (i32)
                32'b????????????????????_?????_1101111: begin // jal
                    branch[i].valid = 1;
                    branch[i].compr = 0;
                    branch[i].btype = (i32[11:7] == 1 || i32[11:7] == 5) ? CALL : JUMP;
                    branch[i].target = J_target[i];
                    branch[i].pc = pc[i];
                    branch[i].fhPC = pc[i+1];
                end

                32'b????????????_?????_000_?????_1100111: begin // jalr
                    branch[i].valid = 1;
                    branch[i].compr = 0;
                    unique casez ({i32[11:7] == 1 || i32[11:7] == 5, i32[19:15] == 1 || i32[19:15] == 5, i32[17] == i32[9]})
                        3'b00?: branch[i].btype = IJUMP;
                        3'b01?: branch[i].btype = RETURN;
                        3'b10?: branch[i].btype = ICALL;
                        3'b110: branch[i].btype = IJUMP;//RETICALL;
                        3'b111: branch[i].btype = ICALL;
                    endcase
                    branch[i].target = 'x;
                    branch[i].pc = pc[i];
                    branch[i].fhPC = pc[i+1];
                end

                32'b???????_?????_?????_???_?????_1100011: if (instrsView[i][14:12] != 2 && instrsView[i][14:12] != 3) begin // branch
                    branch[i].valid = 1;
                    branch[i].compr = 0;
                    branch[i].btype = BRANCH;
                    branch[i].target = B_target[i];
                    branch[i].pc = pc[i];
                    branch[i].fhPC = pc[i+1];
                end
                default: ;
            endcase
        end
    end

end

// Generate Outputs
FetchBranchProv decBranch_c;
BTUpdate btUpdate_c;
ReturnDecUpdate retUpd_c;
logic endOffsValid;
FetchOff_t endOffs;
FetchOff_t newPredPos_c;
logic newPredTaken_c;

always_comb begin
    OUT_decBranch = FetchBranchProv'{taken: 0, default: 'x};
    //OUT_btUpdate = BTUpdate'{valid: 0, default: 'x};
    OUT_retUpdate = ReturnDecUpdate'{valid: 0, default: 'x};
    OUT_endOffsValid = 0;
    OUT_endOffs = 'x;
    OUT_newPredPos = 'x;
    OUT_newPredTaken = 'x;
    if (IN_accept) begin
        OUT_decBranch = decBranch_c;
        //OUT_btUpdate = btUpdate_c;
        OUT_retUpdate = retUpd_c;
        OUT_endOffsValid = endOffsValid;
        OUT_endOffs = endOffs;
        OUT_newPredPos = newPredPos_c;
        OUT_newPredTaken = newPredTaken_c;
    end
end

always_ff@(posedge clk) begin
    OUT_btUpdate <= BTUpdate'{valid: 0, default: 'x};
    //OUT_retUpdate <= ReturnDecUpdate'{valid: 0, default: 'x};
    if (IN_accept && !IN_clear) begin
        OUT_btUpdate <= btUpdate_c;
        //OUT_retUpdate <= retUpd_c;
    end
end

always_comb begin

    decBranch_c = FetchBranchProv'{taken: 0, default: 'x};
    btUpdate_c = BTUpdate'{valid: 0, default: 'x};
    retUpd_c = ReturnDecUpdate'{valid: 0, default: 'x};

    decBranch_c.isFetchBranch = 1;

    endOffs = 'x;
    endOffsValid = 0;

    newPredTaken_c = IN_op.predBr.valid && IN_op.predBr.taken;
    newPredPos_c = IN_op.predBr.offs;

    for (integer i = 0; i < NUM_INST; i=i+1) begin
        Branch curBr = branch[i];

        // convert BH_BranchType to regular BranchType
        BranchType curBr_btypeSimple = curBr.btype[1+:$bits(BranchType)];

        logic isIndirBranch = curBr.valid &&
            (curBr.btype == IJUMP || curBr.btype == ICALL || curBr.btype == RETURN/* || curBr.btype == RETICALL*/);

        logic[30:0] curPC = {IN_op.pc[31:$bits(FetchOff_t)+1], FetchOff_t'(i)};
        logic[30:0] nextPC = curPC + 1;

        logic predicted = IN_op.predBr.valid && IN_op.predBr.offs == FetchOff_t'(i) && !IN_op.predBr.dirOnly;

        if (decBranch_c.taken) ;
        else if (i > IN_op.lastValid || i < IN_op.pc[1+:$bits(FetchOff_t)]) ;

        // A taken prediction was made by the BP, check if correct.
        else if (predicted && IN_op.predBr.taken) begin

            if (// Branch was predicted, but there is none in the package
                !curBr.valid ||

                // Invalid branch type was predicted
                curBr_btypeSimple != IN_op.predBr.btype ||

                // Invalid target
                (!isIndirBranch && curBr.target[31:1] != IN_op.predBr.dst)
            ) begin
                // Prediction is not just wrong but illegal, i.e. no actual instruction exists
                // at supposed source. This is the case if a branch was predicted at the first
                // halfword of a 32-bit instruction.
                // Legal predictions are always in the final halfword, such that the entire
                // 32-bit instruction can be fetched before the prediction is made.
                logic predIllegal = is32bit[IN_op.predBr.offs + ($bits(FetchOff_t)+1)'(1)];

                // Delete matching regular branch prediction entries
                btUpdate_c.valid = 1;
                btUpdate_c.clean = 1;
                btUpdate_c.multiple = 0;
                btUpdate_c.multipleOffs = 'x;
                btUpdate_c.fetchStartOffs = IN_op.pc[1+:$bits(FetchOff_t)];
                btUpdate_c.src = {IN_op.pc[31:$bits(FetchOff_t)], IN_op.predBr.offs};

                // Trigger a decode branch
                decBranch_c.taken = 1;
                decBranch_c.fetchID = IN_op.fetchID;
                decBranch_c.fetchOffs = FetchOff_t'(i);
                decBranch_c.retAct = RET_NONE;
                decBranch_c.histAct = (curBr.valid && curBr.btype == BRANCH) ? HIST_APPEND_1 : HIST_NONE;
                decBranch_c.tgtSpec = BR_TGT_MANUAL;
                decBranch_c.wfi = 0;

                if (curBr.valid && (curBr.btype == CALL || curBr.btype == ICALL)) begin
                    retUpd_c.valid = 1;
                    retUpd_c.idx = IN_op.rIdx;
                    retUpd_c.addr = {IN_op.pc[31:1+$bits(FetchOff_t)], curBr.fhPC[1+:$bits(FetchOff_t)]};
                end

                if (curBr.valid)
                    case (curBr.btype)
                        CALL, ICALL: decBranch_c.retAct = RET_PUSH;
                        RETURN: decBranch_c.retAct = RET_POP;
                        default: ;
                    endcase


                // Branch was predicted at correct address, but target is wrong.
                if (!predIllegal && curBr.valid && (!isIndirBranch || curBr.btype == RETURN)) begin

                    // Correct matching branch prediction entries
                    btUpdate_c.clean = 0;
                    btUpdate_c.btype = curBr_btypeSimple;
                    btUpdate_c.src = curBr.fhPC;
                    btUpdate_c.fetchStartOffs = IN_op.pc[1+:$bits(FetchOff_t)];
                    btUpdate_c.dst = curBr.target;
                    btUpdate_c.compressed = curBr.compr;

                    decBranch_c.dst = (curBr.btype == RETURN) ? IN_op.predRetAddr : curBr.target[31:1];
                end
                else if (predIllegal) begin
                    // On illegal prediction, we need to re-fetch the entire 32-bit instruction
                    // (not just first half)
                    decBranch_c.dst = curPC;
                    newPredTaken_c = 0;
                    newPredPos_c = {$bits(FetchOff_t){1'b1}};

                    endOffsValid = 1;
                    endOffs = IN_op.predBr.offs;
                end
                else begin
                    // The prediction was wrong but preserved instruction boundaries, so we only need to start
                    // re-fetching post-branch instructions;
                    decBranch_c.dst = nextPC;
                    newPredTaken_c = 0;
                    newPredPos_c = {$bits(FetchOff_t){1'b1}};

                    // unless this was the final halfword, all following are invalid
                    if (IN_op.predBr.offs != {$bits(FetchOff_t) {1'b1}}) begin
                        endOffsValid = 1;
                        endOffs = IN_op.predBr.offs + 1;
                    end
                end

            end
        end
        // Handle non-predicted taken jumps or direction-only predicted branches
        else if (curBr.valid) begin
            FetchOff_t actualOffs = curBr.fhPC[1+:$bits(FetchOff_t)];

            reg dirOnly = (curBr.btype == BRANCH && IN_op.predBr.valid && IN_op.predBr.dirOnly);
            reg dirOnlyTaken = (dirOnly && IN_op.predBr.taken);

            // For taken branches with known target, do the jump now.
            if (curBr.btype == JUMP || curBr.btype == CALL || curBr.btype == RETURN || dirOnlyTaken) begin
                decBranch_c.taken = 1;
                decBranch_c.fetchID = IN_op.fetchID;
                decBranch_c.fetchOffs = FetchOff_t'(i);
                decBranch_c.dst = (curBr.btype == RETURN) ? IN_op.predRetAddr : curBr.target[31:1];
                decBranch_c.histAct = dirOnlyTaken ? HIST_APPEND_1 : HIST_NONE;
                decBranch_c.tgtSpec = BR_TGT_MANUAL;
                decBranch_c.wfi = 0;

                case (curBr.btype)
                    CALL:    decBranch_c.retAct = RET_PUSH;
                    RETURN:  decBranch_c.retAct = RET_POP;
                    default: decBranch_c.retAct = RET_NONE;
                endcase

                newPredTaken_c = 1;
                newPredPos_c = actualOffs;

                if (actualOffs != {$bits(FetchOff_t) {1'b1}}) begin
                    endOffsValid = 1;
                    endOffs = actualOffs + 1;
                end
            end
            // Also flush IFetch pipeline for unpredicted branches to correct history.
            else if ((!predicted && curBr.btype == BRANCH && !dirOnlyTaken) || (curBr.btype == ICALL)) begin
                decBranch_c.taken = 1;
                decBranch_c.fetchID = IN_op.fetchID;
                decBranch_c.fetchOffs = FetchOff_t'(i);
                decBranch_c.dst = nextPC;
                decBranch_c.retAct = (curBr.btype == ICALL) ? RET_PUSH : RET_NONE;
                decBranch_c.histAct = (curBr.btype == BRANCH) ? HIST_APPEND_0 : HIST_NONE;
                decBranch_c.tgtSpec = BR_TGT_MANUAL;
                decBranch_c.wfi = 0;

                if (actualOffs != {$bits(FetchOff_t) {1'b1}}) begin
                    endOffsValid = 1;
                    endOffs = actualOffs + 1;
                end
            end

            // Register Branch Target in BTB
            if (!predicted &&
                (curBr.btype == JUMP || curBr.btype == CALL || curBr.btype == BRANCH || curBr.btype == RETURN)
            ) begin
                // Register branch target
                btUpdate_c.valid = 1;
                btUpdate_c.clean = 0;
                btUpdate_c.multiple = actualOffs > IN_op.predBr.offs;
                btUpdate_c.multipleOffs = IN_op.predBr.offs + 1;
                btUpdate_c.btype = curBr_btypeSimple;
                btUpdate_c.src = curBr.fhPC;
                btUpdate_c.fetchStartOffs = IN_op.pc[1+:$bits(FetchOff_t)];
                btUpdate_c.dst = curBr.target;
                btUpdate_c.compressed = curBr.compr;
            end

            // Return Prediction Stuff
            if (curBr.btype == CALL || curBr.btype == ICALL) begin
                retUpd_c.valid = 1;
                retUpd_c.idx = IN_op.rIdx;
                retUpd_c.addr = {IN_op.pc[31:1+$bits(FetchOff_t)], actualOffs};
            end
        end

        // A not-taken prediction was made, but there's no branch
        else if (predicted) begin
            logic predIllegal = is32bit[IN_op.predBr.offs + ($bits(FetchOff_t)+1)'(1)];

            // branch to next instruction to correct history
            decBranch_c.taken = 1;
            decBranch_c.fetchID = IN_op.fetchID;
            decBranch_c.fetchOffs = FetchOff_t'(i);
            decBranch_c.dst = nextPC;
            decBranch_c.retAct = RET_NONE;
            decBranch_c.histAct = HIST_NONE;
            decBranch_c.tgtSpec = BR_TGT_MANUAL;
            decBranch_c.wfi = 0;

            newPredTaken_c = 0;
            newPredPos_c = {$bits(FetchOff_t){1'b1}};

            if (FetchOff_t'(i) != {$bits(FetchOff_t) {1'b1}}) begin
                endOffsValid = 1;
                endOffs = FetchOff_t'(i) + 1;
            end

            if (predIllegal) begin
                endOffsValid = 1;
                endOffs = FetchOff_t'(i);

                decBranch_c.dst = curPC;
            end

            // Delete matching regular branch prediction entries
            btUpdate_c.valid = 1;
            btUpdate_c.clean = 1;
            btUpdate_c.multiple = 0;
            btUpdate_c.multipleOffs = 'x;
            btUpdate_c.fetchStartOffs = IN_op.pc[1+:$bits(FetchOff_t)];
            btUpdate_c.src = {IN_op.pc[31:$bits(FetchOff_t)], IN_op.predBr.offs};
        end
    end
end

always_ff@(posedge clk) begin
    if (rst) begin
        lastInstr <= 'x;
        lastInstrValid <= 0;
    end
    else begin
        if (IN_clear) begin
            lastInstr <= 'x;
            lastInstrValid <= 0;
        end
        else if (IN_accept) begin

            reg[$bits(FetchOff_t):0] lastIdx = $bits(FetchOff_t)'(IN_op.lastValid) + 1;

            // A 32-bit instr may span two fetch packages. In that case, we store the
            // current fetch package's end, and handle it once the second half of the
            // instruction arrives.
            if (is32bit[lastIdx] && !decBranch_c.taken) begin
                lastInstrValid <= 1;
                lastInstr <= instrsView[NUM_INST];
                lastInstrPC <= pc[NUM_INST];
            end
            else begin
                lastInstrValid <= 0;
                lastInstr <= 'x;
            end
        end
    end
end

endmodule
