module IntALU#(parameter FUS = FU_INT_OH)
(
    input wire clk,
    input wire rst,

    input EX_UOp IN_uop,

    input BranchProv IN_branch,

    output BranchProv OUT_branch,
    output BTUpdate OUT_btUpdate,

    output ZCForward OUT_zcFwd,

    output AMO_Data_UOp OUT_amoData,
    output RES_UOp OUT_uop
);

function automatic HasFU(FuncUnit fu);
    logic rv = (FUS & (1 << fu)) != 0;
    return rv;
endfunction

wire[31:0] srcA = IN_uop.srcA;
wire[31:0] srcB = IN_uop.srcB;
wire[31:0] imm = IN_uop.imm;

assign OUT_zcFwd.result = resC;
assign OUT_zcFwd.tag = IN_uop.tagDst;
assign OUT_zcFwd.valid = IN_uop.valid && HasFU(IN_uop.fu) && !IN_uop.tagDst[$bits(Tag)-1];

wire[4:0] resLzTz;
wire resLzTzValid;

reg[31:0] srcAbitRev;
always_comb begin
    for (integer i = 0; i < 32; i=i+1)
        srcAbitRev[i] = srcA[31-i];
end
PriorityEncoder#(32) lzc(
    .IN_data(IN_uop.opcode == BM_CLZ ? srcAbitRev : srcA),
    .OUT_idx('{resLzTz}),
    .OUT_idxValid('{resLzTzValid})
);

wire[5:0] resPopCnt;
PopCnt popc
(
    .in(IN_uop.srcA),
    .res(resPopCnt)
);

wire lessThan = ($signed(srcA) < $signed(srcB));
wire lessThanU = (srcA < srcB);

wire[31:0] finalHalfwPC = IN_uop.pc;
wire[31:0] nextInstrPC = finalHalfwPC + 2;
wire[31:0] firstHalfwPC = finalHalfwPC - (IN_uop.compressed ? 0 : 2);

reg[31:0] resC;
always_comb begin
    resC = 32'bx;
    case (IN_uop.fu)
        FU_INT: if (HasFU(FU_INT) || HasFU(FU_ATOMIC)) case (IN_uop.opcode)
            ATOMIC_AMOADD_W, INT_ADD: resC = srcA + srcB;
            ATOMIC_AMOXOR_W, INT_XOR: resC = srcA ^ srcB;
            ATOMIC_AMOOR_W, INT_OR: resC = srcA | srcB;
            ATOMIC_AMOAND_W, INT_AND: resC = srcA & srcB;
            ATOMIC_AMOMAX_W, INT_MAX: resC = lessThan ? srcB : srcA;
            ATOMIC_AMOMAXU_W, INT_MAXU: resC = lessThanU ? srcB : srcA;
            ATOMIC_AMOMIN_W, INT_MIN: resC = lessThan ? srcA : srcB;
            ATOMIC_AMOMINU_W, INT_MINU: resC = lessThanU ? srcA : srcB;
            INT_SLL: resC = srcA << srcB[4:0];
            INT_SRL: resC = srcA >> srcB[4:0];
            INT_SLT: resC = {31'b0, lessThan};
            INT_SLTU: resC = {31'b0, lessThanU};
            INT_SUB: resC = srcA - srcB;
            INT_SRA: resC = $signed(srcA) >>> srcB[4:0];
            INT_LUI: resC = srcB;
            INT_SH1ADD: resC = srcB + (srcA << 1);
            INT_SH2ADD: resC = srcB + (srcA << 2);
            INT_SH3ADD: resC = srcB + (srcA << 3);
            INT_ANDN: resC = srcA & (~srcB);
            INT_ORN: resC = srcA | (~srcB);
            INT_XNOR: resC = srcA ^ (~srcB);
            INT_SE_B: resC = {{24{srcA[7]}}, srcA[7:0]};
            INT_SE_H: resC = {{16{srcA[15]}}, srcA[15:0]};
            INT_ZE_H: resC = {16'b0, srcA[15:0]};
            default: ;
        endcase

        FU_BRANCH: if (HasFU(FU_BRANCH)) case (IN_uop.opcode)
            BR_AUIPC: resC = firstHalfwPC + imm;
            BR_V_RET,
            BR_V_JR,
            BR_V_JALR,
            BR_JAL: resC = nextInstrPC;
            default: ;
        endcase

        FU_BITMANIP: if (HasFU(FU_BITMANIP)) case (IN_uop.opcode)
            BM_CLZ,
            BM_CTZ: resC = resLzTzValid ? {27'b0, resLzTz} : 32'd32;
            BM_CPOP: resC = {26'b0, resPopCnt};
            BM_ROL: resC = (srcA << srcB[4:0]) | (srcA >> (32 - srcB[4:0]));
            BM_ROR: resC = (srcA >> srcB[4:0]) | (srcA << (32 - srcB[4:0]));
            BM_ORC_B: resC = {{{4'd8}{|srcA[31:24]}}, {{4'd8}{|srcA[23:16]}}, {{4'd8}{|srcA[15:8]}}, {{4'd8}{|srcA[7:0]}}};
            BM_REV8: resC = {srcA[7:0], srcA[15:8], srcA[23:16], srcA[31:24]};
            BM_BCLR: resC = srcA & ~(RegT'(1) << srcB[$clog2($bits(RegT))-1:0]);
            BM_BEXT: resC = RegT'(srcA[srcB[$clog2($bits(RegT))-1:0]]);
            BM_BINV: resC = srcA ^ (RegT'(1) << srcB[$clog2($bits(RegT))-1:0]);
            BM_BSET: resC = srcA | (RegT'(1) << srcB[$clog2($bits(RegT))-1:0]);
    `ifdef ENABLE_FP
            BM_FSGNJ_S:  resC = {srcB[31], srcA[30:0]};
            BM_FSGNJN_S: resC = {~srcB[31], srcA[30:0]};
            BM_FSGNJX_S: resC = {srcA[31] ^ srcB[31], srcA[30:0]};
    `endif
            default: ;
        endcase
        default: ;
    endcase
end

Flags flags;
always_comb begin
    flags = FLAGS_NONE;
    if (IN_uop.fu == FU_INT && IN_uop.opcode == INT_SYS)
        flags = Flags'(imm[3:0]);
end

reg isBranch;
reg branchTaken;
always_comb begin
    branchTaken = 0;
    isBranch = 0;

    if (IN_uop.fu == FU_BRANCH) begin
        case (IN_uop.opcode)
            BR_JAL: branchTaken = 1;
            BR_BEQ: branchTaken = (srcA == srcB);
            BR_BNE: branchTaken = (srcA != srcB);
            BR_BLT: branchTaken = lessThan;
            BR_BGE: branchTaken = !lessThan;
            BR_BLTU: branchTaken = lessThanU;
            BR_BGEU: branchTaken = !lessThanU;
            default: ;
        endcase
        isBranch =
            (IN_uop.opcode == BR_BEQ ||
            IN_uop.opcode == BR_BNE ||
            IN_uop.opcode == BR_BLT ||
            IN_uop.opcode == BR_BGE ||
            IN_uop.opcode == BR_BLTU ||
            IN_uop.opcode == BR_BGEU);
    end
end

if (HasFU(FU_BRANCH)) begin
    BranchProv branch_c;
    BTUpdate btUpdate_c;

    always_ff@(posedge clk) OUT_btUpdate <= btUpdate_c;
    assign OUT_branch = branch_c;

    reg indBranchCorrect;
    reg[31:0] indBranchDst;
    always_comb begin
        indBranchCorrect = 'x;
        indBranchDst = 'x;
        case (IN_uop.opcode)
            BR_V_RET,
            BR_V_JALR,
            BR_V_JR: begin
                indBranchDst = (srcA + {{20{imm[11]}}, imm[11:0]});
                indBranchDst[0] = 0;
                indBranchCorrect = (indBranchDst[31:1] == srcB[31:1]);
            end
            default: ;
        endcase
    end

    always_comb begin
        branch_c = 'x;
        branch_c.taken = 0;
        btUpdate_c = 'x;
        btUpdate_c.valid = 0;

        if (rst) ;
        else if (IN_uop.valid && IN_uop.fu == FU_BRANCH &&
            (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)
        ) begin
            branch_c.sqN = IN_uop.sqN;
            branch_c.loadSqN = IN_uop.loadSqN;
            branch_c.storeSqN = IN_uop.storeSqN;

            branch_c.taken = 0;
            branch_c.flush = 0;

            branch_c.fetchID = IN_uop.fetchID;
            branch_c.fetchOffs = IN_uop.fetchOffs;
            branch_c.histAct = HIST_NONE;
            branch_c.retAct = RET_NONE;
            branch_c.isSCFail = 0;
            branch_c.tgtSpec = BR_TGT_MANUAL;

            if (isBranch) begin
                if (branchTaken != IN_uop.bpi.taken && IN_uop.opcode != BR_JAL) begin
                    if (branchTaken) begin
                        branch_c.dstPC = (firstHalfwPC + {{19{imm[12]}}, imm[12:0]});
                        btUpdate_c.dst = (firstHalfwPC + {{19{imm[12]}}, imm[12:0]});
                    end
                    else begin
                        branch_c.dstPC = nextInstrPC;
                    end

                    branch_c.taken = 1;
                    branch_c.cause = branchTaken ? FLUSH_BRANCH_TK : FLUSH_BRANCH_NT;
                    branch_c.histAct = branchTaken ? HIST_WRITE_1 : HIST_WRITE_0;
                end
            end
            // Check speculated return address
            else if (IN_uop.opcode == BR_V_RET || IN_uop.opcode == BR_V_JALR || IN_uop.opcode == BR_V_JR) begin
                if (!indBranchCorrect || !IN_uop.bpi.taken) begin
                    branch_c.dstPC = indBranchDst;
                    branch_c.cause = (IN_uop.opcode == BR_V_RET) ? FLUSH_RETURN : FLUSH_IBRANCH;
                    branch_c.taken = 1;

                    if (IN_uop.opcode == BR_V_RET)
                        branch_c.retAct = RET_POP;
                    if (IN_uop.opcode == BR_V_JALR)
                        branch_c.retAct = RET_PUSH;

                    if (IN_uop.opcode == BR_V_JALR || IN_uop.opcode == BR_V_JR) begin
                        btUpdate_c.src = finalHalfwPC;
                        btUpdate_c.fetchStartOffs = IN_uop.fetchStartOffs;
                        btUpdate_c.multiple = (finalHalfwPC[1+:$bits(FetchOff_t)] > IN_uop.fetchPredOffs);
                        btUpdate_c.multipleOffs = IN_uop.fetchPredOffs + 1;
                        btUpdate_c.dst = indBranchDst;
                        btUpdate_c.btype = (IN_uop.opcode == BR_V_JALR) ? BT_CALL : BT_JUMP;
                        btUpdate_c.compressed = IN_uop.compressed;
                        btUpdate_c.clean = 0;
                        btUpdate_c.valid = 1;
                    end
                end
            end
        end
    end
end
else begin
    assign OUT_btUpdate = 'x;
    assign OUT_branch = 'x;
end


always_ff@(posedge clk /*or posedge rst*/) begin

    OUT_uop <= RES_UOp'{valid: 0, default: 'x};
    OUT_amoData <= AMO_Data_UOp'{valid: 0, default: 'x};

    if (rst) ;
    else if (IN_uop.valid && HasFU(IN_uop.fu) &&
        (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)
    ) begin
        OUT_uop.result <= resC;
        OUT_uop.tagDst <= IN_uop.tagDst;
        OUT_uop.doNotCommit <= 0;
        OUT_uop.sqN <= IN_uop.sqN;

        if (HasFU(FU_ATOMIC) && IN_uop.opcode >= ATOMIC_AMOADD_W) begin
            OUT_amoData.valid <= 1;
            OUT_amoData.result <= resC;
            OUT_amoData.storeSqN <= IN_uop.storeSqN;
            OUT_amoData.sqN <= IN_uop.sqN;
        end

        OUT_uop.flags <= flags;

        if (HasFU(FU_BRANCH)) begin
            if (isBranch)
                OUT_uop.flags <= branchTaken ? FLAGS_PRED_TAKEN : FLAGS_PRED_NTAKEN;
            else if (IN_uop.opcode == BR_V_RET || IN_uop.opcode == BR_V_JALR || IN_uop.opcode == BR_V_JR)
                OUT_uop.flags <= FLAGS_BRANCH;
        end

        OUT_uop.valid <= 1;
    end
end
endmodule
