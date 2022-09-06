
typedef enum logic[5:0]
{
    INT_ADD,
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
    INT_BGEU,
    INT_LUI,
    INT_AUIPC,
    INT_JAL,
    INT_JALR,
    INT_SYS,
    INT_UNDEFINED,
    INT_SH1ADD,
    INT_SH2ADD,
    INT_SH3ADD,
    INT_XNOR,
    INT_ANDN,
    INT_ORN,
    INT_CLZ,
    INT_CTZ,
    INT_CPOP,
    INT_MAX,
    INT_MAXU,
    INT_MIN,
    INT_MINU,
    INT_SE_B,
    INT_SE_H,
    INT_ZE_H,
    INT_ROL,
    INT_ROR,
    INT_ORC_B,
    INT_REV8,
    INT_BCLR,
    INT_BEXT,
    INT_BINV,
    INT_BSET
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

typedef enum logic[1:0] {FU_INT, FU_LSU, FU_MUL, FU_DIV} FuncUnit;
typedef enum bit[0:0] {FLAGS_NONE, FLAGS_BRK} Flags;

typedef struct packed
{
    logic[31:0] imm;
    logic[31:0] pc;
    logic[4:0] rs0; 
    logic[4:0] rs1;
    logic pcA;
    // only useful when we otherwise need a duplicate opcode -> maybe rework some things
    logic immB;
    logic[4:0] rd;
    logic[5:0] opcode;
    FuncUnit fu;
    logic[5:0] branchID;
    logic branchPred;
    logic valid;
} D_UOp;

typedef struct packed
{
    logic[31:0] imm;
    logic[31:0] pc;
    // TODO: Keep some tags always reserved, use as special values for pc, imm, ...
    logic availA;
    logic[5:0] tagA;
    logic availB;
    logic[5:0] tagB;
    logic pcA;
    logic immB;
    logic[5:0] sqN;
    logic[5:0] tagDst;
    logic[4:0] nmDst;
    logic[5:0] opcode;
    logic[5:0] branchID;
    logic branchPred;
    logic[5:0] storeSqN;
    logic[5:0] loadSqN;
    FuncUnit fu;
} R_UOp;


typedef struct packed
{
    logic[31:0] imm;
    logic[31:0] srcA;
    logic availA;
    logic[5:0] tagA;
    logic[31:0] srcB;
    logic availB;
    logic[5:0] tagB;
    logic[5:0] sqN;
    logic[5:0] tagDst;
    logic[4:0] nmDst;
    logic[5:0] opcode;
    logic valid;
} UOp;

typedef struct packed
{
    logic[31:0] srcA;
    logic[31:0] srcB;
    logic[31:0] pc;
    logic[31:0] imm;
    logic[5:0] opcode;
    logic[5:0] tagDst;
    logic[4:0] nmDst;
    logic[5:0] sqN;
    logic[5:0] branchID;
    logic branchPred;
    logic[5:0] storeSqN;
    logic[5:0] loadSqN;
    logic valid;
} EX_UOp;

typedef struct packed
{
    bit[31:0] result;
    bit[5:0] tagDst;
    bit[4:0] nmDst;
    bit[5:0] sqN;
    bit[31:0] pc;
    Flags flags;
    bit valid;
} RES_UOp;


typedef struct packed
{
    bit taken;
    bit[31:0] dstPC;
    bit[5:0] sqN;
    bit[5:0] storeSqN;
    bit[5:0] loadSqN;
    
} BranchProv;

typedef struct packed
{
    logic[31:0] addr;
    logic[31:0] data;
    logic[4:0] cacheAddr;
    logic[31:0] pc;
    logic[5:0] opcode;
    logic[5:0] tagDst;
    logic[4:0] nmDst;
    logic[5:0] sqN;
    logic[5:0] branchID;
    logic branchPred;
    logic[5:0] storeSqN;
    logic[5:0] loadSqN;
    logic valid;
} LSU_UOp;

