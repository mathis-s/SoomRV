typedef enum logic[2:0]
{
    MEMC_NONE,
    MEMC_CP_CACHE_TO_EXT,
    MEMC_CP_EXT_TO_CACHE,
    MEMC_PAGE_WALK,
    MEMC_READ_SINGLE,
    MEMC_WRITE_SINGLE
} MemCCmd;

typedef struct packed
{
    MemCCmd cmd;
    logic[9:0] sramAddr;
    logic[29:0] extAddr;
    logic[0:0] cacheID;
    logic[2:0] rqID;
} CTRL_MemC;

typedef struct packed
{
    logic[9:0] progress;
    
    logic[31:0] result;
    logic resultValid;
    
    logic[2:0] rqID;
    logic busy;
} STAT_MemC;

typedef logic[4:0] RegNm;
typedef logic[6:0] Tag;
typedef logic[`ROB_SIZE_EXP:0] SqN;
typedef logic[11:0] BrID;
typedef logic[4:0] FetchID_t;
typedef logic[2:0] FetchOff_t;
typedef logic[11:0] BHist_t;
typedef logic[2:0] TageUseful_t;
typedef logic[1:0] RetStackIdx_t;

typedef struct packed
{
    logic[30:0] addr;
    RetStackIdx_t idx;
    logic isCall;
    logic isRet;
    logic compr;
    logic cleanRet;
    logic valid;
} ReturnDecUpd;

typedef struct packed
{
    logic[30:0] dst;
    FetchOff_t offs;
    logic compr;
    logic isJump;
    logic valid;
} PredBranch;

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
    INT_BSET,
    //INT_MV,
    INT_FSGNJ_S,
    INT_FSGNJN_S,
    INT_FSGNJX_S,
    
    INT_V_RET,
    INT_V_JALR,
    INT_V_JR
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
    
    LSU_LR_W
    //LSU_LB_RR, 
    //LSU_LH_RR, 
    //LSU_LW_RR, 
    //LSU_LBU_RR,
    //LSU_LHU_RR
    
} OPCode_LSU;

typedef enum logic[5:0]
{
    LSU_SB,
    LSU_SH,
    LSU_SW,
    
    LSU_CBO_CLEAN,
    LSU_CBO_INVAL,
    LSU_CBO_FLUSH,
    
    LSU_F_ADDI_SW,
    
    LSU_SB_I,
    LSU_SH_I,
    LSU_SW_I,
    
    LSU_SC_W
    
} OPCode_ST;

typedef enum logic[2:0]
{
    // These instructions have an RM field
    // For these, the rounding mode is encoded in the upper 3 opcode bits
    //FPU_FMADD_S,
    //FPU_FMSUB_S,
    //FPU_FNMSUB_S,
    //FPU_FNMADD_S,
    FPU_FADD_S,
    FPU_FSUB_S,
    FPU_FCVTWS,
    FPU_FCVTWUS,
    FPU_FCVTSW,
    FPU_FCVTSWU
    
} OPCode_FPU;

typedef enum logic[5:0]
{
    // These don't
    // For these, the upper 3 opcode bits are 'b101
    //FPU_FMVXW,
    //FPU_FMVWX,
    FPU_FEQ_S = 6'b101000,
    FPU_FLE_S,
    FPU_FLT_S,
    FPU_FMIN_S,
    FPU_FMAX_S,
    FPU_FCLASS_S
    
} OPCode_FPU2;


typedef enum logic[2:0]
{
    FDIV_FDIV_S,
    FDIV_FSQRT_S
} OPCode_FDIV;

typedef enum logic[2:0]
{
    FMUL_FMUL_S
} OPCode_FMUL;

typedef enum logic[5:0]
{
    ATOMIC_AMOSWAP_W=32,
    ATOMIC_AMOADD_W,
    ATOMIC_AMOXOR_W,
    ATOMIC_AMOAND_W,
    ATOMIC_AMOOR_W,
    ATOMIC_AMOMIN_W,
    ATOMIC_AMOMAX_W,
    ATOMIC_AMOMINU_W,
    ATOMIC_AMOMAXU_W
    
} OPCode_FU_ATOMIC;

typedef enum logic[5:0]
{
    CSR_R,
    CSR_RW,
    CSR_RS,
    CSR_RC,
    
    CSR_RW_I,
    CSR_RS_I,
    CSR_RC_I,
    
    CSR_SRET,
    CSR_MRET
    
} OPCode_FU_CSR;

// For decode-time traps, we use FLAGS_TRAP/FU_TRAP as an,
// escape flag. The (unused) rd field then stores on of these fields
// to specify the decode-time exception encountered.

// All other exceptions are passed as result flags from
// functional units to the ROB.
typedef enum logic[5:0]
{
    // These are regular traps in RISC-V mcause encoding
    TRAP_I_ACC_MISAL = 0,
    TRAP_I_ACC_FAULT = 1,
    TRAP_ILLEGAL_INSTR = 2,
    TRAP_BREAK = 3,
    TRAP_ECALL_U = 8,
    TRAP_ECALL_S = 9,
    TRAP_ECALL_M = 11,
    TRAP_I_PAGE_FAULT = 12,
    
    // These are not (regular) traps
    TRAP_V_SFENCE_VMA = 15,
    TRAP_V_INTERRUPT = 16
    
} OPCode_FU_TRAP;

typedef enum logic[3:0] {FU_INT, FU_LD, FU_ST, FU_MUL, FU_DIV, FU_FPU, FU_FDIV, FU_FMUL, FU_RN, FU_ATOMIC, FU_CSR, FU_TRAP} FuncUnit;

typedef enum bit[3:0] 
{
    // Flags that do not cause a flush or trap
    FLAGS_NONE, FLAGS_BRANCH,
    
    // Exceptions that require PC lookup (all following)
    FLAGS_PRED_TAKEN, FLAGS_PRED_NTAKEN, 
    
    // Flags that cause a flush
    FLAGS_FENCE, FLAGS_ORDERING,
    
    // Flags that cause a trap
    FLAGS_ILLEGAL_INSTR, FLAGS_TRAP, 
    
    // Memory Exceptions
    FLAGS_LD_MA, FLAGS_LD_AF, FLAGS_LD_PF,
    FLAGS_ST_MA, FLAGS_ST_AF, FLAGS_ST_PF,
    
    // Return from exception
    FLAGS_XRET,
    
    // Invalid (or not-yet-executed) flag
    FLAGS_NX = 4'b1111
    
} Flags;

// Floating Point Ops use a different flag encoding to store
// floating point exceptions
typedef enum bit[3:0] 
{
    FLAGS_FP_NX = FLAGS_LD_MA, 
    FLAGS_FP_UF = FLAGS_LD_AF, 
    FLAGS_FP_OF = FLAGS_LD_PF, 
    FLAGS_FP_DZ = FLAGS_ST_MA, 
    FLAGS_FP_NV = FLAGS_ST_AF 

} FlagsFP;

typedef enum logic[2:0]
{
    MODE_USER,
    MODE_WMASK,
    MODE_RMASK,
    MODE_NO_CREGS_RD,
    MODE_NO_CREGS_WR,
    MODE_TMR,
    MODE_NO_BRK,
    MODE_NO_EXT
} ModeFlagsIDs;

typedef enum logic[1:0] 
{
    PRIV_USER=0, PRIV_SUPERVISOR=1, PRIV_MACHINE=3
} PrivLevel;

typedef logic[7:0] ModeFlags;

typedef enum logic[1:0]
{
    IF_FAULT_NONE = 0, IF_INTERRUPT, IF_ACCESS_FAULT, IF_PAGE_FAULT
} IFetchFault;

typedef struct packed
{
    bit predicted;
    bit taken;
    bit[2:0] tageID;
    bit altPred;
    RetStackIdx_t rIdx;
    bit isJump;
} BranchPredInfo;

typedef struct packed
{
    bit[31:0] src;
    bit[31:0] dst;
    bit isJump;
    bit isCall;
    bit compressed;
    bit clean;
    bit valid;
} BTUpdate;

typedef struct packed
{
    bit[30:0] src;
    bit[30:0] dst;
    bit valid;
} IndirBranchInfo;

typedef struct packed
{
    bit[31:0] dstPC;
    SqN sqN;
    SqN storeSqN;
    SqN loadSqN;
    bit flush;
    FetchID_t fetchID;
    BHist_t history;
    RetStackIdx_t rIdx;
    bit taken;
} BranchProv;

typedef struct packed
{
    logic[30:0] dst;
    logic[4:0] fetchID;
    BHist_t history;
    RetStackIdx_t rIdx;
    logic taken;
} DecodeBranchProv;

typedef struct packed
{
    bit[30:0] pc;
    bit[2:0] branchPos;
    BranchPredInfo bpi;
    BHist_t hist;
} PCFileEntry;

typedef struct packed
{
    logic[27:0] pc;
    FetchID_t fetchID;
    IFetchFault fetchFault;
    logic[2:0] firstValid;
    logic[2:0] lastValid;
    logic[2:0] predPos;
    logic predTaken;
    logic[30:0] predTarget;
    BHist_t history;
    RetStackIdx_t rIdx;
    logic[7:0][15:0] instrs;
    
    logic valid;
} IF_Instr;

typedef struct packed
{
    logic[31:0] instr;
    logic[30:0] pc;
    logic[30:0] predTarget;
    BHist_t history;
    RetStackIdx_t rIdx;
    logic predTaken;
    logic predInvalid;
    FetchID_t fetchID;
    IFetchFault fetchFault;
    logic is16bit;
    logic valid;
} PD_Instr;

typedef struct packed
{
    logic[31:0] imm;
    logic[4:0] rs0;
    logic[4:0] rs1;
    logic immB;
    logic[4:0] rd;
    logic[5:0] opcode;
    FuncUnit fu;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    logic compressed;
    logic valid;
} D_UOp;

typedef struct packed
{
    logic[31:0] imm;
    logic availA;
    Tag tagA;
    logic availB;
    Tag tagB;
    logic immB;
    Tag tagC; // only used in store port (for atomics), optimized out otherwise
    SqN sqN;
    Tag tagDst;
    RegNm nmDst;
    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
} R_UOp;

typedef struct packed
{
    logic[31:0] imm;
    logic availA;
    Tag tagA;
    logic availB;
    Tag tagB;
    logic immB;
    Tag tagC; // only used in store port (for atomics), optimized out otherwise
    SqN sqN;
    Tag tagDst;
    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
} IS_UOp;


typedef struct packed
{
    logic[31:0] srcA;
    logic[31:0] srcB;
    logic[31:0] srcC; // only used in store port (for atomics), optimized out otherwise
    logic[31:0] pc;
    logic[31:0] imm;
    logic[5:0] opcode;
    Tag tagDst;
    SqN sqN;
    FetchID_t fetchID;
    BranchPredInfo bpi;
    BHist_t history;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic valid;
} EX_UOp;

typedef struct packed
{
    bit[31:0] result;
    Tag tagDst;
    SqN sqN;
    Flags flags;
    logic doNotCommit;
    bit valid;
} RES_UOp;

typedef enum logic[1:0] 
{
    AGU_NO_EXCEPTION,
    AGU_ADDR_MISALIGN,
    AGU_ACCESS_FAULT,
    AGU_PAGE_FAULT
} AGU_Exception;

typedef struct packed
{
    logic[31:0] addr;
    logic[31:0] data;
    // could union some of these fields
    logic[3:0] wmask;
    logic signExtend;
    logic[1:0] size;
    logic isLoad;
    logic[31:0] pc;
    Tag tagDst;
    SqN sqN;
    SqN storeSqN;
    SqN loadSqN;
    FetchID_t fetchID;
    BHist_t history;
    RetStackIdx_t rIdx;
    logic doNotCommit;
    AGU_Exception exception;
    logic compressed;
    logic valid;
} AGU_UOp;

typedef struct packed
{
    logic[31:0] addr;
    logic[21:0] rootPPN;
    
    logic supervUserMemory;
    logic makeExecReadable;
    PrivLevel priv;
    
    logic valid;
} PageWalkRq;

typedef struct packed
{
    logic[19:0] vpn;
    logic[21:0] ppn;
    logic pageFault;
    logic isSuperPage;
    logic[2:0] rwx;
    logic[1:0] rqID;
    logic valid;
    logic busy;
} PageWalkRes;

typedef struct packed
{
    logic[31:0] addr;
    logic valid;
} PW_LD_UOp;

typedef struct packed
{
    logic[31:0] data;
    logic valid;
} PW_LD_RES_UOp;

typedef struct packed
{
    logic[31:0] addr;
    logic signExtend;
    logic[1:0] size;
    Tag tagDst;
    SqN sqN;
    logic doNotCommit;
    logic external; // not part of normal execution, ignore sqn, tagDst and nmDst, don't commit
    AGU_Exception exception;
    logic isMMIO;
    logic valid;
} LD_UOp;

typedef struct packed
{
    logic[31:0] addr;
    logic[31:0] data;
    logic[3:0] wmask;
    logic isMMIO;
    logic valid;
} ST_UOp;

typedef struct packed
{
    RegNm nmDst;
    Tag tagDst;
    SqN sqN;
    logic isBranch;
    logic branchTaken;
    logic compressed;
    logic valid;
} CommitUOp;

typedef struct packed
{
    bit allowInterrupt;
    Flags flags;
    Tag tag;
    SqN sqN;
    RegNm name;
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    bit compressed;
    bit valid;
    
} Trap_UOp;

typedef struct packed
{
    logic[30:0] pc;
    logic compressed;
    BranchPredInfo bpi;
    BHist_t history;
    logic branchTaken;
    logic valid;
} BPUpdate;

typedef struct packed
{
    logic[31:0] result;
    Tag tag;
    logic valid;
} ZCForward;

typedef struct packed
{
    logic[30:0] retvec;
    logic[29:0] mtvec;
    logic mvectord;
    logic[29:0] stvec;
    logic svectord;
    logic[15:0] medeleg;
    logic[15:0] mideleg;
    PrivLevel priv;
    
    logic interruptPending;
    logic[3:0] interruptCause;
    logic interruptDelegate;
    
} TrapControlState;

typedef struct packed
{
    logic[31:0] trapPC;
    logic isInterrupt;
    logic[3:0] cause;
    logic delegate;
    logic valid;
} TrapInfoUpdate;

typedef struct packed
{
    logic[4:0] flags;
    SqN sqN;
    logic valid;
} FloatFlagsUpdate;

typedef struct packed
{
    logic sv32en;
    logic sv32en_ifetch;
    logic[21:0] rootPPN;
    logic makeExecReadable;
    logic supervUserMemory;
    logic[1:0] cbie;
    logic cbcfe;
    PrivLevel priv;
} STAT_VMem;

interface IF_CSR_MMIO;
    logic[63:0] mtime;
    logic[63:0] mtimecmp;
    
    modport CSR
    (
        input mtime,
        input mtimecmp
    );
    modport MMIO
    (
        output mtime,
        output mtimecmp
    );
endinterface

interface IF_MemC;
    logic ce;
    logic we;
    
    logic[0:0] cacheID;
    logic[9:0] sramAddr;
    logic[29:0] extAddr;
    
    logic[9:0] progress;
    logic busy;
    
    modport CON
    (
        input ce, we, cacheID, sramAddr, extAddr,
        output progress, busy
    );
    
    modport CORE
    (
        output ce, we, cacheID, sramAddr, extAddr,
        input progress, busy
    );
endinterface

interface IF_Mem();
    
    localparam ADDR_LEN=30;
    
    logic we;
    logic[ADDR_LEN-1:0] waddr;
    logic[31:0] wdata;
    logic[3:0] wmask;
    
    logic re;
    logic[ADDR_LEN-1:0] raddr;
    logic[31:0] rdata;
    
    logic rbusy;
    logic wbusy;
    
    modport HOST
    (
        output we, waddr, wdata, wmask, re, raddr,
        input rdata, rbusy, wbusy
    );
    
    modport MEM
    (
        input we, waddr, wdata, wmask, re, raddr,
        output rdata, rbusy, wbusy
    );
endinterface

interface IF_MMIO();
    
    localparam ADDR_LEN=32;
    
    logic we;
    logic[ADDR_LEN-1:0] waddr;
    logic[31:0] wdata;
    logic[3:0] wmask;
    
    logic re;
    logic[ADDR_LEN-1:0] raddr;
    logic[1:0] rsize;
    logic[31:0] rdata;
    
    logic rbusy;
    logic wbusy;
    
    modport HOST
    (
        output we, waddr, wdata, wmask, re, raddr, rsize,
        input rdata, rbusy, wbusy
    );
    
    modport MEM
    (
        input we, waddr, wdata, wmask, re, raddr, rsize,
        output rdata, rbusy, wbusy
    );
endinterface

typedef struct packed
{
    logic[19:0] vpn;
    logic valid;
} TLB_Req;

typedef struct packed
{
    logic[19:0] ppn;
    logic fault;
    logic hit;
} TLB_Res;
