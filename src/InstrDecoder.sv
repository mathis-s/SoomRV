
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

`define OPC_ATOMIC 7'b0101111

`define OPC_CUST0 7'b0001011
`define OPC_CUST1 7'b0001011

typedef struct packed
{
    logic[6:0] funct7;
    logic[4:0] rs2;
    logic[4:0] rs1;
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
    parameter NUM_UOPS=`DEC_WIDTH,
    parameter DO_FUSE=0,
    parameter FUSE_LUI=0,
    parameter FUSE_STORE_DATA=0
)
(
    input wire clk,
    input wire rst,
    input wire en,
    input BranchProv IN_branch,

    input DecodeState IN_dec,
    input PD_Instr IN_instrs[NUM_UOPS-1:0],

    input wire IN_enCustom,

    output D_UOp OUT_uop[NUM_UOPS-1:0]
);


D_UOp uop;
reg invalidEnc;
Instr32 instr;
Instr16 i16;
I32 i32;

D_UOp uopsComb[NUM_UOPS-1:0];

always_comb begin

    for (integer i = 0; i < NUM_UOPS; i=i+1) begin

        instr = IN_instrs[i].instr;
        i32 = IN_instrs[i].instr;
        i16 = IN_instrs[i].instr[15:0];

        uop = 0;
        invalidEnc = 1;
        //uop.pc = {IN_instrs[i].pc, 1'b0};
        uop.valid = IN_instrs[i].valid && en;
        uop.fetchID = IN_instrs[i].fetchID;
        uop.fetchOffs = IN_instrs[i].pc[$bits(FetchOff_t)-1:0] + (instr.opcode[1:0] == 2'b11 ? 1 : 0);

        case (instr.opcode)
            `OPC_LUI,
            `OPC_AUIPC:      uop.imm = {instr[31:12], 12'b0};
            `OPC_JAL:        uop.imm = $signed({{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0});
            `OPC_ENV,
            `OPC_JALR,
            `OPC_LOAD,
            `OPC_REG_IMM:    uop.imm = $signed({{20{instr[31]}}, instr[31:20]});
            `OPC_BRANCH:     uop.imm = $signed({{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0});
            `OPC_CUST0,
            `OPC_STORE:    uop.imm = $signed({{20{instr[31]}}, instr[31:25], instr[11:7]});
            //`OPC_REG_REG,
            default:      uop.imm = 0;
        endcase

        if (IN_instrs[i].valid && en) begin

            reg isWFI = 0;

            if (IN_instrs[i].predInvalid) begin
                // A branch was predicted that is impossible considering actual instruction boundaries
                assert(IN_instrs[i].predTaken);
            end
            else if (IN_instrs[i].fetchFault != IF_FAULT_NONE) begin

                uop.fu = FU_TRAP;
                invalidEnc = 0;

                case (IN_instrs[i].fetchFault)
                    IF_INTERRUPT: uop.opcode = TRAP_V_INTERRUPT;
                    IF_ACCESS_FAULT: uop.opcode = TRAP_I_ACC_FAULT;
                    IF_PAGE_FAULT: uop.opcode = TRAP_I_PAGE_FAULT;
                    default: assert(0);
                endcase

                uop.compressed = IN_instrs[i].is16bit;
            end
            // Regular Instructions
            else if (instr.opcode[1:0] == 2'b11) begin
                case (instr.opcode)
                    `OPC_ENV: begin
                        case (instr.funct3)
                            0: begin
                                if ((uop.imm == 0 || uop.imm == 1) && instr.rs1 == 0 && instr.rd == 0) begin
                                    case (uop.imm)
                                        0: uop.opcode = TRAP_ECALL_M;
                                        1: uop.opcode = TRAP_BREAK;
                                    endcase
                                    uop.fu = FU_TRAP;
                                    uop.rs1 = 0;
                                    uop.rs2 = 0;
                                    uop.rd = 0;
                                    uop.immB = 1;
                                    isWFI = 1;
                                    invalidEnc = 0;
                                end
                                else if (instr.rs2 == 5'b00010 && instr.rs1 == 0 && instr.rd == 0) begin
                                    if (instr.funct7 == 7'b0001000) begin
                                        uop.fu = FU_CSR;
                                        uop.opcode = CSR_SRET;
                                        invalidEnc = 0;
                                        isWFI = 1;
                                    end
                                    else if (instr.funct7 == 7'b0011000) begin
                                        uop.fu = FU_CSR;
                                        uop.opcode = CSR_MRET;
                                        invalidEnc = 0;
                                        isWFI = 1;
                                    end
                                end
                                else if (instr.funct7 == 7'b0001000 && instr.rs2 == 5'b00101 && instr.rs1 == 0 && instr.rd == 0) begin
                                    if (IN_dec.allowWFI) begin
                                        // WFI
                                        uop.fu = FU_RN;
                                        invalidEnc = 0;
                                        isWFI = 1;
                                    end
                                end
                                else if (instr.funct7 == 7'b0001001 && instr.rd == 0) begin
                                    uop.fu = FU_TRAP;
                                    uop.opcode = TRAP_V_SFENCE_VMA;
                                    invalidEnc = 0;
                                end
                                else if (instr.funct7 == 7'b0001011 && instr.rd == 0) begin
                                    // sinval.vma
                                    uop.rs1 = instr.rs1;
                                    uop.rs2 = instr.rs2;
                                    //invalidEnc = 0;
                                end
                                else if (instr.funct7 == 7'b0001100 && instr.rs2 == 0 && instr.rs1 == 0 && instr.rd == 0) begin
                                    // sfence.w.inval
                                    //invalidEnc = 0;
                                end
                                else if (instr.funct7 == 7'b0001100 && instr.rs2 == 5'b1 && instr.rs1 == 0 && instr.rd == 0) begin
                                    // sfence.inval.ir
                                    //invalidEnc = 0;
                                end
                            end

                            1: begin // csrrw
                                uop.fu = FU_CSR;
                                uop.rs1 = instr.rs1;
                                uop.rd = instr.rd;
                                uop.opcode = CSR_RW;
                                uop.imm = {20'bx, instr[31:20]};
                                invalidEnc = 0;
                            end

                            2: begin // csrrs
                                uop.fu = FU_CSR;
                                uop.rs1 = instr.rs1;
                                uop.rd = instr.rd;
                                uop.opcode = (instr.rs1 == 0) ? CSR_R : CSR_RS;
                                uop.imm = {20'bx, instr[31:20]};
                                invalidEnc = 0;
                            end

                            3: begin // csrrc
                                uop.fu = FU_CSR;
                                uop.rs1 = instr.rs1;
                                uop.rd = instr.rd;
                                uop.opcode = (instr.rs1 == 0) ? CSR_R : CSR_RC;
                                uop.imm = {20'bx, instr[31:20]};
                                invalidEnc = 0;
                            end

                            5: begin // csrrwi
                                uop.fu = FU_CSR;
                                uop.rd = instr.rd;
                                uop.opcode = CSR_RW_I;
                                uop.imm = {15'bx, instr.rs1, instr[31:20]};
                                invalidEnc = 0;
                            end

                            6: begin // csrrsi
                                uop.fu = FU_CSR;
                                uop.rd = instr.rd;
                                uop.opcode = (instr.rs1 == 0) ? CSR_R : CSR_RS_I;
                                uop.imm = {15'bx, instr.rs1, instr[31:20]};
                                invalidEnc = 0;
                            end

                            7: begin // csrrci
                                uop.fu = FU_CSR;
                                uop.rd = instr.rd;
                                uop.opcode = (instr.rs1 == 0) ? CSR_R : CSR_RC_I;
                                uop.imm = {15'bx, instr.rs1, instr[31:20]};
                                invalidEnc = 0;
                            end

                        endcase
                    end
                    `OPC_LUI: begin
                        uop.fu = FU_INT;
                        uop.rs1 = 0;
                        uop.rs2 = 0;
                        uop.immB = 1;
                        uop.rd = instr.rd;
                        uop.opcode = INT_LUI;
                        invalidEnc = 0;
                    end
                    `OPC_AUIPC: begin
                        uop.fu = FU_INT;
                        uop.rs1 = 0;
                        uop.rs2 = 0;
                        uop.rd = instr.rd;
                        uop.opcode = INT_AUIPC;
                        invalidEnc = 0;
                    end
                    `OPC_JAL: begin
                        uop.fu = FU_INT;
                        uop.rs1 = 0;
                        uop.rs2 = 0;
                        uop.immB = 1;
                        uop.rd = instr.rd;
                        uop.opcode = INT_JAL;
                        invalidEnc = 0;

                        // No need to execute jumps that don't write to a register
                        if (uop.rd == 0) uop.fu = FU_RN;
                    end
                    `OPC_JALR: begin
                        uop.fu = FU_INT;
                        uop.rs1 = instr.rs1;
                        uop.immB = 1;
                        uop.rd = instr.rd;
                        // actual RISC-V instr immediate is encoded in imm12
                        uop.imm12 = instr[31:20];

                        unique casez ({instr.rd==1 || instr.rd==5, instr.rs1==1 || instr.rs1==5, instr.rd==instr.rs1})
                            3'b00?: uop.opcode = INT_V_JR;
                            3'b01?: uop.opcode = INT_V_RET;
                            3'b10?: uop.opcode = INT_V_JALR;
                            3'b110: uop.opcode = INT_V_JR;
                            3'b111: uop.opcode = INT_V_JALR;
                        endcase

                        // the regular imm field is used to pass the speculated
                        // destination (for the ALU to check)
                        if (IN_instrs[i].predTaken)
                            uop.imm = {IN_instrs[i].predTarget, 1'b0};
                        else
                            uop.imm = {(IN_instrs[i].pc + (uop.compressed ? 31'd1 : 31'd2)), 1'b0};

                        invalidEnc = 0;
                    end
                    `OPC_LOAD: begin
                        uop.rs1 = instr.rs1;
                        uop.rs2 = 0;
                        uop.immB = 1;
                        uop.rd = instr.rd;

                        uop.fu = FU_AGU;
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
                        uop.rs1 = instr.rs1;
                        uop.rs2 = instr.rs2;
                        uop.immB = 1;
                        uop.rd = 0;
                        uop.fu = FU_AGU;
                        invalidEnc = 0;
                        case (instr.funct3)
                            0: uop.opcode = LSU_SB;
                            1: uop.opcode = LSU_SH;
                            2: uop.opcode = LSU_SW;
                            default: invalidEnc = 1;
                        endcase
                    end
                    `OPC_CUST0: if (IN_dec.allowCustom) begin
                        if (instr.funct3 == 3'b011 && instr.funct7[6:3] == 0) begin
                            uop.rs1 = instr.rs1;
                            uop.rs2 = instr.rs2;
                            uop.rd = instr.rd;
                            uop.fu = FU_AGU;
                            uop.imm = 0;
                            invalidEnc = 0;
                            case (instr.funct7[2:0])
                                0: uop.opcode = LSU_LB;
                                1: uop.opcode = LSU_LH;
                                2: uop.opcode = LSU_LW;
                                4: uop.opcode = LSU_LBU;
                                5: uop.opcode = LSU_LHU;
                                default: invalidEnc = 1;
                            endcase
                        end
                        else begin
                            uop.rs1 = instr.rs1;
                            uop.rs2 = instr.rs2;
                            uop.rd = instr.rs1;
                            uop.immB = 1;
                            uop.fu = FU_AGU;
                            invalidEnc = 0;
                            case (instr.funct3)
                                0: uop.opcode = LSU_SB_PREINC;
                                1: uop.opcode = LSU_SH_PREINC;
                                2: uop.opcode = LSU_SW_PREINC;

                                4: uop.opcode = LSU_SB_POSTINC;
                                5: uop.opcode = LSU_SH_POSTINC;
                                6: uop.opcode = LSU_SW_POSTINC;
                                default: invalidEnc = 1;
                            endcase
                        end
                    end
                    `OPC_BRANCH: begin
                        uop.rs1 = instr.rs1;
                        uop.rs2 = instr.rs2;
                        uop.immB = 0;
                        uop.rd = 0;
                        uop.fu = FU_INT;

                        invalidEnc = (uop.opcode == 2) || (uop.opcode == 3);

                        case (instr.funct3)
                            0: uop.opcode = INT_BEQ;
                            1: uop.opcode = INT_BNE;
                            4: uop.opcode = INT_BLT;
                            5: uop.opcode = INT_BGE;
                            6: uop.opcode = INT_BLTU;
                            7: uop.opcode = INT_BGEU;
                        endcase
                    end
                    `OPC_FENCE: begin
                        if (instr.funct3 == 0) begin
                            uop.fu = FU_RN;
                            //uop.opcode = INT_SYS;
                            //uop.imm = {28'bx, FLAGS_FENCE};
                            invalidEnc = 0;
                        end
                        else if (instr.funct3 == 1) begin
                            uop.fu = FU_INT;
                            uop.opcode = INT_SYS;
                            uop.imm = {28'bx, FLAGS_FENCE};
                            invalidEnc = 0;
                        end
                        // cbo.inval -> runs as store op, invalidates to instruction after itself
                        else if (instr.funct3 == 3'b010 && instr.rd == 0 && instr[31:20] == 0) begin
                            invalidEnc = 0;
                            uop.opcode = LSU_CBO_INVAL;
                            uop.fu = FU_AGU;
                            uop.rs1 = instr.rs1;
                            uop.rs2 = 0;
                        end
                        // cbo.clean -> runs as store op
                        else if (instr.funct3 == 3'b010 && instr.rd == 0 && instr[31:20] == 1) begin
                            invalidEnc = 0;
                            uop.opcode = LSU_CBO_CLEAN;
                            uop.fu = FU_AGU;
                            uop.rs1 = instr.rs1;
                            uop.rs2 = 0;
                        end
                        // cbo.flush -> runs as store op, invalidates to instruction after itself
                        else if (instr.funct3 == 3'b010 && instr.rd == 0 && instr[31:20] == 2) begin
                            invalidEnc = 0;
                            uop.opcode = LSU_CBO_FLUSH;
                            uop.fu = FU_AGU;
                            uop.rs1 = instr.rs1;
                            uop.rs2 = 0;
                        end
                    end
                    `OPC_REG_IMM: begin
                        uop.rs1 = instr.rs1;
                        uop.rs2 = 0;
                        uop.immB = 1;
                        uop.rd = instr.rd;
                        uop.fu = FU_INT;

                        if (!((instr.funct3 == 1 && instr.funct7 != 0) ||
                                    (instr.funct3 == 5 && (instr.funct7 != 7'h20 && instr.funct7 != 0)))) begin
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

                            invalidEnc = 0;
                        end
                        else if (instr.funct7 == 7'b0110000) begin
                            if (instr.funct3 == 3'b001) begin
                                if (instr.rs2 == 5'b00000) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_CLZ;
                                end
                                else if (instr.rs2 == 5'b00001) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_CTZ;
                                end
                                else if (instr.rs2 == 5'b00010) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_CPOP;
                                end
                                else if (instr.rs2 == 5'b00100) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_SE_B;
                                end
                                else if (instr.rs2 == 5'b00101) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_SE_H;
                                end
                                else if (instr.rs2 == 5'b00101) begin
                                    invalidEnc = 0;
                                    uop.opcode = INT_ZE_H;
                                end
                            end
                            else if (instr.funct3 == 3'b101) begin
                                invalidEnc = 0;
                                uop.opcode = INT_ROR;
                                uop.imm = {27'b0, instr.rs2};
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
                                uop.imm = {27'b0, instr.rs2};
                            end
                            else if (instr.funct3 == 3'b101) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BEXT;
                                uop.imm = {27'b0, instr.rs2};
                            end
                        end
                        else if (instr.funct7 == 7'b0110100) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BINV;
                                uop.imm = {27'b0, instr.rs2};
                            end
                        end
                        else if (instr.funct7 == 7'b0010100) begin
                            if (instr.funct3 == 3'b001) begin
                                //invalidEnc = 0;
                                uop.opcode = INT_BSET;
                                uop.imm = {27'b0, instr.rs2};
                            end
                        end

                        // li rd, 0 is eliminated during rename
                        if (uop.fu == FU_INT && uop.opcode == INT_ADD && uop.rs1 == 0 &&
                            uop.imm[11] == uop.imm[10] &&
                            uop.imm[11] == uop.imm[9] &&
                            uop.imm[11] == uop.imm[8] &&
                            uop.imm[11] == uop.imm[7] &&
                            uop.imm[11] == uop.imm[6] &&
                            uop.imm[11] == uop.imm[5]) begin
                            uop.fu = FU_RN;
                        end
                    end
                    `OPC_REG_REG: begin
                        uop.rs1 = instr.rs1;
                        uop.rs2 = instr.rs2;
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

                            `ifndef ENABLE_INT_DIV
                                if (uop.fu == FU_DIV) invalidEnc = 1;
                            `endif
                            `ifndef ENABLE_INT_MUL
                                if (uop.fu == FU_MUL) invalidEnc = 1;
                            `endif
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
                        else if (instr.funct7 == 7'b0000100 && instr.rs2 == 0 && instr.funct3 == 3'b100) begin
                            // NOTE: differenct encoding in rv64!
                            invalidEnc = 0;
                            uop.rs2 = 0;
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
                        /*else if (IN_enCustom && instr.funct7 == 7'b1000000) begin

                            invalidEnc = 0;

                            uop.fu = FU_AGU;
                            case (instr.funct3)
                                0: uop.opcode = LSU_LB_RR;
                                1: uop.opcode = LSU_LH_RR;
                                2: uop.opcode = LSU_LW_RR;
                                4: uop.opcode = LSU_LBU_RR;
                                5: uop.opcode = LSU_LHU_RR;
                                6: invalidEnc = 1;
                                7: invalidEnc = 1;
                            endcase
                        end*/
                    end

                    /*`OPC_FLW: begin
                        if (i32.flw.width == 3'b010) begin
                            uop.fu = FU_AGU;
                            uop.opcode = LSU_FLW;
                            uop.rs1 = i32.flw.rs1;
                            uop.rd = i32.flw.rd;
                            uop.rd_fp = 1;
                            uop.imm = {{20{i32.flw.offset[11]}}, i32.flw.offset[11:0]};
                            invalidEnc = 0;
                        end
                    end
                    `OPC_FSW: begin
                        if (i32.fsw.width == 3'b010) begin
                            uop.fu = FU_AGU;
                            uop.opcode = LSU_FSW;
                            uop.rs1 = i32.fsw.rs1;
                            uop.rs2 = i32.fsw.rs2;
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
                            uop.rs1 = i32.fma.rs1;
                            uop.rs0_fp = 1;
                            uop.rs2 = i32.fma.rs2;
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
                            uop.rs1 = i32.fma.rs1;
                            uop.rs0_fp = 1;
                            uop.rs2 = i32.fma.rs2;
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
                            uop.rs1 = i32.fma.rs1;
                            uop.rs0_fp = 1;
                            uop.rs2 = i32.fma.rs2;
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
                            uop.rs1 = i32.fma.rs1;
                            uop.rs0_fp = 1;
                            uop.rs2 = i32.fma.rs2;
                            uop.rs1_fp = 1;
                            uop.rs2 = i32.fma.rs3;
                            uop.rd = i32.fma.rd;
                            uop.rd_fp = 1;
                            invalidEnc = 0;
                        end
                    end*/
`ifdef ENABLE_FP
                    `OPC_FP: begin
                        // single precision
                        if (i32.fp.fmt == 2'b00) begin

                            uop.fu = FU_FPU;
                            uop.rs1 = i32.fp.rs1;
                            //uop.rs0_fp = 1;
                            uop.rs2 = i32.fp.rs2;
                            //uop.rs1_fp = 1;
                            uop.rd = i32.fp.rd;
                            // uop.rd_fp = 1;
                            invalidEnc = 0;

                            case (i32.fp.funct5)

                                5'b00000: begin
                                    uop.opcode = {i32.fp.rm, FPU_FADD_S};
                                    invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                end
                                5'b00001: begin
                                    uop.opcode = {i32.fp.rm, FPU_FSUB_S};
                                    invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                end
                                5'b00010: begin
                                    uop.opcode = {i32.fp.rm, FMUL_FMUL_S};
                                    invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                    uop.fu = FU_FMUL;
                                end
                                5'b00011: begin
                                    uop.opcode = {i32.fp.rm, FDIV_FDIV_S};
                                    invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                    uop.fu = FU_FDIV;
                                end
                                5'b01011: begin
                                    uop.opcode = {i32.fp.rm, FDIV_FSQRT_S};
                                    invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                    uop.rs2 = 0;
                                    uop.fu = FU_FDIV;
                                    if (i32.fp.rs2 != 0) invalidEnc = 1;
                                end
                                5'b00100: begin
                                    uop.fu = FU_INT;

                                    if (i32.fp.rm == 3'b000)
                                        uop.opcode = INT_FSGNJ_S;
                                    else if (i32.fp.rm == 3'b001)
                                        uop.opcode = INT_FSGNJN_S;
                                    else if (i32.fp.rm == 3'b010)
                                        uop.opcode = INT_FSGNJX_S;
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
                                    uop.rs2 = 0;
                                    if (i32.fp.rs2 == 5'b00000) begin
                                        uop.opcode = {i32.fp.rm, FPU_FCVTWS};
                                        invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                    end
                                    else if (i32.fp.rs2 == 5'b00001) begin
                                        uop.opcode = {i32.fp.rm, FPU_FCVTWUS};
                                        invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                    end
                                    else invalidEnc = 1;
                                end
                                5'b11100: begin
                                    /*if (i32.fp.rs2 == 5'b00000 && i32.fp.rm == 3'b000) begin
                                        uop.opcode = FPU_FMVXW;
                                        uop.fu = FU_INT;
                                    end
                                    else*/ if (i32.fp.rs2 == 5'b00000 && i32.fp.rm == 3'b001) begin
                                        uop.opcode = FPU_FCLASS_S;
                                    end
                                    else invalidEnc = 1;
                                end
                                5'b10100: begin
                                    if (i32.fp.rm == 3'b010)
                                        uop.opcode = FPU_FEQ_S;
                                    else if (i32.fp.rm == 3'b001)
                                        uop.opcode = FPU_FLT_S;
                                    else if (i32.fp.rm == 3'b000)
                                        uop.opcode = FPU_FLE_S;
                                    else invalidEnc = 1;
                                end
                                5'b11010: begin

                                    if (i32.fp.rs2 == 5'b00000) begin
                                        uop.opcode = {i32.fp.rm, FPU_FCVTSW};
                                        invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                    end
                                    else if (i32.fp.rs2 == 5'b00001) begin
                                        uop.opcode = {i32.fp.rm, FPU_FCVTSWU};
                                        invalidEnc = (i32.fp.rm >= 3'b101) && (i32.fp.rm != 3'b111);
                                    end
                                    else invalidEnc = 1;
                                end
                                5'b11110: begin

                                    /*if (i32.fp.rs2 == 0 && i32.fp.rm == 0) begin
                                        uop.opcode = FPU_FMVWX;
                                        uop.fu = FU_INT;
                                    end
                                    else*/ invalidEnc = 1;
                                end
                                default: invalidEnc = 1;
                            endcase
                        end
                    end
`endif // ENABLE_FP
                    `OPC_ATOMIC: begin
                        if (instr.funct3 == 3'b010) begin

                            uop.rd = instr.rd;
                            uop.rs1 = instr.rs1;
                            uop.rs2 = instr.rs2;
                            uop.fu = FU_ATOMIC;

                            case (instr.funct7[6:2])
                                5'b00010: begin // lr.w
                                    if (instr.rs2 == 5'b0) begin
                                        uop.opcode = LSU_LR_W;
                                        uop.fu = FU_AGU;
                                        uop.immB = 0;
                                        uop.rs2 = 0;
                                        invalidEnc = 0;
                                    end
                                end
                                5'b00011: begin // sc.w
                                    uop.opcode = LSU_SC_W;
                                    uop.fu = FU_AGU;
                                    uop.immB = 1;
                                    invalidEnc = 0;
                                end
                                5'b00001: begin // amoswap.w
                                    uop.opcode = ATOMIC_AMOSWAP_W;
                                    invalidEnc = 0;
                                end
                                5'b00000: begin // amoadd.w
                                    uop.opcode = ATOMIC_AMOADD_W;
                                    invalidEnc = 0;
                                end
                                5'b00100: begin // amoxor.w
                                    uop.opcode = ATOMIC_AMOXOR_W;
                                    invalidEnc = 0;
                                end
                                5'b01100: begin // amoand.w
                                    uop.opcode = ATOMIC_AMOAND_W;
                                    invalidEnc = 0;
                                end
                                5'b01000: begin // amoor.w
                                    uop.opcode = ATOMIC_AMOOR_W;
                                    invalidEnc = 0;
                                end
                                5'b10000: begin // amomin.w
                                    uop.opcode = ATOMIC_AMOMIN_W;
                                    invalidEnc = 0;
                                end
                                5'b10100: begin // amomax.w
                                    uop.opcode = ATOMIC_AMOMAX_W;
                                    invalidEnc = 0;
                                end
                                5'b11000: begin // amominu.w
                                    uop.opcode = ATOMIC_AMOMINU_W;
                                    invalidEnc = 0;
                                end
                                5'b11100: begin // amomaxu.w
                                    uop.opcode = ATOMIC_AMOMAXU_W;
                                    invalidEnc = 0;
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
                        uop.fu = FU_AGU;
                        uop.imm = {25'b0, i16.cl.imm[0], i16.cl.imm2, i16.cl.imm[1], 2'b00};
                        uop.rs1 = {2'b01, i16.cl.rs1};
                        uop.rd = {2'b01, i16.cl.rd};
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.sw
                    else if (i16.cs.funct3 == 3'b110) begin
                        uop.opcode = LSU_SW;
                        uop.fu = FU_AGU;
                        uop.imm = {25'b0, i16.cs.imm[0], i16.cs.imm2, i16.cs.imm[1], 2'b00};
                        uop.rs1 = {2'b01, i16.cs.rd_rs1};
                        uop.rs2 = {2'b01, i16.cs.rs2};
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.addi4spn
                    else if (i16.ciw.funct3 == 3'b000 && i16.ciw.imm != 0) begin
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        uop.imm = {22'b0, i16.ciw.imm[5:2], i16.ciw.imm[7:6], i16.ciw.imm[0], i16.ciw.imm[1], 2'b00};
                        uop.rs1 = 2;
                        uop.immB = 1;
                        uop.rd = {2'b01, i16.ciw.rd};
                        invalidEnc = 0;
                    end
                    `ifdef ENABLE_ZCB
                    // c.lbu
                    else if (i16.ciw.funct3 == 3'b100 && i16.raw[12:10] == 3'b000) begin
                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rs2 = 0;
                        uop.immB = 1;
                        uop.imm = {30'b0, i16.raw[5], i16.raw[6]};
                        uop.rd = {2'b01, i16.raw[4:2]};
                        uop.fu = FU_AGU;
                        uop.opcode = LSU_LBU;
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.lhu
                    else if (i16.ciw.funct3 == 3'b100 && i16.raw[12:10] == 3'b001 && i16.raw[6] == 0) begin
                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rs2 = 0;
                        uop.immB = 1;
                        uop.imm = {30'b0, i16.raw[5], 1'b0};
                        uop.rd = {2'b01, i16.raw[4:2]};
                        uop.fu = FU_AGU;
                        uop.opcode = LSU_LHU;
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.lh
                    else if (i16.ciw.funct3 == 3'b100 && i16.raw[12:10] == 3'b001 && i16.raw[6] == 1) begin
                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rs2 = 0;
                        uop.immB = 1;
                        uop.imm = {30'b0, i16.raw[5], 1'b0};
                        uop.rd = {2'b01, i16.raw[4:2]};
                        uop.fu = FU_AGU;
                        uop.opcode = LSU_LH;
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.sb
                    else if (i16.ciw.funct3 == 3'b100 && i16.raw[12:10] == 3'b010) begin
                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rs2 = {2'b01, i16.raw[4:2]};
                        uop.imm = {30'b0, i16.raw[5], i16.raw[6]};
                        uop.immB = 0;
                        uop.rd = 0;
                        uop.fu = FU_AGU;
                        uop.opcode = LSU_SB;
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    `endif
                    // c.sw with preinc
                    else if (i16.ciw.funct3 == 3'b101 && IN_dec.allowCustom) begin
                        uop.opcode = LSU_SW_PREINC;
                        uop.fu = FU_AGU;
                        uop.imm = {25'b0, i16.cs.imm[0], i16.cs.imm2, i16.cs.imm[1], 2'b00};
                        uop.rs1 = {2'b01, i16.cs.rd_rs1};
                        uop.rs2 = {2'b01, i16.cs.rs2};
                        uop.rd = {2'b01, i16.cs.rd_rs1};
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.sw with postinc
                    else if (i16.ciw.funct3 == 3'b111 && IN_dec.allowCustom) begin
                        uop.opcode = LSU_SW_POSTINC;
                        uop.fu = FU_AGU;
                        uop.imm = {25'b0, i16.cs.imm[0], i16.cs.imm2, i16.cs.imm[1], 2'b00};
                        uop.rs1 = {2'b01, i16.cs.rd_rs1};
                        uop.rs2 = {2'b01, i16.cs.rs2};
                        uop.rd = {2'b01, i16.cs.rd_rs1};
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.lw with full-range address register
                    else if (i16.cl.funct3 == 3'b011 && {i16.raw[12], i16.raw[5]} != 2'b01 && IN_dec.allowCustom) begin
                        uop.opcode = LSU_LW;
                        uop.fu = FU_AGU;
                        uop.imm = {27'b0, i16.cl.imm2[1:0], i16.cl.imm[1], 2'b00};
                        uop.rs1 = {i16.raw[12], i16.raw[5], i16.cl.rs1};
                        uop.rd = {2'b01, i16.cl.rd};
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.lw r8 r8(r8)
                    else if (i16.cl.funct3 == 3'b001 && IN_dec.allowCustom) begin
                        uop.fu = FU_AGU;
                        uop.rs2 = {2'b01, i16.raw[12:10]};
                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rd =  {2'b01, i16.raw[4:2]};
                        invalidEnc = 0;
                        case (i16.raw[6:5])
                            0: uop.opcode = LSU_LB;
                            1: uop.opcode = LSU_LH;
                            2: uop.opcode = LSU_LW;
                            default: invalidEnc = 1;
                        endcase
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

                        uop.fu = FU_RN;

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
                        invalidEnc = 0;
                    end
                    // c.beqz
                    else if (i16.cb.funct3 == 3'b110) begin
                        uop.opcode = INT_BEQ;
                        uop.fu = FU_INT;
                        uop.imm = {{23{i16.cb.imm2[2]}}, i16.cb.imm2[2], i16.cb.imm[4:3],
                            i16.cb.imm[0], i16.cb.imm2[1:0], i16.cb.imm[2:1], 1'b0};

                        uop.rs1 = {2'b01, i16.cb.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.bnez
                    else if (i16.cb.funct3 == 3'b111) begin
                        uop.opcode = INT_BNE;
                        uop.fu = FU_INT;
                        uop.imm = {{23{i16.cb.imm2[2]}}, i16.cb.imm2[2], i16.cb.imm[4:3],
                            i16.cb.imm[0], i16.cb.imm2[1:0], i16.cb.imm[2:1], 1'b0};

                        uop.rs1 = {2'b01, i16.cb.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.li
                    else if (i16.ci.funct3 == 3'b010 && !(i16.ci.rd_rs1 == 0)) begin
                        uop.fu = FU_RN; // eliminated during rename
                        uop.imm = {{26{i16.ci.imm2}}, i16.ci.imm2, i16.ci.imm};
                        uop.immB = 1;
                        uop.rd = i16.ci.rd_rs1;
                        invalidEnc = 0;
                    end
                    // c.lui / c.addi16sp
                    else if (i16.ci.funct3 == 3'b011 && i16.ci.rd_rs1 != 0 && {i16.ci.imm2, i16.ci.imm} != 0) begin
                        uop.fu = FU_INT;

                        if (i16.ci.rd_rs1 == 2) begin
                            uop.opcode = INT_ADD;
                            uop.rs1 = 2;
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
                        uop.rs1 = i16.ci.rd_rs1;
                        uop.rd = i16.ci.rd_rs1;

                        invalidEnc = 0;
                    end
                    // c.srli
                    else if (i16.cb2.funct3 == 3'b100 && i16.cb2.funct2 == 2'b00 && !i16.cb2.imm2 && i16.cb2.imm[4:0] != 0) begin
                        uop.opcode = INT_SRL;
                        uop.fu = FU_INT;
                        uop.imm = {27'b0, i16.cb2.imm[4:0]};
                        uop.immB = 1;
                        uop.rs1 = {2'b01, i16.cb2.rd_rs1};
                        uop.rd = {2'b01, i16.cb2.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.srai
                    else if (i16.cb2.funct3 == 3'b100 && i16.cb2.funct2 == 2'b01 && !i16.cb2.imm2 && i16.cb2.imm[4:0] != 0) begin
                        uop.opcode = INT_SRA;
                        uop.fu = FU_INT;
                        uop.imm = {27'b0, i16.cb2.imm[4:0]};
                        uop.immB = 1;
                        uop.rs1 = {2'b01, i16.cb2.rd_rs1};
                        uop.rd = {2'b01, i16.cb2.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.andi
                    else if (i16.cb2.funct3 == 3'b100 && i16.cb2.funct2 == 2'b10) begin
                        uop.opcode = INT_AND;
                        uop.fu = FU_INT;
                        uop.imm = {{26{i16.cb2.imm2}}, i16.cb2.imm2, i16.cb2.imm[4:0]};
                        uop.immB = 1;
                        uop.rs1 = {2'b01, i16.cb2.rd_rs1};
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
                        uop.rs1 = {2'b01, i16.ca.rd_rs1};
                        uop.rs2 = {2'b01, i16.ca.rs2};
                        uop.rd = {2'b01, i16.ca.rd_rs1};
                        invalidEnc = 0;
                    end
                    // c.nop
                    else if (i16.ci.funct3 == 3'b000 && i16.ci.imm2 == 1'b0 && i16.ci.rd_rs1 == 5'b0 && i16.ci.imm == 5'b0) begin
                        uop.fu = FU_RN;
                        invalidEnc = 0;
                    end
                    `ifdef ENABLE_ZCB
                    // c.zext.b
                    else if (i16.raw[15:13] == 3'b100 && i16.raw[12:10] == 3'b111 && i16.raw[6:5] == 2'b11 && i16.raw[4:2] == 3'b000) begin

                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rd = {2'b01, i16.raw[9:7]};

                        uop.fu = FU_INT;
                        uop.opcode = INT_AND;
                        uop.immB = 1;
                        uop.imm = 32'h000000FF;
                        invalidEnc = 0;
                    end
                    // c.sext.b
                    else if (i16.raw[15:13] == 3'b100 && i16.raw[12:10] == 3'b111 && i16.raw[6:5] == 2'b11 && i16.raw[4:2] == 3'b001) begin

                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rd = {2'b01, i16.raw[9:7]};

                        uop.fu = FU_INT;
                        uop.opcode = INT_SE_B;
                        uop.immB = 0;
                        invalidEnc = 0;
                    end
                    // c.zext.h
                    else if (i16.raw[15:13] == 3'b100 && i16.raw[12:10] == 3'b111 && i16.raw[6:5] == 2'b11 && i16.raw[4:2] == 3'b010) begin

                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rd = {2'b01, i16.raw[9:7]};

                        uop.fu = FU_INT;
                        uop.opcode = INT_ZE_H;
                        uop.immB = 0;
                        invalidEnc = 0;
                    end
                    // c.sext.h
                    else if (i16.raw[15:13] == 3'b100 && i16.raw[12:10] == 3'b111 && i16.raw[6:5] == 2'b11 && i16.raw[4:2] == 3'b011) begin

                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rd = {2'b01, i16.raw[9:7]};

                        uop.fu = FU_INT;
                        uop.opcode = INT_SE_H;
                        uop.immB = 0;
                        invalidEnc = 0;
                    end
                    // c.not
                    else if (i16.raw[15:13] == 3'b100 && i16.raw[12:10] == 3'b111 && i16.raw[6:5] == 2'b11 && i16.raw[4:2] == 3'b101) begin

                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rd = {2'b01, i16.raw[9:7]};

                        uop.fu = FU_INT;
                        uop.opcode = INT_XNOR;
                        uop.immB = 1;
                        uop.imm = 0;
                        invalidEnc = 0;
                    end
                    `ifdef ENABLE_INT_MUL
                    // c.mul
                    else if (i16.raw[15:13] == 3'b100 && i16.raw[12:10] == 3'b111 && i16.raw[6:5] == 2'b10) begin
                        uop.rs2 = {2'b01, i16.raw[4:2]};
                        uop.rs1 = {2'b01, i16.raw[9:7]};
                        uop.rd = {2'b01, i16.raw[9:7]};

                        uop.fu = FU_MUL;
                        uop.opcode = MUL_MUL;
                        uop.immB = 0;
                        invalidEnc = 0;
                    end
                    `endif
                    `endif
                end
                else if (i16.raw[1:0] == 2'b10) begin
                    // c.lwsp
                    if (i16.ci.funct3 == 3'b010 && !(i16.ci.rd_rs1 == 0)) begin
                        uop.opcode = LSU_LW;
                        uop.fu = FU_AGU;
                        uop.imm = {24'b0, i16.ci.imm[1:0], i16.ci.imm2, i16.ci.imm[4:2], 2'b00};
                        uop.rs1 = 2; // sp
                        uop.rd = i16.ci.rd_rs1;
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.swsp
                    else if (i16.css.funct3 == 3'b110) begin
                        uop.opcode = LSU_SW;
                        uop.fu = FU_AGU;
                        uop.imm = {24'b0, i16.css.imm[1:0], i16.css.imm[5:2], 2'b00};
                        uop.rs1 = 2; // sp
                        uop.rs2 = i16.css.rs2;
                        uop.immB = 1;
                        invalidEnc = 0;
                    end
                    // c.jr
                    else if (i16.cr.funct4 == 4'b1000 && !(i16.cr.rd_rs1 == 0 || i16.cr.rs2 != 0)) begin
                        uop.fu = FU_INT;
                        uop.rs1 = i16.cr.rd_rs1;

                        uop.opcode = (i16.cr.rd_rs1 == 1) ? INT_V_RET : INT_V_JR;
                        uop.immB = 1;
                        uop.imm12 = 0;

                        if (IN_instrs[i].predTaken)
                            uop.imm = {IN_instrs[i].predTarget, 1'b0};
                        else
                            uop.imm = {(IN_instrs[i].pc + (uop.compressed ? 31'd1 : 31'd2)), 1'b0};

                        invalidEnc = 0;
                    end
                    // c.jalr
                    else if (i16.cr.funct4 == 4'b1001 && !(i16.cr.rd_rs1 == 0 || i16.cr.rs2 != 0)) begin
                        uop.fu = FU_INT;
                        uop.rs1 = i16.cr.rd_rs1;
                        uop.rd = 1;

                        uop.opcode = INT_V_JALR;
                        uop.immB = 1;
                        uop.imm12 = 0;

                        if (IN_instrs[i].predTaken)
                            uop.imm = {IN_instrs[i].predTarget, 1'b0};
                        else
                            uop.imm = {(IN_instrs[i].pc + (uop.compressed ? 31'd1 : 31'd2)), 1'b0};

                        invalidEnc = 0;
                    end
                    // c.slli
                    else if (i16.ci.funct3 == 3'b000 && !(i16.ci.rd_rs1 == 0) && !i16.ci.imm2 && i16.ci.imm[4:0] != 0) begin
                        uop.opcode = INT_SLL;
                        uop.fu = FU_INT;
                        uop.imm = {27'b0, i16.ci.imm[4:0]};
                        uop.immB = 1;
                        uop.rs1 = i16.ci.rd_rs1;
                        uop.rd = i16.ci.rd_rs1;
                        invalidEnc = 0;
                    end
                    // c.mv
                    else if (i16.cr.funct4 == 4'b1000 && i16.cr.rd_rs1 != 0 && i16.cr.rs2 != 0) begin
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        uop.rs2 = i16.cr.rs2;
                        uop.rd = i16.cr.rd_rs1;
                        invalidEnc = 0;
                    end
                    // c.add
                    else if (i16.cr.funct4 == 4'b1001 && i16.cr.rd_rs1 != 0 && i16.cr.rs2 != 0) begin
                        uop.opcode = INT_ADD;
                        uop.fu = FU_INT;
                        uop.rs1 = i16.cr.rd_rs1;
                        uop.rs2 = i16.cr.rs2;
                        uop.rd = i16.cr.rd_rs1;
                        invalidEnc = 0;
                    end
                    else if (i16.cr.funct4 == 4'b1001 && i16.cr.rd_rs1 == 0 && i16.cr.rs2 == 0) begin
                        uop.opcode = TRAP_BREAK;
                        uop.fu = FU_TRAP;
                        invalidEnc = 0;
                    end
                end
            end
        end

        if (invalidEnc) begin
            uop.opcode = TRAP_ILLEGAL_INSTR;
            uop.fu = FU_TRAP;
        end
        uopsComb[i] = uop;
    end
end

always_ff@(posedge clk) begin

    if (rst || IN_branch.taken) begin
        for (integer i = 0; i < NUM_UOPS; i=i+1) begin
            OUT_uop[i] <= 'x;
            OUT_uop[i].valid <= 0;
        end
    end
    else if (en) begin
        for (integer i = 0; i < NUM_UOPS; i=i+1) begin
            OUT_uop[i] <= uopsComb[i];
        end
    end
end

endmodule
