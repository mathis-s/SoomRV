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

typedef struct packed
{
    logic[6:0] funct7; 
    logic[4:0] rs1;
    logic[4:0] rs0;
    logic[2:0] funct3;
    logic[4:0] rd;
    logic[6:0] opcode;
} Instr32;

module InstrDecoder
#(
    parameter NUM_UOPS=2
)
(
    input wire[31:0] IN_instr[NUM_UOPS-1:0],
    input wire IN_instrValid[NUM_UOPS-1:0],
    input wire IN_branchPred[NUM_UOPS-1:0],
    input wire[3:0] IN_branchID[NUM_UOPS-1:0],

    input wire[31:0] IN_pc[NUM_UOPS-1:0],

    output D_UOp OUT_uop[NUM_UOPS-1:0]
);

integer i;

D_UOp uop;
reg invalidEnc;
Instr32 instr;

always_comb begin
    
    for (i = 0; i < NUM_UOPS; i=i+1) begin
        instr = IN_instr[i];
        // TODO write x to uop here?
        uop.pc = IN_pc[i];
        uop.valid = IN_instrValid[i];
        uop.branchID = IN_branchID[i];
        uop.branchPred = IN_branchPred[i];
        
        case (instr.opcode)
            `OPC_LUI,
            `OPC_AUIPC:      uop.imm = {instr[31:12], 12'b0};
            `OPC_JAL:        uop.imm = IN_pc[i] + $signed({{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}); // TODO: pc is only 31 bits, fix this later
            `OPC_ENV,
            `OPC_JALR,          
            `OPC_LOAD,
            `OPC_REG_IMM:    uop.imm = $signed({{20{instr[31]}}, instr[31:20]});
            `OPC_BRANCH:     uop.imm = IN_pc[i] + $signed({{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0});
            `OPC_STORE:    uop.imm = $signed({{20{instr[31]}}, instr[31:25], instr[11:7]});
            //`OPC_REG_REG,
            default:      uop.imm = 0;
        endcase

        case (instr.opcode)
            `OPC_ENV: begin
                uop.fu = FU_INT;
                uop.rs0 = 0;
                uop.rs1 = 0;
                uop.rd = 0;
                uop.opcode = INT_SYS;
                uop.immB = 1;
                uop.pcA = 1;
                invalidEnc = 0;
            end
            `OPC_LUI: begin
                uop.fu = FU_INT;
                uop.rs0 = 0;
                uop.rs1 = 0;
                uop.pcA = 0;
                uop.immB = 1;
                uop.rd = instr.rd;
                uop.opcode = INT_LUI;
                invalidEnc = 0;
            end
            `OPC_AUIPC: begin
                uop.fu = FU_INT;
                uop.rs0 = 0;
                uop.rs1 = 0;
                uop.pcA = 1;
                uop.immB = 1;
                uop.rd = instr.rd;
                uop.opcode = INT_AUIPC;
                invalidEnc = 0;
            end
            `OPC_JAL: begin
                uop.fu = FU_INT;
                uop.rs0 = 0;
                uop.rs1 = 0;
                uop.pcA = 1;
                uop.immB = 1;
                uop.rd = instr.rd;
                uop.opcode = INT_JAL;
                invalidEnc = 0;
            end
            `OPC_JALR: begin
                uop.fu = FU_INT;
                // (!) inverted rs0/rs1 here, to be able to pass
                // rs1, imm and pc in (resp.) srcB, imm, srcA
                uop.rs0 = 0;
                uop.rs1 = instr.rs0;
                uop.pcA = 1;
                uop.immB = 0;
                uop.rd = instr.rd;
                uop.opcode = INT_JALR; 
                invalidEnc = 0;
            end
            `OPC_LOAD: begin
                uop.rs0 = instr.rs0;
                uop.rs1 = 0;
                uop.pcA = 0;
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
                uop.pcA = 0;
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
                uop.pcA = 0;
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
                uop.pcA = 0;
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
            end
            `OPC_REG_REG: begin
                uop.rs0 = instr.rs0;
                uop.rs1 = instr.rs1;
                uop.pcA = 0;
                uop.immB = 0;
                uop.rd = instr.rd;
                if (instr.funct7 == 0) begin
                    invalidEnc = 0;
                    uop.fu = FU_INT;
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
                else
                    invalidEnc = 1;
            end
            default: invalidEnc = 1;
        endcase
        if (invalidEnc) begin
            uop.opcode = INT_UNDEFINED;
            uop.fu = FU_INT;
        end
        OUT_uop[i] = uop;
    end
end

endmodule
