`timescale 1 ns / 10 ps

`define OPC_LUI 7'b0110111
`define OPC_AUIPC 7'b0010111
`define OPC_JAL 7'b1101111
`define OPC_JALR 7'b1100111
`define OPC_LOAD 7'b0000011
`define OPC_STORE 7'b0100011
`define OPC_BRANCH 7'b1100011
`define OPC_REG_IMM 7'b0010011
`define OPC_REG_REG 7'b0110011

typedef enum
{
    INT_ADD = 0,
    INT_XOR,
    INT_OR,
    INT_AND,
    INT_SLL,
    INT_SRL,
    INT_SLT,
    INT_SLTU,
    INT_SUB,
    INT_SRA,
    INT_BEQ,
    INT_BNE,
    INT_BLT,
    INT_BGE,
    INT_BLTU,
    INT_BGEU
} OPCode_INT;

typedef enum
{
    MUL_MUL,
    MUL_MULH,
    MUL_MULSU,
    MUL_MULU
} OPCode_MUL;

typedef enum
{
    DIV_DIV,
    DIV_DIVU,
    DIV_REM,
    DIV_REMU
} OPCode_DIV;

typedef enum
{
    LSU_LB, 
    LSU_LH, 
    LSU_LW, 
    LSU_LBU,
    LSU_LHU,
    LSU_SB,
    LSU_SH,
    LSU_SW
} OPCode_LSU;

typedef enum {FU_INT, FU_MUL, FU_DIV, FU_LSU} FuncUnit;

typedef struct packed
{
    logic[31:0] imm;
    logic[31:0] immPC;
    logic[5:0] srcA; 
    logic[5:0] srcB; 
    logic immB;
    logic[5:0] dst;
    logic[5:0] opcode;
} UOp;

typedef struct packed
{
    logic[6:0] funct7; 
    logic[4:0] rs2;
    logic[4:0] rs1;
    logic[2:0] funct3;
    logic[4:0] rd;
    logic[6:0] opcode;
} Instr32;

module Decoder
(
    input wire clk,
    input wire[31:0] IN_instr,
    input wire[31:0] IN_pc,

    output UOp OUT_uop,
    output reg[2:0] OUT_idFU,
    output reg OUT_invalid
);


UOp uop;
FuncUnit idFU;

reg invalidEnc;
Instr32 instr;

always@(*) begin

    instr = IN_instr;

    case (instr.opcode)
        `OPC_LUI,
        `OPC_AUIPC:      uop.imm = {instr[31:12], 12'b0};
        `OPC_JAL:        uop.imm = $signed({instr[31], instr[19:12], instr[20], instr[30:21], 1'b0});
        `OPC_JALR,          
        `OPC_LOAD,
        `OPC_REG_IMM:    uop.imm = $signed({instr[31:20]});
        `OPC_BRANCH:     uop.imm = $signed({instr[31], instr[7], instr[30:25], instr[11:8], 1'b0});
        `OPC_REG_REG:    uop.imm = $signed({instr[31:25], instr[11:7]});
        `OPC_STORE:      uop.imm = 0;
    endcase

    uop.immPC = IN_pc;

    case (instr.opcode)
        `OPC_LUI: begin
            idFU = FU_INT;
            uop.srcA = 0;
            uop.srcB = 0;
            uop.immB = 1;
            uop.dst = instr.rd;
            uop.opcode = 0;
            invalidEnc = 0;
        end
        `OPC_AUIPC: begin
            idFU = FU_INT;
            uop.srcA = 0;
            uop.srcB = 0;
            uop.immB = 1;
            uop.dst = instr.rd;
            uop.opcode = 0;
            invalidEnc = 0;
        end
        `OPC_JAL: begin
            idFU = FU_INT;
            uop.srcA = 0;
            uop.srcB = 0;
            uop.immB = 1;
            uop.dst = instr.rd;
            uop.opcode = 0;
            invalidEnc = 0;
        end
        `OPC_JALR: begin
            idFU = FU_INT;
            uop.srcA = instr.rs1;
            uop.srcB = 0;
            uop.immB = 1;
            uop.dst = instr.rd;
            uop.opcode = 0; 
            invalidEnc = 0;
        end
        `OPC_LOAD: begin
            uop.srcA = instr.rs1;
            uop.srcB = 0;
            uop.immB = 1;
            uop.dst = instr.rd;

            idFU = FU_LSU;
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
            uop.srcA = instr.rs1;
            uop.srcB = instr.rs2;
            uop.immB = 0;
            uop.dst = 0;

            idFU = FU_LSU;
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
            uop.srcA = instr.rs1;
            uop.srcB = instr.rs2;
            uop.immB = 0;
            uop.dst = 0;
            
            idFU = FU_INT;
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
        `OPC_REG_IMM: begin
            uop.srcA = instr.rs1;
            uop.srcB = 0;
            uop.immB = 1;
            uop.dst = instr.rd;
            
            invalidEnc = (instr.funct3 == 1 && instr.funct7 != 0) || 
                         (instr.funct3 == 5 && (instr.funct7 != 7'h20 && instr.funct7 != 0));
            idFU = FU_INT;
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
        end
        `OPC_REG_REG: begin
            uop.srcA = instr.rs1;
            uop.srcB = instr.rs2;
            uop.immB = 0;
            uop.dst = instr.rd;
            if (instr.funct7 == 0) begin
                invalidEnc = 0;
                idFU = FU_INT;
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

                if (instr.funct3 < 4) idFU = FU_MUL;
                else idFU = FU_DIV;

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
                idFU = FU_INT;
                case (instr.funct3)
                    0: uop.opcode = INT_SUB;
                    5: uop.opcode = INT_SRA;
                endcase
            end
            else
                invalidEnc = 1;
        end
        default: invalidEnc = 1;
    endcase
end

always_ff@(posedge clk) begin
    $display("Instr: %h | INV: %h | SRCA: %h | SRCB: %h | IMMB: %b | DST: %h | OPC: %h | FU: %x | IMM: %x", instr, invalidEnc, uop.srcA, uop.srcB, uop.immB, uop.dst, uop.opcode, idFU, uop.imm);
    OUT_uop <= uop;
    OUT_idFU <= idFU;
    OUT_invalid <= invalidEnc;
end

endmodule