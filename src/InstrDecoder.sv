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
`define OPC_ENV 7'b1110011
`define OPC_BITM 7'b0110011

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
    input wire en,
    input PD_Instr IN_instrs[NUM_UOPS-1:0],

    output D_UOp OUT_uop[NUM_UOPS-1:0]
);

integer i;

D_UOp uop;
reg invalidEnc;
Instr32 instr;
Instr16 instr16;

always_comb begin
    
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        
        instr = IN_instrs[i].instr;
        instr16 = IN_instrs[i].instr[15:0];
        
        uop = 97'b0;
        invalidEnc = 1;
        uop.pc = {IN_instrs[i].pc, 1'b0};
        uop.valid = IN_instrs[i].valid && en;
        uop.branchID = IN_instrs[i].branchID;
        uop.branchPred = IN_instrs[i].branchPred;
        
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
        
        
        // Regular Instructions
        if (instr.opcode[1:0] == 2'b11) begin
            case (instr.opcode)
                `OPC_ENV: begin
                    if (uop.imm == 0 || uop.imm == 1) begin
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

                    uop.fu = FU_LSU;
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
                default: invalidEnc = 1;
            endcase
        end
        // Compressed Instructions
        else begin
            uop.compressed = 1;
            if (instr16.raw[1:0] == 2'b00) begin
                // c.lw
                if (instr16.cl.funct3 == 3'b010) begin
                    uop.opcode = LSU_LW;
                    uop.fu = FU_LSU;
                    uop.imm = {25'b0, instr16.cl.imm[0], instr16.cl.imm2, instr16.cl.imm[1], 2'b00};
                    uop.rs0 = {2'b01, instr16.cl.rs1};
                    uop.rd = {2'b01, instr16.cl.rd};
                    invalidEnc = 0;
                end
                // c.sw
                else if (instr16.cs.funct3 == 3'b110) begin
                    uop.opcode = LSU_SW;
                    uop.fu = FU_LSU;
                    uop.imm = {25'b0, instr16.cs.imm[0], instr16.cs.imm2, instr16.cs.imm[1], 2'b00};
                    uop.rs0 = {2'b01, instr16.cs.rd_rs1};
                    uop.rs1 = {2'b01, instr16.cs.rs2};
                    invalidEnc = 0;
                end
                // c.addi4spn
                else if (instr16.ciw.funct3 == 3'b000 && instr16.ciw.imm != 0) begin
                    uop.opcode = INT_ADD;
                    uop.fu = FU_INT;
                    uop.imm = {22'b0, instr16.ciw.imm[5:2], instr16.ciw.imm[7:6], instr16.ciw.imm[0], instr16.ciw.imm[1], 2'b00};
                    uop.rs0 = 2;
                    uop.immB = 1;
                    uop.rd = {2'b01, instr16.ciw.rd};
                    invalidEnc = 0;
                end
            end
            else if (instr16.raw[1:0] == 2'b01) begin
                // c.j
                if (instr16.cj.funct3 == 3'b101) begin
                    uop.opcode = INT_JAL;
                    uop.fu = FU_INT;
                    // certainly one of the encodings of all time
                    uop.imm = {{20{instr16.cj.imm[10]}}, instr16.cj.imm[10], instr16.cj.imm[6], instr16.cj.imm[8:7], instr16.cj.imm[4], 
                        instr16.cj.imm[5], instr16.cj.imm[0], instr16.cj.imm[9], instr16.cj.imm[3:1], 1'b0};
                    uop.immB = 1;
                    invalidEnc = 0;
                end
                // c.jal
                else if (instr16.cj.funct3 == 3'b001) begin
                    uop.opcode = INT_JAL;
                    uop.fu = FU_INT;
                    uop.imm = {{20{instr16.cj.imm[10]}}, instr16.cj.imm[10], instr16.cj.imm[6], instr16.cj.imm[8:7], instr16.cj.imm[4], 
                        instr16.cj.imm[5], instr16.cj.imm[0], instr16.cj.imm[9], instr16.cj.imm[3:1], 1'b0};
                    uop.immB = 1;
                    uop.rd = 1; // ra
                    invalidEnc = 0;
                end
                // c.beqz
                else if (instr16.cb.funct3 == 3'b110) begin
                    uop.opcode = INT_BEQ;
                    uop.fu = FU_INT;
                    uop.imm = {{23{instr16.cb.imm2[2]}}, instr16.cb.imm2[2], instr16.cb.imm[4:3], 
                        instr16.cb.imm[0], instr16.cb.imm2[1:0], instr16.cb.imm[2:1], 1'b0};
                    
                    uop.rs0 = {2'b01, instr16.cb.rd_rs1};
                    invalidEnc = 0;
                end
                // c.bnez
                else if (instr16.cb.funct3 == 3'b111) begin
                    uop.opcode = INT_BNE;
                    uop.fu = FU_INT;
                    uop.imm = {{23{instr16.cb.imm2[2]}}, instr16.cb.imm2[2], instr16.cb.imm[4:3], 
                        instr16.cb.imm[0], instr16.cb.imm2[1:0], instr16.cb.imm[2:1], 1'b0};
                    
                    uop.rs0 = {2'b01, instr16.cb.rd_rs1};
                    invalidEnc = 0;
                end
                // c.li
                else if (instr16.ci.funct3 == 3'b010 && !(instr16.ci.rd_rs1 == 0)) begin
                    uop.opcode = INT_ADD;
                    uop.fu = FU_INT;
                    uop.imm = {{26{instr16.ci.imm2}}, instr16.ci.imm2, instr16.ci.imm};
                    uop.immB = 1;
                    uop.rd = instr16.ci.rd_rs1;
                    invalidEnc = 0;
                end
                // c.lui / c.addi16sp
                else if (instr16.ci.funct3 == 3'b011 && instr16.ci.rd_rs1 != 0 && {instr16.ci.imm2, instr16.ci.imm} != 0) begin
                    uop.fu = FU_INT;
                    
                    if (instr16.ci.rd_rs1 == 2) begin
                        uop.opcode = INT_ADD;
                        uop.rs0 = 2;
                        uop.imm = {{22{instr16.ci.imm2}}, instr16.ci.imm2, instr16.ci.imm[2:1], 
                            instr16.ci.imm[3], instr16.ci.imm[0], instr16.ci.imm[4], 4'b0};
                    end
                    else begin
                        uop.opcode = INT_LUI;
                        uop.imm = {{14{instr16.ci.imm2}}, instr16.ci.imm2, instr16.ci.imm, 12'b0};
                    end
                    
                    uop.immB = 1;
                    uop.rd = instr16.ci.rd_rs1;
                    invalidEnc = 0;
                end
                // c.addi
                else if (instr16.ci.funct3 == 3'b000 && !(instr16.ci.rd_rs1 == 0)) begin
                    uop.opcode = INT_ADD;
                    uop.fu = FU_INT;
                    uop.imm = {{26{instr16.ci.imm2}}, instr16.ci.imm2, instr16.ci.imm};
                    uop.immB = 1;
                    uop.rs0 = instr16.ci.rd_rs1;
                    uop.rd = instr16.ci.rd_rs1;
                    invalidEnc = 0;
                end
                // c.srli
                else if (instr16.cb2.funct3 == 3'b100 && instr16.cb2.funct2 == 2'b00 && !instr16.cb2.imm2 && instr16.cb2.imm[4:0] != 0) begin
                    uop.opcode = INT_SRL;
                    uop.fu = FU_INT;
                    uop.imm = {27'b0, instr16.cb2.imm[4:0]};
                    uop.immB = 1;
                    uop.rs0 = {2'b01, instr16.cb2.rd_rs1};
                    uop.rd = {2'b01, instr16.cb2.rd_rs1};
                    invalidEnc = 0;
                end
                // c.srai
                else if (instr16.cb2.funct3 == 3'b100 && instr16.cb2.funct2 == 2'b01 && !instr16.cb2.imm2 && instr16.cb2.imm[4:0] != 0) begin
                    uop.opcode = INT_SRA;
                    uop.fu = FU_INT;
                    uop.imm = {27'b0, instr16.cb2.imm[4:0]};
                    uop.immB = 1;
                    uop.rs0 = {2'b01, instr16.cb2.rd_rs1};
                    uop.rd = {2'b01, instr16.cb2.rd_rs1};
                    invalidEnc = 0;
                end
                // c.andi
                else if (instr16.cb2.funct3 == 3'b100 && instr16.cb2.funct2 == 2'b10) begin
                    uop.opcode = INT_AND;
                    uop.fu = FU_INT;
                    uop.imm = {{26{instr16.cb2.imm2}}, instr16.cb2.imm2, instr16.cb2.imm[4:0]};
                    uop.immB = 1;
                    uop.rs0 = {2'b01, instr16.cb2.rd_rs1};
                    uop.rd = {2'b01, instr16.cb2.rd_rs1};
                    invalidEnc = 0;
                end
                // c.and / c.or / c.xor / c.sub
                else if (instr16.ca.funct6 == 6'b100011) begin
                    case (instr16.ca.funct2)
                        2'b11: uop.opcode = INT_AND;
                        2'b10: uop.opcode = INT_OR;
                        2'b01: uop.opcode = INT_XOR;
                        2'b00: uop.opcode = INT_SUB;
                    endcase
                    uop.fu = FU_INT;
                    uop.rs0 = {2'b01, instr16.ca.rd_rs1};
                    uop.rs1 = {2'b01, instr16.ca.rs2};
                    uop.rd = {2'b01, instr16.ca.rd_rs1};
                    invalidEnc = 0;
                end
                // c.nop
                else if (instr16.ci.funct3 == 3'b000 && instr16.ci.imm2 == 1'b0 && instr16.ci.rd_rs1 == 5'b0 && instr16.ci.imm == 5'b0) begin
                    uop.opcode = INT_ADD;
                    uop.fu = FU_INT;
                    invalidEnc = 0;
                end
            end
            else if (instr16.raw[1:0] == 2'b10) begin
                // c.lwsp
                if (instr16.ci.funct3 == 3'b010 && !(instr16.ci.rd_rs1 == 0)) begin
                    uop.opcode = LSU_LW;
                    uop.fu = FU_LSU;
                    uop.imm = {24'b0, instr16.ci.imm[1:0], instr16.ci.imm2, instr16.ci.imm[4:2], 2'b00};
                    uop.rs0 = 2; // sp
                    uop.rd = instr16.ci.rd_rs1;
                    invalidEnc = 0;
                end
                // c.swsp
                else if (instr16.css.funct3 == 3'b110) begin
                    uop.opcode = LSU_SW;
                    uop.fu = FU_LSU;
                    uop.imm = {24'b0, instr16.css.imm[1:0], instr16.css.imm[5:2], 2'b00};
                    uop.rs0 = 2; // sp
                    uop.rs1 = instr16.css.rs2;
                    invalidEnc = 0;
                end
                // c.jr
                else if (instr16.cr.funct4 == 4'b1000 && !(instr16.cr.rd_rs1 == 0 || instr16.cr.rs2 != 0)) begin
                    uop.opcode = INT_JALR;
                    uop.fu = FU_INT;
                    //uop.immB = 1;
                    uop.rs0 = instr16.cr.rd_rs1;
                    invalidEnc = 0;
                end
                // c.jalr
                else if (instr16.cr.funct4 == 4'b1001 && !(instr16.cr.rd_rs1 == 0 || instr16.cr.rs2 != 0)) begin
                    uop.opcode = INT_JALR;
                    uop.fu = FU_INT;
                    uop.rs0 = instr16.cr.rd_rs1;
                    uop.rd = 1; // ra
                    //uop.immB = 1;
                    invalidEnc = 0;
                end
                // c.slli
                else if (instr16.ci.funct3 == 3'b000 && !(instr16.ci.rd_rs1 == 0) && !instr16.ci.imm2 && instr16.ci.imm[4:0] != 0) begin
                    uop.opcode = INT_SLL;
                    uop.fu = FU_INT;
                    uop.imm = {27'b0, instr16.ci.imm[4:0]};
                    uop.immB = 1;
                    uop.rs0 = instr16.ci.rd_rs1;
                    uop.rd = instr16.ci.rd_rs1;
                    invalidEnc = 0;
                end
                // c.mv
                else if (instr16.cr.funct4 == 4'b1000 && instr16.cr.rd_rs1 != 0 && instr16.cr.rs2 != 0) begin
                    uop.opcode = INT_ADD;
                    uop.fu = FU_INT;
                    uop.rs1 = instr16.cr.rs2;
                    uop.rd = instr16.cr.rd_rs1;
                    invalidEnc = 0;
                end
                // c.add
                else if (instr16.cr.funct4 == 4'b1001 && instr16.cr.rd_rs1 != 0 && instr16.cr.rs2 != 0) begin
                    uop.opcode = INT_ADD;
                    uop.fu = FU_INT;
                    uop.rs0 = instr16.cr.rd_rs1;
                    uop.rs1 = instr16.cr.rs2;
                    uop.rd = instr16.cr.rd_rs1;
                    invalidEnc = 0;
                end
                else if (instr16.cr.funct4 == 4'b1001 && instr16.cr.rd_rs1 == 0 && instr16.cr.rs2 == 0) begin
                    uop.opcode = INT_SYS;
                    uop.fu = FU_INT;
                    uop.immB = 1;
                    uop.imm = 1;
                    invalidEnc = 0;
                end
            end
        end
        
        
        if (invalidEnc) begin
            //uop = 97'bx;
            uop.opcode = INT_UNDEFINED;
            uop.fu = FU_INT;
        end
        OUT_uop[i] = uop;
    end
end

endmodule
