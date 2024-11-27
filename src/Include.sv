typedef logic[4:0] RegNm;
typedef logic[`RF_SIZE_EXP:0] Tag;
typedef logic[`RF_SIZE_EXP-1:0] RFTag;
typedef logic[`ROB_SIZE_EXP:0] SqN;
typedef logic[31:0] RegT;
typedef logic[4:0] FetchID_t;
typedef logic[`FSIZE_E-2:0] FetchOff_t;
typedef logic[$clog2(`RETURN_SIZE)-1:0] RetStackIdx_t;
typedef logic[1:0] StID_t;
typedef logic[0:0] CacheID_t;
typedef logic[1:0] StOff_t;
typedef logic[2:0] StNonce_t;
typedef logic[3:0] TageID_t;
typedef logic[`TAGE_BASE*(1<<(`TAGE_STAGES-2))-1:0] BHist_t;
typedef logic[$clog2(NUM_ALUS)-1:0] IntUOpOrder_t;
typedef logic[4:0] TrapCause_t;

localparam Tag TAG_ZERO = {1'b1, RFTag'(0)};

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
    INT_LUI,
    INT_SYS,
    INT_SH1ADD,
    INT_SH2ADD,
    INT_SH3ADD,
    INT_XNOR,
    INT_ANDN,
    INT_ORN,
    INT_MAX,
    INT_MAXU,
    INT_MIN,
    INT_MINU,
    INT_SE_B,
    INT_SE_H,
    INT_ZE_H
} OPCode_INT;

typedef enum logic[5:0]
{
    BR_AUIPC,
    BR_JAL,
    BR_BEQ,
    BR_BNE,
    BR_BLT,
    BR_BGE,
    BR_BLTU,
    BR_BGEU,
    BR_V_RET,
    BR_V_JALR,
    BR_V_JR
} OPCode_Branch;

typedef enum logic[5:0]
{
    BM_CLZ,
    BM_CTZ,
    BM_CPOP,
    BM_ROL,
    BM_ROR,
    BM_ORC_B,
    BM_REV8,
    BM_BCLR,
    BM_BEXT,
    BM_BINV,
    BM_BSET
`ifdef ENABLE_FP
    ,
    BM_FSGNJ_S,
    BM_FSGNJN_S,
    BM_FSGNJX_S
`endif

} OPCode_Bitmanip;

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
    LSU_LR_W,

    LSU_SC_W,
    LSU_SB,
    LSU_SH,
    LSU_SW,

    LSU_CBO_CLEAN,
    LSU_CBO_INVAL,
    LSU_CBO_FLUSH

} OPCode_AGU;

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
    ATOMIC_AMOSWAP_W=55,
    ATOMIC_AMOADD_W=56,
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

// Trap Cause Encodings straight from Privilege Spec
typedef enum logic[4:0]
{
    RVP_TRAP_IF_MA   = 0,
    RVP_TRAP_IF_AF   = 1,
    RVP_TRAP_ILLEGAL = 2,
    RVP_TRAP_BREAK   = 3,
    RVP_TRAP_LD_MA   = 4,
    RVP_TRAP_LD_AF   = 5,
    RVP_TRAP_ST_MA   = 6,
    RVP_TRAP_ST_AF   = 7,
    RVP_TRAP_ECALL_U = 8,
    RVP_TRAP_ECALL_S = 9,
    RVP_TRAP_IF_PF   = 12,
    RVP_TRAP_LD_PF   = 13,
    RVP_TRAP_ST_PF   = 15,
    TRAP_CUSTOM_HANG = 24
} RVPTrapCause;

// For decode-time traps, we use FLAGS_TRAP/FU_TRAP as an,
// escape flag. The (unused) rd field then stores one of these fields
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

typedef enum logic[3:0]
{
    FU_INT,
    FU_BRANCH,
    FU_BITMANIP,
    FU_AGU,
    FU_MUL,
    FU_DIV,
    FU_FPU,
    FU_FMUL,
    FU_FDIV,
    FU_RN,
    FU_ATOMIC,
    FU_CSR,
    FU_TRAP
} FuncUnit /* public */;

typedef enum logic[3:0]
{
    // Flags that do not cause a flush or trap
    FLAGS_NONE, FLAGS_BRANCH,

    // Flags for sending direction prediction updates
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

} Flags /* public */;

// Floating Point Ops use a different flag encoding to store
// floating point exceptions
typedef enum logic[3:0]
{
    FLAGS_FP_NX = FLAGS_LD_MA,
    FLAGS_FP_UF = FLAGS_LD_AF,
    FLAGS_FP_OF = FLAGS_LD_PF,
    FLAGS_FP_DZ = FLAGS_ST_MA,
    FLAGS_FP_NV = FLAGS_ST_AF

} FlagsFP;

typedef enum logic[1:0]
{
    PRIV_USER=0, PRIV_SUPERVISOR=1, PRIV_MACHINE=3
} PrivLevel;

typedef enum logic[1:0]
{
    IF_FAULT_NONE = 0, IF_INTERRUPT, IF_ACCESS_FAULT, IF_PAGE_FAULT
} IFetchFault /* public */;

typedef enum logic[2:0]
{
    FLUSH_ORDERING,
    FLUSH_BRANCH_TK,
    FLUSH_BRANCH_NT,
    FLUSH_RETURN,
    FLUSH_IBRANCH,
    FLUSH_MEM_ORDER
} FlushCause /* public */;

typedef enum logic[2:0]
{
    STALL_NONE,
    STALL_FRONTEND,
    STALL_BACKEND,
    STALL_STORE,
    STALL_LOAD,
    STALL_ROB
} StallCause;

typedef enum logic[3:0]
{
    MEMC_NONE,

    // cache line operations
    MEMC_REPLACE,
    MEMC_CP_CACHE_TO_EXT,
    MEMC_CP_EXT_TO_CACHE,

    // single access
    MEMC_READ_BYTE,
    MEMC_READ_HALF,
    MEMC_READ_WORD,
    MEMC_WRITE_BYTE,
    MEMC_WRITE_HALF,
    MEMC_WRITE_WORD
} MemC_Cmd /* public */;

typedef struct packed
{
    logic[31:0] data;
    logic[`CACHE_SIZE_E-3:0] id;
    logic valid;
} MemController_SglLdRes /* public */;

typedef struct packed
{
    logic[`CACHE_SIZE_E-3:0] id;
    logic valid;
} MemController_SglStRes /* public */;

typedef struct packed
{
    logic[`AXI_WIDTH-1:0] data;
    logic[31:0] addr;
    logic valid;
} MemController_LdDataFwd /* public */;

typedef struct packed
{
    logic[31:0] writeAddr;
    logic[31:0] readAddr;
    logic[`CACHE_SIZE_E-3:0] cacheAddr;
    logic[`CLSIZE_E-2:0] progress;
    CacheID_t cacheID;
    logic active;
    logic valid;
} MemController_Transf;

typedef struct packed
{
    logic[`AXI_WIDTH/8-1:0] mask;
    logic[`AXI_WIDTH-1:0] data;

    logic[`CACHE_SIZE_E-3:0] cacheAddr; // instead used as ID for MMIO
    logic[31:0] readAddr;
    logic[31:0] writeAddr;
    CacheID_t cacheID;
    MemC_Cmd cmd;
} MemController_Req /* public */;

typedef struct packed
{
    MemController_LdDataFwd ldDataFwd;
    MemController_Transf[`AXI_NUM_TRANS-1:0] transfers;
    MemController_SglLdRes sglLdRes;
    MemController_SglStRes sglStRes;

    logic[2:0] stall;
    logic busy;
} MemController_Res /* public */;

typedef enum logic[1:0]
{
    BT_JUMP, BT_CALL, BT_BRANCH, BT_RETURN
} BranchType /* public */;

typedef struct packed
{
    logic[30:0] dst;
    FetchOff_t offs;
    logic compr;
    BranchType btype;
    logic multiple;
    logic taken;
    logic dirOnly;
    logic valid;
} PredBranch /* public */;

typedef struct packed
{
    logic taken;
} BranchPredInfo /* public */;

typedef struct packed
{
    logic[31:0] src;
    logic[31:0] dst;
    FetchOff_t fetchStartOffs;
    BranchType btype;
    FetchOff_t multipleOffs;
    logic multiple;
    logic compressed;
    logic clean;
    logic valid;
} BTUpdate;

typedef enum logic[1:0]
{
    RET_NONE, RET_PUSH, RET_POP
} RetStackAction /* public */;

typedef enum logic[2:0]
{
    HIST_NONE, HIST_APPEND_0, HIST_APPEND_1, HIST_WRITE_0, HIST_WRITE_1
} HistoryAction /* public */;

typedef enum logic[1:0]
{
    // We generally store the PC of the last instruction halfword,
    // so next is always +1 while offset to current may be 0 or -1.
    BR_TGT_MANUAL, BR_TGT_NEXT, BR_TGT_CUR16, BR_TGT_CUR32
} BranchTargetSpec /* public */;

typedef struct packed
{
    FlushCause cause; // only for performance counters
    BranchTargetSpec tgtSpec;
    logic isSCFail;
    FetchOff_t fetchOffs;
    RetStackAction retAct;
    HistoryAction histAct;
    logic[31:0] dstPC;
    SqN sqN;
    SqN storeSqN;
    SqN loadSqN;
    logic flush;
    FetchID_t fetchID;
    logic taken;
} BranchProv /* public */;

typedef struct packed
{
    TageID_t tageID;
    logic altPred;

    BHist_t history;
    RetStackIdx_t rIdx;
    logic isRegularBranch;
    logic predTaken;
    FetchOff_t predOffs;
    logic pred;
} BPBackup /* public */;

typedef struct packed
{
    logic isFetchBranch;
    BranchTargetSpec tgtSpec;
    FetchOff_t fetchOffs;
    RetStackAction retAct;
    HistoryAction histAct;
    logic[30:0] dst;
    FetchID_t fetchID;
    logic wfi;
    logic taken;
} FetchBranchProv;

typedef struct packed
{
    logic[30:0] addr;
    RetStackIdx_t idx;
    logic valid;
} ReturnDecUpdate;

typedef struct packed
{
    logic[30:0] pc;
    FetchOff_t branchPos;
    BranchPredInfo bpi;
} PCFileEntry;

typedef struct packed
{
    FetchID_t addr;
    logic valid;
} PCFileReadReq;

typedef struct packed
{
    logic prio;
    FetchID_t addr;
    logic valid;
} PCFileReadReqTH;

typedef struct packed
{
    logic[31:0] pc;
    FetchID_t fetchID;
    IFetchFault fetchFault;
    FetchOff_t lastValid;

    PredBranch predBr;

    logic[30:0] predRetAddr;
    RetStackIdx_t rIdx;

    logic valid;
} IFetchOp /* public */;

typedef struct packed
{
    logic[31-`FSIZE_E:0] pc;
    FetchID_t fetchID;
    IFetchFault fetchFault;
    FetchOff_t firstValid;
    FetchOff_t lastValid;
    FetchOff_t predPos;
    logic predTaken;
    logic[30:0] predTarget;
    logic[FETCH_WORDS-1:0][15:0] instrs;

    logic valid;
} IF_Instr /* public */;

typedef struct packed
{
    logic[31:0] instr;
    logic[30:0] pc;
    FetchOff_t fetchStartOffs;
    FetchOff_t fetchPredOffs;
    logic[30:0] predTarget;
    logic predTaken;
    FetchID_t fetchID;
    IFetchFault fetchFault;
    logic is16bit;
    logic valid;
} PD_Instr /* public */;

typedef struct packed
{
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    logic wfi;
    logic taken;
} DecodeBranch;

typedef struct packed
{
    logic[31:0] imm;
    logic[11:0] imm12; // only used for jalr
    logic[4:0] rs1;
    logic[4:0] rs2;
    logic immB;
    logic[4:0] rd;
    logic[5:0] opcode;
    FuncUnit fu;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    logic compressed;
    logic valid;
} D_UOp /* public */;

typedef struct packed
{
    logic[31:0] imm;
    logic[11:0] imm12; // only used for jalr (on int ports)
    logic availA;
    Tag tagA;
    logic availB;
    Tag tagB;
    logic immB;
    logic availC;
    Tag tagC; // used for atomics
    SqN sqN;
    Tag tagDst;
    RegNm rd;
    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic[NUM_PORTS_TOTAL-1:0] validIQ; // valids for individual Issue Queues
    logic valid;
} R_UOp /* public */;

typedef struct packed
{
    logic[31:0] imm;
    logic[11:0] imm12;
    logic availA;
    Tag tagA;
    logic availB;
    Tag tagB;
    logic immB;
    SqN sqN;
    Tag tagDst;
    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic valid;
} IS_UOp /* public */;

typedef struct packed
{
    SqN sqN;
    logic valid;
} OpFile_Req;
typedef struct packed
{
    // imm size varies per port
    logic[11:0] imm12;
    logic[31:0] imm;

    // only int ports store ld/st sqn in op file
    SqN storeSqN;
    SqN loadSqN;

    logic[5:0] opcode;
    logic immB;
    logic compressed;
    FetchOff_t fetchOffs;
} OpFile_Res;

typedef struct packed
{
    RFTag tag;
    logic valid;
} RF_ReadReq;

typedef struct packed
{
    logic[31:0] srcA;
    logic[31:0] srcB;
    logic[31:0] pc;
    FetchOff_t fetchOffs;
    FetchOff_t fetchStartOffs;
    FetchOff_t fetchPredOffs;
    logic[31:0] imm;
    logic[5:0] opcode;
    Tag tagDst;
    SqN sqN;
    FetchID_t fetchID;
    BranchPredInfo bpi;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic valid;
} EX_UOp /* public */;

typedef struct packed
{
    logic[31:0] result;
    Tag tagDst;
    SqN sqN;
    Flags flags;
    logic doNotCommit;
    logic valid;
} RES_UOp /* public */;

typedef struct packed
{
    Tag tagDst;
    SqN sqN;
    Flags flags;
    logic doNotCommit;
    logic valid;
} FlagsUOp /* public */;

typedef struct packed
{
    logic[31:0] result;
    Tag tagDst;
    logic doNotCommit;
    logic valid;
} ResultUOp /* public */;

typedef struct packed
{
    logic[31:0] result;
    SqN storeSqN;
    SqN sqN;
    logic valid;
} AMO_Data_UOp;

typedef struct packed
{
    logic[31:0] addr;
    // could union some of these fields
    logic[3:0] wmask;
    logic signExtend;
    logic[1:0] size;
    logic isStore; // both isLoad and isStore may be set (for atomics)
    logic isLoad;
    logic isLrSc;
    logic earlyLoadFailed;
    Tag tagDst;
    SqN sqN;
    SqN storeSqN;
    SqN loadSqN;
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    logic doNotCommit;
    logic compressed;
    logic valid;
} AGU_UOp;

typedef struct packed
{
    logic[31:0] data;
    SqN storeSqN;
    logic valid;
} StDataUOp;

typedef struct packed
{
    StOff_t offs;
    Tag tag;
    SqN storeSqN;
    logic valid;
} StDataLookupUOp;

typedef struct packed
{
    logic[31:0] data;
    logic[3:0] fwdMask;
    logic[31:0] addr;
    logic[1:0] size;
    logic sext;
    logic dataAvail;

    Tag tagDst;
    SqN sqN;
    logic external;
    logic doNotCommit;
    logic valid;
} LoadResUOp;

typedef struct packed
{
    logic[31:0] addr;
    logic[21:0] rootPPN;
    logic valid;
} PageWalk_Req;

typedef struct packed
{
    logic[19:0] vpn;
    logic[21:0] ppn;

    logic pageFault;
    logic isSuperPage;

    logic globl;
    logic user;

    logic[2:0] rwx;
    logic[1:0] rqID;

    logic busy;
    logic valid;
} PageWalk_Res;

typedef struct packed
{
    logic[19:0] vpn;
    logic valid;
} TLB_Req;

typedef struct packed
{
    logic[19:0] ppn;
    logic pageFault;
    logic accessFault;
    logic[2:0] rwx;
    logic isSuper;
    logic user;
    logic hit;
} TLB_Res;

typedef struct packed
{
    logic[31:0] addr;
    logic valid;
} PW_LD_UOp;

typedef struct packed
{
    logic[31:0] data;
    logic dataValid;
    logic[31:0] addr;
    logic signExtend;
    logic[1:0] size;
    SqN storeSqN;
    SqN loadSqN;
    Tag tagDst;
    SqN sqN;
    logic atomic;
    logic doNotCommit;
    logic external; // not part of normal execution, ignore sqn, tagDst and rd, don't commit
    logic isMMIO;
    logic valid;
} LD_UOp /* public */;

typedef struct packed
{
    logic[11:0] addr;
    logic valid;
} ELD_UOp; // early load address for VIPT

typedef struct packed
{
    logic[31:0] addr;
    SqN loadSqN;
    logic fail;
    logic doNotReIssue;
    logic external;
    logic valid;
} LD_Ack;

typedef struct packed
{
    RegT data;
    logic[31:0] addr;
    logic[3:0] wmask;
    logic isMgmt;
    logic valid;
} SQ_UOp;

typedef struct packed
{
    logic[31:0] addr;
    logic[`AXI_WIDTH-1:0] data;
    logic[`AXI_WIDTH/8-1:0] wmask;
    logic isMMIO;
    logic isMgmt;
    StNonce_t nonce;
    StID_t id;
    logic valid;
} ST_UOp /* public */;

typedef struct packed
{
    logic[31:0] addr;
    logic[`AXI_WIDTH-1:0] data;
    logic[`AXI_WIDTH/8-1:0] wmask;
    StNonce_t nonce;
    StID_t idx;
    logic fail;
    logic valid;
} ST_Ack;

typedef struct packed
{
    SqN sqN;
    logic valid;
} ComLimit;

typedef struct packed
{
    FetchID_t fetchID;
    logic valid;
} FetchLimit;

typedef struct packed
{
    RegNm rd;
    Tag tagDst;
    SqN sqN;
    logic isBranch;
    logic branchTaken;
    logic compressed;
    logic valid;
} CommitUOp /* public */;

typedef struct packed
{
    logic timeout;
    Flags flags;
    Tag tag;
    SqN sqN;
    SqN loadSqN;
    SqN storeSqN;
    RegNm rd;
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    logic compressed;
    logic valid;
} Trap_UOp /* public */;

typedef struct packed
{
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
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
    TrapCause_t interruptCause;
    logic interruptDelegate;

} TrapControlState;

typedef struct packed
{
    logic[31:0] tval;
} TValState;

typedef struct packed
{
    logic[31:0] trapPC;
    logic[31:0] finalHalfwPC;
    logic isInterrupt;
    TrapCause_t cause;
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
} VirtMemState;

typedef struct packed
{
    logic allowCustom;
    logic allowWFI;
    logic allowSFENCE;
} DecodeState;

typedef struct packed
{
    logic[31:0] tval;
    SqN sqN;
    logic valid;
} TValProv;

typedef struct packed
{
    logic ce;
    logic we;
    logic[4*`CWIDTH-1:0] wm;
    logic[`CACHE_SIZE_E-3:0] addr;
    logic[32*`CWIDTH-1:0] data;
} CacheIF;

typedef struct packed
{
    logic ce;
    logic we;
    logic[(FETCH_BITS/`AXI_WIDTH)-1:0] wm;
    logic[`CACHE_SIZE_E-3:0] addr;
    logic[FETCH_BITS-1:0] data;
} ICacheIF;

typedef struct packed
{
    logic[1:0] stallWeigth;
    StallCause stallCause;
    logic[3:0] branchRetire;
    logic[3:0] validRetire;
} ROB_PERFC_Info;

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

interface IF_Cache();

    logic[NUM_AGUS-1:0] re;
    logic[NUM_AGUS-1:0] we;
    logic[NUM_AGUS-1:0][`VIRT_IDX_LEN-1:0] addr;
    logic[NUM_AGUS-1:0][`CASSOC-1:0][31:0] rdata;
    logic[NUM_AGUS-1:0][$clog2(`CASSOC)-1:0] wassoc;
    logic[NUM_AGUS-1:0][`AXI_WIDTH-1:0] wdata;
    logic[NUM_AGUS-1:0][`AXI_WIDTH/8-1:0] wmask;
    logic[NUM_AGUS-1:0] busy;

    modport HOST
    (
        output we, wassoc, wdata, wmask, re, addr,
        input rdata, busy
    );

    modport MEM
    (
        input we, wassoc, wdata, wmask, re, addr,
        output rdata, busy
    );
endinterface

typedef struct packed
{
    logic[32-`VIRT_IDX_LEN-1:0] addr;
    logic valid;
} CTEntry;

typedef struct packed
{
    logic[31:0] data;
    logic[3:0] mask;
    logic conflict;
    logic valid;
} StFwdResult;

interface IF_CTable();

    logic we;
    logic[`VIRT_IDX_LEN-1:0] waddr;
    logic[$clog2(`CASSOC)-1:0] wassoc;
    CTEntry wdata;

    logic re[NUM_AGUS-1:0];
    logic[`VIRT_IDX_LEN-1:0] raddr[NUM_AGUS-1:0];
    CTEntry[NUM_AGUS-1:0][`CASSOC-1:0] rdata;

    modport HOST
    (
        output we, waddr, wassoc, wdata, re, raddr,
        input rdata
    );

    modport MEM
    (
        input we, waddr, wassoc, wdata, re, raddr,
        output rdata
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

interface IF_ICTable();

    logic we;
    logic[`VIRT_IDX_LEN-1:0] waddr;
    logic[$clog2(`CASSOC)-1:0] wassoc;
    CTEntry wdata;

    logic re;
    logic[`VIRT_IDX_LEN-1:0] raddr;
    CTEntry[`CASSOC-1:0] rdata;

    modport HOST
    (
        output we, waddr, wassoc, wdata, re, raddr,
        input rdata
    );

    modport MEM
    (
        input we, waddr, wassoc, wdata, re, raddr,
        output rdata
    );
endinterface

interface IF_ICache();

    logic re;
    logic[11:0] raddr;
    logic[`CASSOC-1:0][FETCH_BITS-1:0] rdata;
    logic busy;

    modport HOST
    (
        output re, raddr,
        input rdata, busy
    );

    modport MEM
    (
        input re, raddr,
        output rdata, busy
    );
endinterface

typedef struct packed
{
    logic[31:0] stallPC;

    logic sqNStall;
    logic stSqNStall;

    logic rnStall;
    logic memBusy;

    logic sqBusy;
    logic lsuBusy;
    logic ldNack;
    logic stNack;

} DebugInfo;

typedef struct packed
{
    logic[3:0] transfValid;
    logic[3:0] transfReadDone;
    logic[3:0] transfWriteDone;
    logic[3:0] transfIsMMIO;
} DebugInfoMemC;
