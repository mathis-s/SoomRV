
`define OPC_LUI 7'b0110111
`define OPC_AUIPC 7'b0010111
`define OPC_JAL 7'b1101111
`define OPC_JALR 7'b1100111
`define OPC_LOAD 7'b0000011
`define OPC_STORE 7'b0100011
`define OPC_BRANCH 7'b1100011
`define OPC_REG_IMM 7'b0010011
`define OPC_REG_REG 7'b0110011
`define OPC_ENV 7'b1110011
`define OPC_BITM 7'b0110011

`define OPC_FLW 7'b0000111
`define OPC_FSW 7'b0100111
`define OPC_FMADD 7'b1000011
`define OPC_FMSUB 7'b1000111
`define OPC_FNMSUB 7'b1001011
`define OPC_FNMADD 7'b1001111
`define OPC_FP 7'b1010011
`define OPC_FENCE 7'b0001111

typedef struct packed
{
    logic[6:0] funct7; 
    logic[4:0] rs1;
    logic[4:0] rs0;
    logic[2:0] funct3;
    logic[4:0] rd;
    logic[6:0] opcode;
} Instr32;

typedef struct packed
{
    logic[11:0] offset;
    logic[4:0] rs1;
    logic[2:0] width;
    logic[4:0] rd;
    logic[6:0] opcode;
} Instr32_LD_FP;

typedef struct packed
{
    logic[6:0] offset2;
    logic[4:0] rs2;
    logic[4:0] rs1;
    logic[2:0] width;
    logic[4:0] offset;
    logic[6:0] opcode;
} Instr32_ST_FP;

typedef struct packed
{
    logic[4:0] funct5;
    logic[1:0] fmt;
    logic[4:0] rs2;
    logic[4:0] rs1;
    logic[2:0] rm;
    logic[4:0] rd;
    logic[6:0] opcode;
} Instr32_OP_FP;

typedef struct packed
{
    logic[4:0] rs3;
    logic[1:0] fmt;
    logic[4:0] rs2;
    logic[4:0] rs1;
    logic[2:0] rm;
    logic[4:0] rd;
    logic[6:0] opcode;
} Instr32_FMA;

typedef union packed
{
    Instr32 rr;
    Instr32_LD_FP flw;
    Instr32_ST_FP fsw;
    Instr32_OP_FP fp;
    Instr32_FMA fma;
} I32;

typedef struct packed
{
    logic[3:0] funct4;
    logic[4:0] rd_rs1;
    logic[4:0] rs2;
    logic[1:0] op;
} Instr16_CR;

typedef struct packed
{
    logic[2:0] funct3;
    logic imm2;
    logic[4:0] rd_rs1;
    logic[4:0] imm;
    logic[1:0] op;
} Instr16_CI;

typedef struct packed
{
    logic[2:0] funct3;
    logic[5:0] imm;
    logic[4:0] rs2;
    logic[1:0] op;
} Instr16_CSS;

typedef struct packed
{
    logic[2:0] funct3;
    logic[7:0] imm;
    logic[2:0] rd;
    logic[1:0] op;
} Instr16_CIW;

typedef struct packed
{
    logic[2:0] funct3;
    logic[2:0] imm2;
    logic[2:0] rs1;
    logic[1:0] imm;
    logic[2:0] rd;
    logic[1:0] op;
} Instr16_CL;

typedef struct packed
{
    logic[2:0] funct3;
    logic[2:0] imm2;
    logic[2:0] rd_rs1;
    logic[1:0] imm;
    logic[2:0] rs2;
    logic[1:0] op;
} Instr16_CS;

typedef struct packed
{
    logic[5:0] funct6;
    logic[2:0] rd_rs1;
    logic[1:0] funct2;
    logic[2:0] rs2;
    logic[1:0] op;
} Instr16_CA;

typedef struct packed
{
    logic[2:0] funct3;
    logic[2:0] imm2;
    logic[2:0] rd_rs1;
    logic[4:0] imm;
    logic[1:0] op;
} Instr16_CB;

typedef struct packed
{
    logic[2:0] funct3;
    logic imm2;
    logic[1:0] funct2;
    logic[2:0] rd_rs1;
    logic[4:0] imm;
    logic[1:0] op;
} Instr16_CB2;

typedef struct packed
{
    logic[2:0] funct3;
    logic[10:0] imm;
    logic[1:0] op;
} Instr16_CJ;

typedef union packed
{
    logic[15:0] raw;
    Instr16_CR cr;
    Instr16_CI ci;
    Instr16_CSS css;
    Instr16_CIW ciw;
    Instr16_CL cl;
    Instr16_CS cs;
    Instr16_CA ca;
    Instr16_CB cb;
    Instr16_CB2 cb2;
    Instr16_CJ cj;
} Instr16;

module InstrDecoder
#(
    parameter NUM_UOPS=4
)
(
    input wire clk,
    input wire rst,
    input wire en,
    input wire IN_invalidate,
    input PD_Instr IN_instrs[NUM_UOPS-1:0],
    
    input wire[30:0] IN_indirBranchTarget,
    
    output reg OUT_decBranch,
    output reg[30:0] OUT_decBranchDst,
    output FetchID_t OUT_decBranchFetchID,
    
    //output BTUpdate OUT_btUpdate,

    output D_UOp OUT_uop[NUM_UOPS-1:0]
);

reg RS_inValid;
reg[30:0] RS_inData;

reg RS_outValid;
reg RS_inPop;
reg[30:0] RS_outData;
ReturnStack returnStack
(
    .clk(clk),
    .rst(rst),
    
    .IN_valid(RS_inValid),
    .IN_data(RS_inData),
    
    .OUT_valid(RS_outValid),
    .IN_pop(RS_inPop),
    .OUT_data(RS_outData)
);

integer i;

D_UOp uop;
reg invalidEnc;
Instr32 instr;
Instr16 i16;
I32 i32;

D_UOp uopsComb[NUM_UOPS-1:0];

always_comb begin
    
    RS_inValid = 0;
    RS_inData = 31'bx;
    RS_inPop = 0;
    OUT_decBranch = 0;
    OUT_decBranchDst = 31'bx;
    
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        
        instr = IN_instrs[i].instr;
        i32 = IN_instrs[i].instr;
        i16 = IN_instrs[i].instr[15:0];
        
        uop = 0;
        invalidEnc = 1;
        //uop.pc = {IN_instrs[i].pc, 1'b0};
        uop.valid = IN_instrs[i].valid && en && !OUT_decBranch;
        uop.fetchID = IN_instrs[i].fetchID;
        uop.fetchOffs = IN_instrs[i].pc[1:0] + (instr.opcode[1:0] == 2'b11 ? 1 : 0);
        
        case (instr.opcode)
            `OPC_LUI,
            `OPC_AUIPC:      uop.imm = {instr[31:12], 12'b0};
            `OPC_JAL:        uop.imm = $signed({{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0});
            `OPC_ENV,
            `OPC_JALR,          
            `OPC_LOAD,
            `OPC_REG_IMM:    uop.imm = $signed({{20{instr[31]}}, instr[31:20]});
            `OPC_BRANCH:     uop.imm = $signed({{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0});
            `OPC_STORE:    uop.imm = $signed({{20{instr[31]}}, instr[31:25], instr[11:7]});
            //`OPC_REG_REG,
            default:      uop.imm = 0;
        endcase
        
        if (IN_instrs[i].valid && en && !OUT_decBranch) begin
            reg isJumpBranch = 0;
            // Regular Instructions
            if (instr.opcode[1:0] == 2'b11) begin
                case (instr.opcode)
                    `OPC_ENV: begin
                        if (uop.imm == 0 || uop.imm == 1) begin
                            case (uop.imm)
                                0: uop.imm[2:0] = FLAGS_EXCEPT;
                                1: uop.imm[2:0] = FLAGS_BRK;
                            endcase
                            uop.fu = FU_INT;
                            uop.rs0 = 0;
                            uop.rs1 = 0;
                            uop.rd = 0;
                            uop.opcode = INT_SYS;
                            uop.immB = 1;
                            invalidEnc = 0;
                        end
                    end
                    `OPC_LUI: begin
                        uop.fu = FU_INT;
                        uop.rs0 = 0;
                        uop.rs1 = 0;
                        uop.immB = 1;
                        uop.rd = instr.rd;
                        uop.opcode = INT_LUI;
                        invalidEnc = 0;
                    end
                    `OPC_AUIPC: begin
                        uop.fu = FU_INT;
                        uop.rs0 = 0;
                        uop.rs1 = 0;
                        uop.rd = instr.rd;
                        uop.opcode = INT_AUIPC;
                        invalidEnc = 0;
                    end
                    `OPC_JAL: begin
                        uop.fu = FU_INT;
                        uop.rs0 = 0;
                        uop.rs1 = 0;
                        uop.immB = 1;
                        uop.rd = instr.rd;
                        uop.opcode = INT_JAL;
                        invalidEnc = 0;
                        
                        // Return
                        if (uop.rd == 1) begin
                            RS_inValid = 1;
                            RS_inData = IN_instrs[i].pc + 2;
                        end
                        // Handle unpredicted jumps right away
                        if (!IN_instrs[i].predTaken) begin
                            OUT_decBranchDst = IN_instrs[i].pc[30:0] + uop.imm[31:1];
                            OUT_decBranch = 1;
                            OUT_decBranchFetchID = IN_instrs[i].fetchID;
                        end
                        // Predicted jumps don't need to be executed if the don't write anything
                        else if (uop.rd == 0 && IN_instrs[i].predTaken) begin
                            uop.valid = 0;
                        end
                        
                    end
                    `OPC_JALR: begin
                        uop.fu = FU_INT;
                        uop.rs0 = instr.rs0;
                        uop.immB = 1;
                        uop.rd = instr.rd;
                        uop.opcode = INT_JALR; 
                        invalidEnc = 0;
                    end
                    `OPC_LOAD: begin
                        uop.rs0 = instr.rs0;
                        uop.rs1 = 0;
                        uop.immB = 1;
                        uop.rd = instr.rd;

                        uop.fu = FU_LSU;
                        case (instr.funct3)
                            0: uop.opcode = LSU_LB;
                            1: uop.opcode = LSU_LH;
                            2: uop.opcode = LSU_LW;
                            4: uop.opcode = LSU_LBU;
                            5: uop.opcode = LSU_LHU;
                        endcase
                        invalidEnc = 
                            instr.funct3 != 0 && instr.funct3 != 1 &&
                            instr.funct3 != 2 && instr.funct3 != 4 &&
                            instr.funct3 != 5;
                    end
                    `OPC_STORE: begin
                        uop.rs0 = instr.rs0;
                        uop.rs1 = instr.rs1;
                        uop.immB = 0;
                        uop.rd = 0;

                        uop.fu = FU_ST;
                        case (instr.funct3)
                            0: uop.opcode = LSU_SB;
                            1: uop.opcode = LSU_SH;
                            2: uop.opcode = LSU_SW;
                        endcase
                        invalidEnc = 
                            instr.funct3 != 0 && instr.funct3 != 1 &&
                            instr.funct3 != 2;
                    end
                    `OPC_BRANCH: begin
                        uop.rs0 = instr.rs0;
                        uop.rs1 = instr.rs1;
                        uop.immB = 0;
                        uop.rd = 0;
                        
                        uop.fu = FU_INT;
                        case (instr.funct3)
                            0: uop.opcode = INT_BEQ;
                            1: uop.opcode = INT_BNE;
                            4: uop.opcode = INT_BLT;
                            5: uop.opcode = INT_BGE;
                            6: uop.opcode = INT_BLTU;
                            7: uop.opcode = INT_BGEU;
                        endcase
                        invalidEnc =
                            (uop.opcode == 2) || (uop.opcode == 3);
                    end
                    `OPC_FENCE: begin
                        if (instr.funct3 == 0) begin
                            uop.fu = FU_INT;
                            uop.opcode = INT_SYS;
                            uop.imm = {29'bx, FLAGS_FENCE};
                            invalidEnc = 0;
                        end
                        else if (instr.funct3 == 1) begin
                            uop.fu = FU_INT;
                            uop.opcode = INT_SYS;
                            uop.imm = {29'bx, FLAGS_FENCE};
                            invalidEnc = 0;
                        end
                        // cbo.inval -> runs as store op, invalidates to instruction after itself
                        else if (instr.funct3 == 3'b010 && instr.rd == 0 && instr[31:20] == 0) begin
                            invalidEnc = 0;
                            uop.opcode = LSU_CBO_INVAL;
                            uop.fu = FU_ST;
                            uop.rs0 = instr.rs0;
                        end
                        // cbo.clean -> runs as store op
                        else if (instr.funct3 == 3'b010 && instr.rd == 0 && instr[31:20] == 1) begin
                            invalidEnc = 0;
                            uop.opcode = LSU_CBO_CLEAN;
                            uop.fu = FU_ST;
                            uop.rs0 = instr.rs0;
                        end
                        // cbo.flush -> runs as store op, invalidates to instruction after itself
                        else if (instr.funct3 == 3'b010 && instr.rd == 0 && instr[31:20] == 2) begin
                            invalidEnc = 0;
                            uop.opcode = LSU_CBO_FLUSH;
                            uop.fu = FU_ST;
                            uop.rs0 = instr.rs0;
                        end
                    end
                    `OPC_REG_IMM: begin
                        uop.rs0 = instr.rs0;
                        uop.rs1 = 0;
                        uop.immB = 1;
                        uop.rd = instr.rd;
                        
                        invalidEnc = (instr.funct3 == 1 && instr.funct7 != 0) || 
                                    (instr.funct3 == 5 && (instr.funct7 != 7'h20 && instr.funct7 != 0));
                        uop.fu = FU_INT;
                        case (instr.funct3)
                            0: uop.opcode = INT_ADD;
                            1: uop.opcode = INT_SLL;
                            2: uop.opcode = INT_SLT;
                            3: uop.opcode = INT_SLTU;
                            4: uop.opcode = INT_XOR;
                            5: uop.opcode = (instr.funct7 == 7'h20) ? INT_SRA : INT_SRL;
                            6: uop.opcode = INT_OR;
                            7: uop.opcode = INT_AND;
                        endcase
                        
                        if (instr.funct7 == 7'b0110000) begin
                            if (instr.funct3 == 3'b001) begin
                                if (instr.rs1 == 5'b00000) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_CLZ;
                                end
                                else if (instr.rs1 == 5'b00001) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_CTZ;
                                end
                                else if (instr.rs1 == 5'b00010) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_CPOP;
                                end
                                else if (instr.rs1 == 5'b00100) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_SE_B;
                                end
                                else if (instr.rs1 == 5'b00101) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_SE_H;
                                end
                                else if (instr.rs1 == 5'b00101) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_ZE_H;
                                end
                            end
                            else if (instr.funct3 == 3'b101) begin
                                invalidEnc = 0;
                                uop.opcode = INT_ROR;
                                uop.imm = {27'b0, instr.rs1};
                            end
                        end
                        else if (instr[31:20] == 12'b001010000111 && instr.funct3 == 3'b101) begin
                            invalidEnc = 0;
                            uop.opcode = INT_ORC_B;
                        end
                        else if (instr[31:20] == 12'b011010011000 && instr.funct3 == 3'b101) begin
                            invalidEnc = 0;
                            uop.opcode = INT_REV8;
                        end
                        if (instr.funct7 == 7'b0100100) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BCLR;
                                uop.imm = {27'b0, instr.rs1};
                            end
                            else if (instr.funct3 == 3'b101) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BEXT;
                                uop.imm = {27'b0, instr.rs1};
                            end
                        end
                        else if (instr.funct7 == 7'b0110100) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BINV;
                                uop.imm = {27'b0, instr.rs1};
                            end
                        end
                        else if (instr.funct7 == 7'b0010100) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BSET;
                                uop.imm = {27'b0, instr.rs1};
                            end
                        end
                        
                        // li rd, 0 is eliminated during rename
                        if (uop.fu == FU_INT && uop.opcode == INT_ADD && uop.rs0 == 0 && uop.imm == 0) begin
                            if (uop.rd == 0) uop.valid = 0;
                            else uop.fu = FU_RN;
                        end
                    end
                    `OPC_REG_REG: begin
                        uop.rs0 = instr.rs0;
                        uop.rs1 = instr.rs1;
                        uop.immB = 0;
                        uop.rd = instr.rd;
                        uop.fu = FU_INT;
                        
                        if (instr.funct7 == 0) begin
                            invalidEnc = 0;
                            case (instr.funct3)
                                0: uop.opcode = INT_ADD;
                                1: uop.opcode = INT_SLL;
                                2: uop.opcode = INT_SLT;
                                3: uop.opcode = INT_SLTU;
                                4: uop.opcode = INT_XOR;
                                5: uop.opcode = INT_SRL;
                                6: uop.opcode = INT_OR;
                                7: uop.opcode = INT_AND;
                            endcase 
                        end
                        else if (instr.funct7 == 7'h01) begin
                            invalidEnc = 0;

                            if (instr.funct3 < 4) uop.fu = FU_MUL;
                            else uop.fu = FU_DIV;

                            case (instr.funct3)
                                0: uop.opcode = MUL_MUL;
                                1: uop.opcode = MUL_MULH;
                                2: uop.opcode = MUL_MULSU;
                                3: uop.opcode = MUL_MULU;
                                4: uop.opcode = DIV_DIV;
                                5: uop.opcode = DIV_DIVU;
                                6: uop.opcode = DIV_REM;
                                7: uop.opcode = DIV_REMU;
                            endcase
                        end
                        else if (instr.funct7 == 7'h20) begin
                            invalidEnc = (instr.funct3 != 0 && instr.funct3 != 5);
                            uop.fu = FU_INT;
                            case (instr.funct3)
                                0: uop.opcode = INT_SUB;
                                5: uop.opcode = INT_SRA;
                            endcase
                        end
                        
                        if (instr.funct7 == 7'b0010000) begin
                            if (instr.funct3 == 3'b010) begin
                                invalidEnc = 0;
                                uop.opcode = INT_SH1ADD;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b100) begin
                                invalidEnc = 0;
                                uop.opcode = INT_SH2ADD;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b110) begin
                                invalidEnc = 0;
                                uop.opcode = INT_SH3ADD;
                                uop.fu = FU_INT;
                            end
                        end
                        else if (instr.funct7 == 7'b0100000) begin
                            if (instr.funct3 == 3'b111) begin
                                invalidEnc = 0;
                                uop.opcode = INT_ANDN;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b110) begin
                                invalidEnc = 0;
                                uop.opcode = INT_ORN;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b100) begin
                                invalidEnc = 0;
                                uop.opcode = INT_XNOR;
                                uop.fu = FU_INT;
                            end
                        end
                        else if (instr.funct7 == 7'b0000101) begin
                            if (instr.funct3 == 3'b110) begin
                                invalidEnc = 0;
                                uop.opcode = INT_MAX;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b111) begin
                                invalidEnc = 0;
                                uop.opcode = INT_MAXU;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b100) begin
                                invalidEnc = 0;
                                uop.opcode = INT_MIN;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b101) begin
                                invalidEnc = 0;
                                uop.opcode = INT_MINU;
                                uop.fu = FU_INT;
                            end
                        end
                        else if (instr.funct7 == 7'b0000100 && instr.rs1 == 0 && instr.funct3 == 3'b100) begin
                            // NOTE: differenct encoding in rv64!
                            invalidEnc = 0;
                            uop.rs1 = 0;
                            uop.opcode = INT_ZE_H;
                        end
                        else if (instr.funct7 == 7'b0110000) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_ROL;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b101) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_ROR;
                                uop.fu = FU_INT;
                            end
                        end
                        else if (instr.funct7 == 7'b0100100) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BCLR;
                                uop.fu = FU_INT;
                            end
                            else if (instr.funct3 == 3'b101) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BEXT;
                                uop.fu = FU_INT;
                            end
                        end
                        else if (instr.funct7 == 7'b0110100) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BINV;
                                uop.fu = FU_INT;
                            end
                        end
                        else if (instr.funct7 == 7'b0010100) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BSET;
                                uop.fu = FU_INT;
                            end
                        end
                    end
                    
                    `OPC_FLW: begin
                        if (i32.flw.width == 3'b010) begin
                            uop.fu = FU_LSU;
                            uop.opcode = LSU_FLW;
                            uop.rs0 = i32.flw.rs1;
                            uop.rd = i32.flw.rd;
                            uop.rd_fp = 1;
                            uop.imm = {{20{i32.flw.offset[11]}}, i32.flw.offset[11:0]};
                            invalidEnc = 0;
                        end
                    end
                    `OPC_FSW: begin
                        if (i32.fsw.width == 3'b010) begin
                            uop.fu = FU_ST;
                            uop.opcode = LSU_FSW;
                            uop.rs0 = i32.fsw.rs1;
                            uop.rs1 = i32.fsw.rs2;
                            uop.rs1_fp = 1;
                            uop.imm = {{20{i32.fsw.offset2[6]}}, i32.fsw.offset2[6:0], i32.fsw.offset[4:0]};
                            invalidEnc = 0;
                        end
                    end
                    `OPC_FMADD: begin
                        // fmadd.s
                        if (i32.fma.fmt == 2'b00) begin
                            uop.fu = FU_FPU;
                            uop.opcode = FPU_FMADD_S;
                            uop.rs0 = i32.fma.rs1;
                            uop.rs0_fp = 1;
                            uop.rs1 = i32.fma.rs2;
                            uop.rs1_fp = 1;
                            uop.rs2 = i32.fma.rs3;
                            uop.rd = i32.fma.rd;
                            uop.rd_fp = 1;
                            invalidEnc = 0;
                        end
                    end
                    `OPC_FMSUB: begin
                        // fmsub.s
                        if (i32.fma.fmt == 2'b00) begin
                            uop.fu = FU_FPU;
                            uop.opcode = FPU_FMSUB_S;
                            uop.rs0 = i32.fma.rs1;
                            uop.rs0_fp = 1;
                            uop.rs1 = i32.fma.rs2;
                            uop.rs1_fp = 1;
                            uop.rs2 = i32.fma.rs3;
                            uop.rd = i32.fma.rd;
                            uop.rd_fp = 1;
                            invalidEnc = 0;
                        end
                    end
                    `OPC_FNMSUB: begin
                        // fnmsub.s
                        if (i32.fma.fmt == 2'b00) begin
                            uop.fu = FU_FPU;
                            uop.opcode = FPU_FNMSUB_S;
                            uop.rs0 = i32.fma.rs1;
                            uop.rs0_fp = 1;
                            uop.rs1 = i32.fma.rs2;
                            uop.rs1_fp = 1;
                            uop.rs2 = i32.fma.rs3;
                            uop.rd = i32.fma.rd;
                            uop.rd_fp = 1;
                            invalidEnc = 0;
                        end
                    end
                    `OPC_FNMADD: begin
                        // fnmadd.s
                        if (i32.fma.fmt == 2'b00) begin
                            uop.fu = FU_FPU;
                            uop.opcode = FPU_FNMADD_S;
                            uop.rs0 = i32.fma.rs1;
                            uop.rs0_fp = 1;
                            uop.rs1 = i32.fma.rs2;
                            uop.rs1_fp = 1;
                            uop.rs2 = i32.fma.rs3;
                            uop.rd = i32.fma.rd;
                            uop.rd_fp = 1;
                            invalidEnc = 0;
                        end
                    end
                    `OPC_FP: begin
                        // single precision
                        if (i32.fp.fmt == 2'b00) begin
                            
                            uop.fu = FU_FPU;
                            uop.rs0 = i32.fp.rs1;
                            uop.rs0_fp = 1;
                            uop.rs1 = i32.fp.rs2;
                            uop.rs1_fp = 1;
                            uop.rd = i32.fp.rd;
                            uop.rd_fp = 1;
                            invalidEnc = 0;
                            
                            case (i32.fp.funct5)
                                
                                5'b00000: uop.opcode = FPU_FADD_S;
                                5'b00001: uop.opcode = FPU_FSUB_S;
                                5'b00010: uop.opcode = FPU_FMUL_S;
                                5'b00011: uop.opcode = FPU_FDIV_S;
                                5'b01011: begin
                                    uop.opcode = FPU_FSQRT_S;
                                    uop.rs1_fp = 0;
                                    uop.rs1 = 0;
                                    if (i32.fp.rs2 != 0) invalidEnc = 1;
                                end
                                5'b00100: begin
                                    if (i32.fp.rm == 3'b000)
                                        uop.opcode = FPU_FSGNJ_S;
                                    else if (i32.fp.rm == 3'b001)
                                        uop.opcode = FPU_FSGNJN_S;
                                    else if (i32.fp.rm == 3'b010)
                                        uop.opcode = FPU_FSGNJX_S;
                                    else invalidEnc = 1;
                                end
                                5'b00101: begin
                                    if (i32.fp.rm == 3'b000)
                                        uop.opcode = FPU_FMIN_S;
                                    else if (i32.fp.rm == 3'b001)
                                        uop.opcode = FPU_FMAX_S;
                                    else invalidEnc = 1;
                                end
                                5'b11000: begin
                                    uop.rs1 = 0;
                                    uop.rs1_fp = 0;
                                    uop.rd_fp = 0;
                                    if (i32.fp.rs2 == 5'b00000)
                                        uop.opcode = FPU_FCVTWS;
                                    else if (i32.fp.rs2 == 5'b00001)
                                        uop.opcode = FPU_FCVTWUS;
                                    else invalidEnc = 1;
                                end
                                5'b11100: begin
                                    uop.rd_fp = 0;
                                    if (i32.fp.rs2 == 5'b00000 && i32.fp.rm == 3'b000)
                                        uop.opcode = FPU_FMVXW;
                                    else if (i32.fp.rs2 == 5'b00000 && i32.fp.rm == 3'b001) begin
                                        uop.opcode = FPU_FCLASS_S;
                                        uop.rd_fp = 0;
                                    end
                                    else invalidEnc = 1;
                                end
                                5'b10100: begin
                                    uop.rd_fp = 0;
                                    if (i32.fp.rm == 3'b010)
                                        uop.opcode = FPU_FEQ_S;
                                    else if (i32.fp.rm == 3'b001)
                                        uop.opcode = FPU_FLT_S;
                                    else if (i32.fp.rm == 3'b000)
                                        uop.opcode = FPU_FLE_S;
                                    else invalidEnc = 1;
                                end
                                5'b11010: begin
                                    uop.rs0_fp = 0;
                                    uop.rs1_fp = 0;
                                    
                                    if (i32.fp.rs2 == 5'b00000) begin
                                        uop.opcode = FPU_FCVTSW;
                                    end
                                    else if (i32.fp.rs2 == 5'b00001) begin
                                        uop.opcode = FPU_FCVTSWU;
                                    end
                                    else invalidEnc = 1;
                                end
                                5'b11110: begin
                                    uop.rs0_fp = 0;
                                    if (i32.fp.rs2 == 0 && i32.fp.rm == 0)
                                        uop.opcode = FPU_FMVWX;
                                    else invalidEnc = 1;
                                end
                                default: invalidEnc = 1;
                            endcase
                        end
                    end
                    
                    default: invalidEnc = 1;
                endcase
            end
            // Compressed Instructions
            else begin
                uop.compressed = 1;
                if (i16.raw[1:0] == 2'b00) begin
                    // c.lw
                    if (i16.cl.funct3 == 3'b010) begin
                        uop.opcode = LSU_LW;
                        uop.fu = FU_LSU;
                        uop.imm = {25'b0, i16.cl.imm[0], i16.cl.imm2, i16.cl.imm[1], 2'b00};
                        uop.rs0 = {2'b01, i16.cl.rs1};
                        uop.rd = {2'b01, i16.cl.rd};
                        invalidEnc = 0;
                    end
                    // c.sw
                    else if (i16.cs.funct3 == 3'b110) begin
                        uop.opcode = LSU_SW;
                        uop.fu = FU_ST;
                        uop.imm = {25'b0, i16.cs.imm[0], i16.cs.imm2, i16.cs.imm[1], 2'b00};
                        uop.rs0 = {2'b01, i16.cs.rd_rs1};
                        uop.rs1 = {2'b01, i16.cs.rs2};
                        invalidEnc = 0;
                    end
                    // c.addi4spn
                    else if (i16.ciw.funct3 == 3'b000 && i16.ciw.imm != 0) begin
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        uop.imm = {22'b0, i16.ciw.imm[5:2], i16.ciw.imm[7:6], i16.ciw.imm[0], i16.ciw.imm[1], 2'b00};
                        uop.rs0 = 2;
                        uop.immB = 1;
                        uop.rd = {2'b01, i16.ciw.rd};
                        invalidEnc = 0;
                    end
                end
                else if (i16.raw[1:0] == 2'b01) begin
                    // c.j
                    if (i16.cj.funct3 == 3'b101) begin
                        uop.opcode = INT_JAL;
                        uop.fu = FU_INT;
                        // certainly one of the encodings of all time
                        uop.imm = {{20{i16.cj.imm[10]}}, i16.cj.imm[10], i16.cj.imm[6], i16.cj.imm[8:7], i16.cj.imm[4], 
                            i16.cj.imm[5], i16.cj.imm[0], i16.cj.imm[9], i16.cj.imm[3:1], 1'b0};
                            
                        if (!IN_instrs[i].predTaken) begin
                            OUT_decBranchDst = IN_instrs[i].pc[30:0] + uop.imm[31:1];
                            OUT_decBranch = 1;
                            OUT_decBranchFetchID = IN_instrs[i].fetchID;
                        end
                        else
                            uop.valid = 0;
                        
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.jal
                    else if (i16.cj.funct3 == 3'b001) begin
                        uop.opcode = INT_JAL;
                        uop.fu = FU_INT;
                        uop.imm = {{20{i16.cj.imm[10]}}, i16.cj.imm[10], i16.cj.imm[6], i16.cj.imm[8:7], i16.cj.imm[4], 
                            i16.cj.imm[5], i16.cj.imm[0], i16.cj.imm[9], i16.cj.imm[3:1], 1'b0};
                        uop.immB = 1;
                        uop.rd = 1; // ra

                        RS_inValid = 1;
                        RS_inData = IN_instrs[i].pc + 1;
                        
                        if (!IN_instrs[i].predTaken) begin
                            OUT_decBranchDst = IN_instrs[i].pc[30:0] + uop.imm[31:1];
                            OUT_decBranch = 1;
                            OUT_decBranchFetchID = IN_instrs[i].fetchID;
                        end

                        invalidEnc = 0;
                    end
                    // c.beqz
                    else if (i16.cb.funct3 == 3'b110) begin
                        uop.opcode = INT_BEQ;
                        uop.fu = FU_INT;
                        uop.imm = {{23{i16.cb.imm2[2]}}, i16.cb.imm2[2], i16.cb.imm[4:3], 
                            i16.cb.imm[0], i16.cb.imm2[1:0], i16.cb.imm[2:1], 1'b0};
                        
                        uop.rs0 = {2'b01, i16.cb.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.bnez
                    else if (i16.cb.funct3 == 3'b111) begin
                        uop.opcode = INT_BNE;
                        uop.fu = FU_INT;
                        uop.imm = {{23{i16.cb.imm2[2]}}, i16.cb.imm2[2], i16.cb.imm[4:3], 
                            i16.cb.imm[0], i16.cb.imm2[1:0], i16.cb.imm[2:1], 1'b0};
                        
                        uop.rs0 = {2'b01, i16.cb.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.li
                    else if (i16.ci.funct3 == 3'b010 && !(i16.ci.rd_rs1 == 0)) begin
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        uop.imm = {{26{i16.ci.imm2}}, i16.ci.imm2, i16.ci.imm};
                        uop.immB = 1;
                        uop.rd = i16.ci.rd_rs1;
                        
                        // li rd, 0 is eliminated during rename
                        if (uop.imm == 0) begin
                            uop.fu = FU_RN;
                        end
                        
                        invalidEnc = 0;
                    end
                    // c.lui / c.addi16sp
                    else if (i16.ci.funct3 == 3'b011 && i16.ci.rd_rs1 != 0 && {i16.ci.imm2, i16.ci.imm} != 0) begin
                        uop.fu = FU_INT;
                        
                        if (i16.ci.rd_rs1 == 2) begin
                            uop.opcode = INT_ADD;
                            uop.rs0 = 2;
                            uop.imm = {{22{i16.ci.imm2}}, i16.ci.imm2, i16.ci.imm[2:1], 
                                i16.ci.imm[3], i16.ci.imm[0], i16.ci.imm[4], 4'b0};
                        end
                        else begin
                            uop.opcode = INT_LUI;
                            uop.imm = {{14{i16.ci.imm2}}, i16.ci.imm2, i16.ci.imm, 12'b0};
                        end
                        
                        uop.immB = 1;
                        uop.rd = i16.ci.rd_rs1;
                        invalidEnc = 0;
                    end
                    // c.addi
                    else if (i16.ci.funct3 == 3'b000 && !(i16.ci.rd_rs1 == 0)) begin
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        uop.imm = {{26{i16.ci.imm2}}, i16.ci.imm2, i16.ci.imm};
                        uop.immB = 1;
                        uop.rs0 = i16.ci.rd_rs1;
                        uop.rd = i16.ci.rd_rs1;
                        
                        invalidEnc = 0;
                    end
                    // c.srli
                    else if (i16.cb2.funct3 == 3'b100 && i16.cb2.funct2 == 2'b00 && !i16.cb2.imm2 && i16.cb2.imm[4:0] != 0) begin
                        uop.opcode = INT_SRL;
                        uop.fu = FU_INT;
                        uop.imm = {27'b0, i16.cb2.imm[4:0]};
                        uop.immB = 1;
                        uop.rs0 = {2'b01, i16.cb2.rd_rs1};
                        uop.rd = {2'b01, i16.cb2.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.srai
                    else if (i16.cb2.funct3 == 3'b100 && i16.cb2.funct2 == 2'b01 && !i16.cb2.imm2 && i16.cb2.imm[4:0] != 0) begin
                        uop.opcode = INT_SRA;
                        uop.fu = FU_INT;
                        uop.imm = {27'b0, i16.cb2.imm[4:0]};
                        uop.immB = 1;
                        uop.rs0 = {2'b01, i16.cb2.rd_rs1};
                        uop.rd = {2'b01, i16.cb2.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.andi
                    else if (i16.cb2.funct3 == 3'b100 && i16.cb2.funct2 == 2'b10) begin
                        uop.opcode = INT_AND;
                        uop.fu = FU_INT;
                        uop.imm = {{26{i16.cb2.imm2}}, i16.cb2.imm2, i16.cb2.imm[4:0]};
                        uop.immB = 1;
                        uop.rs0 = {2'b01, i16.cb2.rd_rs1};
                        uop.rd = {2'b01, i16.cb2.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.and / c.or / c.xor / c.sub
                    else if (i16.ca.funct6 == 6'b100011) begin
                        case (i16.ca.funct2)
                            2'b11: uop.opcode = INT_AND;
                            2'b10: uop.opcode = INT_OR;
                            2'b01: uop.opcode = INT_XOR;
                            2'b00: uop.opcode = INT_SUB;
                        endcase
                        uop.fu = FU_INT;
                        uop.rs0 = {2'b01, i16.ca.rd_rs1};
                        uop.rs1 = {2'b01, i16.ca.rs2};
                        uop.rd = {2'b01, i16.ca.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.nop
                    else if (i16.ci.funct3 == 3'b000 && i16.ci.imm2 == 1'b0 && i16.ci.rd_rs1 == 5'b0 && i16.ci.imm == 5'b0) begin
                        // don't execute nops
                        uop.valid = 0;
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        invalidEnc = 0;
                    end
                end
                else if (i16.raw[1:0] == 2'b10) begin
                    // c.lwsp
                    if (i16.ci.funct3 == 3'b010 && !(i16.ci.rd_rs1 == 0)) begin
                        uop.opcode = LSU_LW;
                        uop.fu = FU_LSU;
                        uop.imm = {24'b0, i16.ci.imm[1:0], i16.ci.imm2, i16.ci.imm[4:2], 2'b00};
                        uop.rs0 = 2; // sp
                        uop.rd = i16.ci.rd_rs1;
                        invalidEnc = 0;
                    end
                    // c.swsp
                    else if (i16.css.funct3 == 3'b110) begin
                        uop.opcode = LSU_SW;
                        uop.fu = FU_ST;
                        uop.imm = {24'b0, i16.css.imm[1:0], i16.css.imm[5:2], 2'b00};
                        uop.rs0 = 2; // sp
                        uop.rs1 = i16.css.rs2;
                        invalidEnc = 0;
                    end
                    // c.jr
                    else if (i16.cr.funct4 == 4'b1000 && !(i16.cr.rd_rs1 == 0 || i16.cr.rs2 != 0)) begin
                        uop.fu = FU_INT;
                        //uop.opcode = INT_JALR;
                        uop.rs0 = i16.cr.rd_rs1;
                        
                        // jr ra
                        if (i16.cr.rd_rs1 == 1 && RS_outValid) begin
                            RS_inPop = 1;
                            uop.opcode = INT_V_RET;
                            uop.imm = {RS_outData, 1'b0};
                            uop.immB = 1;
                            
                            OUT_decBranch = 1;
                            OUT_decBranchDst = RS_outData;
                            OUT_decBranchFetchID = uop.fetchID;
                        end
                        else begin
                            uop.opcode = INT_V_JR;
                            uop.imm = {IN_indirBranchTarget, 1'b0};
                            uop.immB = 1;
                            
                            OUT_decBranch = 1;
                            OUT_decBranchDst = IN_indirBranchTarget;
                            OUT_decBranchFetchID = uop.fetchID;
                        end
                        invalidEnc = 0;
                    end
                    // c.jalr
                    else if (i16.cr.funct4 == 4'b1001 && !(i16.cr.rd_rs1 == 0 || i16.cr.rs2 != 0)) begin
                        uop.opcode = INT_JALR;
                        uop.fu = FU_INT;
                        uop.rs0 = i16.cr.rd_rs1;
                        uop.rd = 1;
                        
                        invalidEnc = 0;
                    end
                    // c.slli
                    else if (i16.ci.funct3 == 3'b000 && !(i16.ci.rd_rs1 == 0) && !i16.ci.imm2 && i16.ci.imm[4:0] != 0) begin
                        uop.opcode = INT_SLL;
                        uop.fu = FU_INT;
                        uop.imm = {27'b0, i16.ci.imm[4:0]};
                        uop.immB = 1;
                        uop.rs0 = i16.ci.rd_rs1;
                        uop.rd = i16.ci.rd_rs1;
                        invalidEnc = 0;
                    end
                    // c.mv
                    else if (i16.cr.funct4 == 4'b1000 && i16.cr.rd_rs1 != 0 && i16.cr.rs2 != 0) begin
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        uop.rs1 = i16.cr.rs2;
                        uop.rd = i16.cr.rd_rs1;
                        invalidEnc = 0;
                    end
                    // c.add
                    else if (i16.cr.funct4 == 4'b1001 && i16.cr.rd_rs1 != 0 && i16.cr.rs2 != 0) begin
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        uop.rs0 = i16.cr.rd_rs1;
                        uop.rs1 = i16.cr.rs2;
                        uop.rd = i16.cr.rd_rs1;
                        invalidEnc = 0;
                    end
                    else if (i16.cr.funct4 == 4'b1001 && i16.cr.rd_rs1 == 0 && i16.cr.rs2 == 0) begin
                        uop.opcode = INT_SYS;
                        uop.fu = FU_INT;
                        uop.immB = 1;
                        uop.imm[2:0] = FLAGS_BRK;
                        invalidEnc = 0;
                    end
                end
            end
        end
        
        
        if (invalidEnc) begin
            uop.opcode = INT_UNDEFINED;
            uop.fu = FU_INT;
        end
        uopsComb[i] = uop;
    end
end

always@(posedge clk) begin
    if (rst || IN_invalidate) begin
        for (i = 0; i < NUM_UOPS; i=i+1)
            OUT_uop[i].valid <= 0;
    end
    else if (en) begin
        for (i = 0; i < NUM_UOPS; i=i+1)
            OUT_uop[i] <= uopsComb[i];
    end
end

endmodule
