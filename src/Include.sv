
typedef enum logic[5:0]
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

typedef enum logic[5:0]
{
    MUL_MUL,
    MUL_MULH,
    MUL_MULSU,
    MUL_MULU
} OPCode_MUL;

typedef enum logic[5:0]
{
    DIV_DIV,
    DIV_DIVU,
    DIV_REM,
    DIV_REMU
} OPCode_DIV;

typedef enum logic[5:0]
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

typedef enum logic[1:0] {FU_INT, FU_MUL, FU_DIV, FU_LSU} FuncUnit;

typedef struct packed
{
    logic[31:0] imm;
    logic[31:0] immPC;
    logic[5:0] rs0; 
    logic[5:0] rs1; 
    logic immB;
    logic[5:0] rd;
    logic[5:0] opcode;
    FuncUnit fu;
} D_UOp;

typedef struct packed
{
    logic[31:0] imm;
    logic[31:0] immPC;
    logic[31:0] srcA;
    logic[31:0] srcB;
    logic[5:0] rd;
    logic[5:0] opcode;
    FuncUnit fu;
} UOp;
