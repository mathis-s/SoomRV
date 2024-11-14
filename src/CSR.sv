module CSR#(parameter NUM_FLOAT_FLAG_UPD = 2)
(
    input wire clk,
    input wire rst,
    input wire en,

    input wire IN_irq,

    input EX_UOp IN_uop,
    input BranchProv IN_branch,

    input wire[4:0] IN_fpNewFlags,

    input ROB_PERFC_Info IN_perfcInfo,
    input wire IN_branchMispr,

    IF_CSR_MMIO.CSR IF_mmio,

    input TValState IN_tvalState,

    input TrapInfoUpdate IN_trapInfo,
    output TrapControlState OUT_trapControl,
    output wire[2:0] OUT_fRoundMode,

    output DecodeState OUT_dec,
    output VirtMemState OUT_vmem,

    output RES_UOp OUT_uop
);

localparam NUM_PERFC = 17;

typedef logic[11:0] CSR_Id;

typedef enum logic[11:0]
{
    CSR_fflags=12'h001,
    CSR_frm=12'h002,
    CSR_fcsr=12'h003,

    CSR_cycle=12'hC00,
    CSR_time=12'hC01,
    CSR_instret=12'hC02,
    CSR_hpmcounter3=12'hC03,
    CSR_hpmcounter4=12'hC04,
    CSR_hpmcounter5=12'hC05,
    CSR_hpmcounter6=12'hC06,
    CSR_hpmcounter7=12'hC07,
    CSR_hpmcounter8,
    CSR_hpmcounter9,
    CSR_hpmcounter10,
    CSR_hpmcounter11,
    CSR_hpmcounter12,
    CSR_hpmcounter13,
    CSR_hpmcounter14,
    CSR_hpmcounter15,
    CSR_hpmcounter16,
    CSR_hpmcounter17,
    CSR_hpmcounter18,
    CSR_hpmcounter19,
    CSR_hpmcounter20,
    CSR_hpmcounter21,
    CSR_hpmcounter22,
    CSR_hpmcounter23,
    CSR_hpmcounter24,
    CSR_hpmcounter25,
    CSR_hpmcounter26,
    CSR_hpmcounter27,
    CSR_hpmcounter28,
    CSR_hpmcounter29,
    CSR_hpmcounter30,
    CSR_hpmcounter31=12'hC1F,

    CSR_cycleh=12'hC80,
    CSR_timeh=12'hC81,
    CSR_instreth=12'hC82,
    CSR_hpmcounter3h=12'hC83,
    CSR_hpmcounter4h=12'hC84,
    CSR_hpmcounter5h=12'hC85,
    CSR_hpmcounter6h=12'hC86,
    CSR_hpmcounter7h=12'hC87,
    CSR_hpmcounter8h,
    CSR_hpmcounter9h,
    CSR_hpmcounter10h,
    CSR_hpmcounter11h,
    CSR_hpmcounter12h,
    CSR_hpmcounter13h,
    CSR_hpmcounter14h,
    CSR_hpmcounter15h,
    CSR_hpmcounter16h,
    CSR_hpmcounter17h,
    CSR_hpmcounter18h,
    CSR_hpmcounter19h,
    CSR_hpmcounter20h,
    CSR_hpmcounter21h,
    CSR_hpmcounter22h,
    CSR_hpmcounter23h,
    CSR_hpmcounter24h,
    CSR_hpmcounter25h,
    CSR_hpmcounter26h,
    CSR_hpmcounter27h,
    CSR_hpmcounter28h,
    CSR_hpmcounter29h,
    CSR_hpmcounter30h,
    CSR_hpmcounter31h=12'hC9F,


    CSR_sstatus=12'h100,
    CSR_sie=12'h104, // interrupt enable
    CSR_stvec=12'h105, // trap handler base address
    CSR_scounteren=12'h106, // counter enable

    CSR_senvcfg=12'h10A, // environment configuration

    CSR_sscratch=12'h140,
    CSR_sepc=12'h141, // sepc exception program counter
    CSR_scause=12'h142, // trap cause
    CSR_stval=12'h143, // bad address or instruction
    CSR_sip=12'h144, // interrupt pending

    CSR_satp=12'h180, // address translation and protection
    CSR_scontext=12'h5A8, // mode context register


    CSR_mvendorid=12'hF11,
    CSR_marchid=12'hF12,
    CSR_mimpid=12'hF13,
    CSR_mhartid=12'hF14,
    CSR_mconfigptr=12'hF15,

    CSR_mstatus=12'h300,
    CSR_misa=12'h301,
    CSR_medeleg=12'h302, // exception delegation
    CSR_mideleg=12'h303, // interrupt delegation
    CSR_mie=12'h304, // interrupt enable
    CSR_mtvec=12'h305, // trap handler
    CSR_mcounteren=12'h306,
    CSR_mstatush=12'h310,

    CSR_mscratch=12'h340,
    CSR_mepc=12'h341,
    CSR_mcause=12'h342,
    CSR_mtval=12'h343,
    CSR_mip=12'h344,
    CSR_mtinst=12'h34A,
    CSR_mtval2=12'h34B,

    CSR_menvcfg=12'h30A,
    CSR_menvcfgh=12'h31A,
    CSR_mseccfg=12'h747,
    CSR_mseccfgh=12'h757,


    CSR_pmpcfg0=12'h3A0,
    CSR_pmpcfg1=12'h3A1,
    CSR_pmpcfg2=12'h3A2,
    // ...
    CSR_pmpcfg15=12'h3AF,

    CSR_pmpaddr0=12'h3B0,
    CSR_pmpaddr1=12'h3B1,
    CSR_pmpaddr2=12'h3B2,
    CSR_pmpaddr3=12'h3B3,
    // ...
    CSR_pmpaddr63=12'h3EF,


    CSR_mcycle=12'hB00,
    CSR_minstret=12'hB02,
    CSR_mhpmcounter3=12'hB03,
    CSR_mhpmcounter4=12'hB04,
    CSR_mhpmcounter5,
    CSR_mhpmcounter6,
    CSR_mhpmcounter7,
    CSR_mhpmcounter8,
    CSR_mhpmcounter9,
    CSR_mhpmcounter10,
    CSR_mhpmcounter11,
    CSR_mhpmcounter12,
    CSR_mhpmcounter13,
    CSR_mhpmcounter14,
    CSR_mhpmcounter15,
    CSR_mhpmcounter16,
    CSR_mhpmcounter17,
    CSR_mhpmcounter18,
    CSR_mhpmcounter19,
    CSR_mhpmcounter20,
    CSR_mhpmcounter21,
    CSR_mhpmcounter22,
    CSR_mhpmcounter23,
    CSR_mhpmcounter24,
    CSR_mhpmcounter25,
    CSR_mhpmcounter26,
    CSR_mhpmcounter27,
    CSR_mhpmcounter28,
    CSR_mhpmcounter29,
    CSR_mhpmcounter30,
    CSR_mhpmcounter31=12'hB1F,

    CSR_mcycleh=12'hB80,
    CSR_minstreth=12'hB82,
    CSR_mhpmcounter3h=12'hB83,
    CSR_mhpmcounter4h=12'hB84,
    CSR_mhpmcounter5h,
    CSR_mhpmcounter6h,
    CSR_mhpmcounter7h,
    CSR_mhpmcounter8h,
    CSR_mhpmcounter9h,
    CSR_mhpmcounter10h,
    CSR_mhpmcounter11h,
    CSR_mhpmcounter12h,
    CSR_mhpmcounter13h,
    CSR_mhpmcounter14h,
    CSR_mhpmcounter15h,
    CSR_mhpmcounter16h,
    CSR_mhpmcounter17h,
    CSR_mhpmcounter18h,
    CSR_mhpmcounter19h,
    CSR_mhpmcounter20h,
    CSR_mhpmcounter21h,
    CSR_mhpmcounter22h,
    CSR_mhpmcounter23h,
    CSR_mhpmcounter24h,
    CSR_mhpmcounter25h,
    CSR_mhpmcounter26h,
    CSR_mhpmcounter27h,
    CSR_mhpmcounter28h,
    CSR_mhpmcounter29h,
    CSR_mhpmcounter30h,
    CSR_mhpmcounter31h=12'hB9F,

    CSR_mcountinhibit=12'h320,
    CSR_mhpmevent3=12'h323,
    CSR_mhpmevent4=12'h324,
    CSR_mhpmevent5=12'h325,
    CSR_mhpmevent6=12'h326,
    CSR_mhpmevent7=12'h327,
    CSR_mhpmevent8=12'h328,
    CSR_mhpmevent9=12'h329,
    CSR_mhpmevent10=12'h32A,
    CSR_mhpmevent11=12'h32B,
    CSR_mhpmevent12=12'h32C,
    CSR_mhpmevent13=12'h32D,
    CSR_mhpmevent14=12'h32E,
    CSR_mhpmevent15=12'h32F,
    CSR_mhpmevent16=12'h330,
    CSR_mhpmevent17=12'h331,
    CSR_mhpmevent18=12'h332,
    CSR_mhpmevent19=12'h333,
    CSR_mhpmevent20=12'h334,
    CSR_mhpmevent21=12'h335,
    CSR_mhpmevent22=12'h336,
    CSR_mhpmevent23=12'h337,
    CSR_mhpmevent24=12'h338,
    CSR_mhpmevent25=12'h339,
    CSR_mhpmevent26=12'h33A,
    CSR_mhpmevent27=12'h33B,
    CSR_mhpmevent28=12'h33C,
    CSR_mhpmevent29=12'h33D,
    CSR_mhpmevent30=12'h33E,
    CSR_mhpmevent31=12'h33F,

    CSR_tselect=12'h7A0,
    CSR_tdata1=12'h7A1,
    CSR_tdata2=12'h7A2,
    CSR_tdata3=12'h7A3,
    CSR_mcontext=12'h7A8,

    CSR_magic=12'hCC0
} CSRAddr;

typedef enum logic[3:0]
{
    SSI=1,
    MSI=3,
    STI=5,
    MTI=7,
    SEI=9,
    MEI=11
} InterruptIndices;


PrivLevel priv;

reg[4:0] fflags;
reg[2:0] frm;

reg[63:0] mcycle /*verilator public*/;
reg[63:0] minstret /*verilator public*/;
reg[63:0] mhpmcounter[NUM_PERFC-1:0] /*verilator public*/; // branches

typedef struct packed
{
    logic sd; // state dirty (0)
    logic[7:0] wpri23; // (0)
    logic tsr; // trap sret
    logic tw; // timeout wait (1 -> illegal instr on wfi)
    logic tvm; // trap virtual memory
    logic mxr; // make executable readable, 0 if s mode not supported
    logic sum; // permit supervisor user memory access
    logic mprv; // memory privilege (1 -> ld/st memory access via mode in MPP), 0 if u mode not supported
    logic[1:0] xs; // extended register state (0)
    logic[1:0] fs_; // floating point register state (0)
    PrivLevel mpp; // machine prior privilege
    logic[1:0] vs; // vector register state (0)
    logic spp; // supervisor prior privilege
    logic mpie; // machine prior interrupt enable
    logic ube; // user big endian (0)
    logic spie; // supervisor prior interrupt enable
    logic wpri4; // (0)
    logic mie; // machine interrupt enable
    logic wpri2; // (0)
    logic sie; // supervisor interrupt enable
    logic wpri0; // (0)
} MStatus_t;

MStatus_t mstatus;

typedef struct packed
{
    logic[29:0] base;
    logic[1:0] mode;
} TVec_t;

TVec_t mtvec;
TVec_t stvec;

reg[31:0] mscratch;

reg[31:0] mepc;
reg[31:0] mcause;
reg[31:0] mtval;
reg[15:0] medeleg;
reg[15:0] mideleg;
reg[15:0] mip;
reg[15:0] mie;
reg[31:0] mcounteren;
reg[31:0] mcountinhibit;

typedef struct packed
{
    logic[23:0] wpri1;
    logic cbze;
    logic cbcfe;
    logic[1:0] cbie;
    logic[2:0] wpri0;
    logic fiom;
} MEnvCfg_t;
MEnvCfg_t menvcfg;
MEnvCfg_t senvcfg;

reg[31:0] scounteren;
reg[31:0] sepc;
reg[31:0] sscratch;
reg[31:0] scause;
reg[31:0] stval;

reg misa_X; // enable/disable for custom instrs

struct packed
{
    logic mode;
    logic[8:0] asid;
    logic[21:0] ppn;
} satp;

reg[30:0] retvec;

reg interrupt;
TrapCause_t interruptCause;
reg interruptDelegate;
always_comb begin

    // these are in reverse
    InterruptIndices mPrio[5:0] = '{STI, SSI, SEI, MTI, MSI, MEI};
    InterruptIndices sPrio[2:0] = '{STI, SSI, SEI};

    interruptCause = 0;
    interrupt = 0;
    interruptDelegate = 0;


    if (priv < PRIV_SUPERVISOR || (mstatus.sie && priv == PRIV_SUPERVISOR))
        for (integer i = 0; i < 3; i=i+1)
            if (mip[sPrio[i][3:0]] && mie[sPrio[i][3:0]]) begin
                interrupt = 1;
                interruptCause = {1'b0, sPrio[i]};
                interruptDelegate = 1;
            end

    if (priv < PRIV_MACHINE || mstatus.mie)
        for (integer i = 0; i < 6; i=i+1)
            if (mip[mPrio[i][3:0]] && mie[mPrio[i][3:0]] && !mideleg[mPrio[i][3:0]]) begin
                interrupt = 1;
                interruptCause = {1'b0, mPrio[i]};
                interruptDelegate = 0;
            end
end



assign OUT_trapControl.mvectord = mtvec.mode[0];
assign OUT_trapControl.mtvec = mtvec.base;
assign OUT_trapControl.svectord = stvec.mode[0];
assign OUT_trapControl.stvec = stvec.base;
assign OUT_trapControl.retvec = retvec;
assign OUT_trapControl.mideleg = mideleg;
assign OUT_trapControl.medeleg = medeleg;
assign OUT_trapControl.priv = priv;
assign OUT_trapControl.interruptPending = interrupt;
assign OUT_trapControl.interruptCause = interruptCause;
assign OUT_trapControl.interruptDelegate = interruptDelegate;

assign OUT_fRoundMode = frm;

assign OUT_dec.allowWFI = (priv == PRIV_MACHINE) || (priv == PRIV_SUPERVISOR && !mstatus.tw);
assign OUT_dec.allowCustom = misa_X;
assign OUT_dec.allowSFENCE = !mstatus.tvm;

VirtMemState vmem_c;
always_comb begin
    PrivLevel epm = mstatus.mprv ? mstatus.mpp : priv;

    vmem_c.rootPPN = satp.ppn;
    vmem_c.sv32en_ifetch = satp.mode && priv != PRIV_MACHINE;
    vmem_c.sv32en = satp.mode;
    vmem_c.priv = epm;
    vmem_c.makeExecReadable = mstatus.mxr;
    vmem_c.supervUserMemory = 0;

    if (epm == PRIV_MACHINE) begin
        vmem_c.sv32en_ifetch = 0;
        vmem_c.sv32en = 0;
    end
    else if (epm == PRIV_SUPERVISOR) begin
        vmem_c.supervUserMemory = mstatus.sum;
    end

    vmem_c.cbcfe =
    !(
        (priv != PRIV_MACHINE && !menvcfg.cbcfe) ||
        (priv == PRIV_USER && !senvcfg.cbcfe)
    );

    if ((priv != PRIV_MACHINE && menvcfg.cbie == 0) ||
        (priv == PRIV_USER && senvcfg.cbie == 0))
        vmem_c.cbie = 0;
    else if ((priv != PRIV_MACHINE && menvcfg.cbie == 1) ||
        (priv == PRIV_USER && senvcfg.cbie == 1))
        vmem_c.cbie = 1;
    else
        vmem_c.cbie = 3;
end

always_ff@(posedge clk) OUT_vmem <= vmem_c;

reg[31:0] rdata;
reg invalidCSR;
always_comb begin

    MStatus_t temp = 0;

    invalidCSR = 0;
    rdata = 32'bx;

    case (IN_uop.imm[11:0])
`ifdef ENABLE_FP
        CSR_fflags: rdata = {27'b0, fflags};
        CSR_frm: rdata = {29'b0, frm};
        CSR_fcsr: rdata = {24'b0, frm, fflags};
`endif

        CSR_time,
        CSR_timeh: begin
            invalidCSR = !((priv == PRIV_MACHINE) ||
                (priv == PRIV_SUPERVISOR && mcounteren[1]) ||
                (priv == PRIV_USER && mcounteren[1] && scounteren[1]));
            rdata = (IN_uop.imm[11:0] == CSR_time) ? IF_mmio.mtime[31:0] : IF_mmio.mtime[63:32];
        end

        CSR_cycle: begin
            invalidCSR = !((priv == PRIV_MACHINE) ||
                (priv == PRIV_SUPERVISOR && mcounteren[0]) ||
                (priv == PRIV_USER && mcounteren[0] && scounteren[0]));
            rdata = mcycle[31:0];
        end
        CSR_cycleh: begin
            invalidCSR = !((priv == PRIV_MACHINE) ||
                (priv == PRIV_SUPERVISOR && mcounteren[0]) ||
                (priv == PRIV_USER && mcounteren[0] && scounteren[0]));
            rdata = mcycle[63:32];
        end

        CSR_instret: begin
            invalidCSR = !((priv == PRIV_MACHINE) ||
                (priv == PRIV_SUPERVISOR && mcounteren[2]) ||
                (priv == PRIV_USER && mcounteren[2] && scounteren[2]));
            rdata = minstret[31:0];
        end
        CSR_instreth: begin
            invalidCSR = !((priv == PRIV_MACHINE) ||
                (priv == PRIV_SUPERVISOR && mcounteren[2]) ||
                (priv == PRIV_USER && mcounteren[2] && scounteren[2]));
            rdata = minstret[63:32];
        end

        CSR_misa: rdata = 32'b01_0000_00000101000001000100000101 | {8'b0, misa_X, 23'b0};
        CSR_marchid: rdata = 32'h50087502;
        CSR_mimpid: rdata = 32'h50087532;
        CSR_mstatus: rdata = mstatus;

        CSR_mcycle: rdata = mcycle[31:0];
        CSR_mcycleh: rdata = mcycle[63:32];

        CSR_minstret: rdata = minstret[31:0];
        CSR_minstreth: rdata = minstret[63:32];

        CSR_mcounteren: rdata = mcounteren;
        CSR_mcountinhibit: rdata = mcountinhibit;

        CSR_mtvec: rdata = mtvec;
        CSR_medeleg: rdata = {16'b0, medeleg};
        CSR_mideleg: rdata = {16'b0, mideleg};

        CSR_mip: rdata = {16'b0, mip};
        CSR_mie: rdata = {16'b0, mie};

        CSR_mscratch: rdata = mscratch;
        CSR_mepc: rdata = mepc;
        CSR_mcause: rdata = mcause;
        CSR_mtval: rdata = mtval;
        CSR_menvcfg: rdata = menvcfg;

        CSR_sstatus: begin
            temp.sie = mstatus.sie;
            temp.spie = mstatus.spie;
            temp.ube = mstatus.ube;
            temp.spp = mstatus.spp;
            temp.vs = mstatus.vs;
            temp.fs_ = mstatus.fs_;
            temp.xs = mstatus.xs;
            temp.sum = mstatus.sum;
            temp.mxr = mstatus.mxr;
            temp.sd = mstatus.sd;
            rdata = temp;
        end

        CSR_scounteren: rdata = scounteren;
        CSR_sepc: rdata = sepc;
        CSR_sscratch: rdata = sscratch;
        CSR_scause: rdata = scause;
        CSR_stval: rdata = stval;
        CSR_stvec: rdata = stvec;

        CSR_sip: begin
            rdata = 0;
            if (mideleg[1]) rdata[1] = mip[1];
            if (mideleg[5]) rdata[5] = mip[5];
            if (mideleg[9]) rdata[9] = mip[9];
        end

        CSR_sie: begin
            rdata = 0;
            if (mideleg[1]) rdata[1] = mie[1];
            if (mideleg[3]) rdata[3] = mie[3];
            if (mideleg[5]) rdata[5] = mie[5];
            if (mideleg[7]) rdata[7] = mie[7];
            if (mideleg[9]) rdata[9] = mie[9];
            if (mideleg[11]) rdata[11] = mie[11];
        end

        CSR_satp: begin
            invalidCSR = mstatus.tvm;
            rdata = satp;
        end
        CSR_senvcfg: rdata = senvcfg;

        CSR_mhpmevent3: rdata = 3;
        CSR_mhpmevent4: rdata = 4;
        CSR_mhpmevent5: rdata = 5;

        CSR_magic: rdata = 32'h88980f;

        // read-only zero CSRs
        CSR_menvcfgh,
        CSR_mvendorid,
        CSR_mconfigptr,
        CSR_mstatush,
        CSR_mhartid,
        CSR_tselect,
        CSR_tdata1,
        CSR_tdata2,
        CSR_tdata3,
        CSR_mcontext: rdata = 0;

        // all unused perf counter stuff, also r/o zero
        CSR_hpmcounter6, CSR_hpmcounter7, CSR_hpmcounter8, CSR_hpmcounter9,
        CSR_hpmcounter10, CSR_hpmcounter11, CSR_hpmcounter12, CSR_hpmcounter13, CSR_hpmcounter14, CSR_hpmcounter15,
        CSR_hpmcounter16, CSR_hpmcounter17, CSR_hpmcounter18, CSR_hpmcounter19, CSR_hpmcounter20, CSR_hpmcounter21,
        CSR_hpmcounter22, CSR_hpmcounter23, CSR_hpmcounter24, CSR_hpmcounter25, CSR_hpmcounter26, CSR_hpmcounter27,
        CSR_hpmcounter28, CSR_hpmcounter29, CSR_hpmcounter30, CSR_hpmcounter31,

        CSR_hpmcounter6h, CSR_hpmcounter7h, CSR_hpmcounter8h,
        CSR_hpmcounter9h, CSR_hpmcounter10h, CSR_hpmcounter11h, CSR_hpmcounter12h, CSR_hpmcounter13h, CSR_hpmcounter14h,
        CSR_hpmcounter15h, CSR_hpmcounter16h, CSR_hpmcounter17h, CSR_hpmcounter18h, CSR_hpmcounter19h, CSR_hpmcounter20h,
        CSR_hpmcounter21h, CSR_hpmcounter22h, CSR_hpmcounter23h, CSR_hpmcounter24h, CSR_hpmcounter25h, CSR_hpmcounter26h,
        CSR_hpmcounter27h, CSR_hpmcounter28h, CSR_hpmcounter29h, CSR_hpmcounter30h, CSR_hpmcounter31h,

        CSR_mhpmcounter6, CSR_mhpmcounter7, CSR_mhpmcounter8,
        CSR_mhpmcounter9, CSR_mhpmcounter10, CSR_mhpmcounter11, CSR_mhpmcounter12, CSR_mhpmcounter13, CSR_mhpmcounter14,
        CSR_mhpmcounter15, CSR_mhpmcounter16, CSR_mhpmcounter17, CSR_mhpmcounter18, CSR_mhpmcounter19, CSR_mhpmcounter20,
        CSR_mhpmcounter21, CSR_mhpmcounter22, CSR_mhpmcounter23, CSR_mhpmcounter24, CSR_mhpmcounter25, CSR_mhpmcounter26,
        CSR_mhpmcounter27, CSR_mhpmcounter28, CSR_mhpmcounter29, CSR_mhpmcounter30, CSR_mhpmcounter31,

        CSR_mhpmcounter6h, CSR_mhpmcounter7h, CSR_mhpmcounter8h,
        CSR_mhpmcounter9h, CSR_mhpmcounter10h, CSR_mhpmcounter11h, CSR_mhpmcounter12h, CSR_mhpmcounter13h, CSR_mhpmcounter14h,
        CSR_mhpmcounter15h, CSR_mhpmcounter16h, CSR_mhpmcounter17h, CSR_mhpmcounter18h, CSR_mhpmcounter19h, CSR_mhpmcounter20h,
        CSR_mhpmcounter21h, CSR_mhpmcounter22h, CSR_mhpmcounter23h, CSR_mhpmcounter24h, CSR_mhpmcounter25h, CSR_mhpmcounter26h,
        CSR_mhpmcounter27h, CSR_mhpmcounter28h, CSR_mhpmcounter29h, CSR_mhpmcounter30h, CSR_mhpmcounter31h,

        CSR_mhpmevent6, CSR_mhpmevent7, CSR_mhpmevent8, CSR_mhpmevent9, CSR_mhpmevent10, CSR_mhpmevent11,
        CSR_mhpmevent12, CSR_mhpmevent13, CSR_mhpmevent14, CSR_mhpmevent15, CSR_mhpmevent16, CSR_mhpmevent17,
        CSR_mhpmevent18, CSR_mhpmevent19, CSR_mhpmevent20, CSR_mhpmevent21, CSR_mhpmevent22, CSR_mhpmevent23,
        CSR_mhpmevent24, CSR_mhpmevent25, CSR_mhpmevent26, CSR_mhpmevent27, CSR_mhpmevent28, CSR_mhpmevent29,
        CSR_mhpmevent30, CSR_mhpmevent31: rdata = 0;

        default: invalidCSR = 1;
    endcase


    // handle HPM counters here to avoid code duplication
    for (integer i = 3; i < NUM_PERFC; i++) begin
        // unprivileged copies
        CSR_Id hpm = CSR_cycle + CSR_Id'(i);
        CSR_Id hpmh = CSR_cycleh + CSR_Id'(i);

        // privileged
        CSR_Id mhpm = CSR_mcycle + CSR_Id'(i);
        CSR_Id mhpmh = CSR_mcycleh + CSR_Id'(i);

        if (IN_uop.imm[11:0] == mhpm || IN_uop.imm[11:0] == mhpmh) begin
            rdata = (IN_uop.imm[11:0] == mhpm) ? mhpmcounter[i][31:0] : mhpmcounter[i][63:32];
            invalidCSR = 0;
        end
        else if (IN_uop.imm[11:0] == hpm || IN_uop.imm[11:0] == hpmh) begin
            invalidCSR = !((priv == PRIV_MACHINE) ||
                (priv == PRIV_SUPERVISOR && mcounteren[i]) ||
                (priv == PRIV_USER && mcounteren[i] && scounteren[i]));
            rdata = (IN_uop.imm[11:0] == hpm) ? mhpmcounter[i][31:0] : mhpmcounter[i][63:32];
        end
    end
end

always_ff@(posedge clk) begin

    // implicit writes
    // CSR writes on trap/interrupt
    if (IN_trapInfo.valid) begin

        reg[31:0] tval = 0;

        if (!IN_trapInfo.isInterrupt)
            case (IN_trapInfo.cause)
                RVP_TRAP_IF_PF,
                RVP_TRAP_IF_AF: tval = IN_trapInfo.finalHalfwPC;
                RVP_TRAP_BREAK: tval = IN_trapInfo.trapPC;

                RVP_TRAP_LD_MA,
                RVP_TRAP_LD_AF,
                RVP_TRAP_LD_PF,
                RVP_TRAP_ST_MA,
                RVP_TRAP_ST_AF,
                RVP_TRAP_ST_PF: tval = IN_tvalState.tval;

                default: ;
            endcase

        if (IN_trapInfo.delegate) begin
            mstatus.spie <= mstatus.sie;
            mstatus.sie <= 0;
            mstatus.spp <= priv[0];
            sepc <= IN_trapInfo.trapPC;
            scause[0+:5] <= IN_trapInfo.cause;
            scause[31] <= IN_trapInfo.isInterrupt;
            stval <= tval;

            priv <= PRIV_SUPERVISOR;
        end
        else begin
            mstatus.mpie <= mstatus.mie;
            mstatus.mie <= 0;
            mstatus.mpp <= priv;
            mepc <= IN_trapInfo.trapPC;
            mcause[0+:5] <= IN_trapInfo.cause;
            mcause[4] <= 0;
            mcause[31] <= IN_trapInfo.isInterrupt;
            mtval <= tval;

            priv <= PRIV_MACHINE;
        end

        //$display("trap: pc=%x, dst=%x, cause=%x", IN_trapInfo.trapPC, {mtvec.base, 2'b0}, IN_trapInfo.cause);
    end

    // Other implicit writes
    fflags <= fflags | IN_fpNewFlags;

    if (!mcountinhibit[0])
        mcycle <= mcycle + 1;

    // MTIP
    mip[7] <= IF_mmio.mtime >= IF_mmio.mtimecmp;
    mip[11] <= IN_irq;

    if (!mcountinhibit[2]) begin
        reg[2:0] temp = 0;
        for (integer i = 0; i < `DEC_WIDTH; i=i+1)
            if (IN_perfcInfo.validRetire[i]) temp = temp + 1;
        minstret <= minstret + {32'b0, 29'b0, temp};
    end

    if (!mcountinhibit[3]) begin
        reg[2:0] temp = 0;
        for (integer i = 0; i < `DEC_WIDTH; i=i+1)
            if (IN_perfcInfo.branchRetire[i]) temp = temp + 1;
        mhpmcounter[3] <= mhpmcounter[3] + {32'b0, 29'b0, temp};
    end

    if (!mcountinhibit[4] && IN_branchMispr)
        mhpmcounter[4] <= mhpmcounter[4] + 1;

    if (!mcountinhibit[5] && IN_branch.taken)
        mhpmcounter[5] <= mhpmcounter[5] + 1;

    // Mispredict Cause Counters
    if (IN_branch.taken && !mcountinhibit[6 + IN_branch.cause])
        mhpmcounter[6 + IN_branch.cause] <= mhpmcounter[6 + IN_branch.cause] + 1;

    // Stall Cause Counters
    if (IN_perfcInfo.stallCause != STALL_NONE)
        mhpmcounter[11 + IN_perfcInfo.stallCause] <=
            mhpmcounter[11 + IN_perfcInfo.stallCause] + 64'(IN_perfcInfo.stallWeigth) + 1;

    if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin

        OUT_uop.valid <= 1;
        OUT_uop.doNotCommit <= 0;
        OUT_uop.flags <= FLAGS_NONE;
        OUT_uop.sqN <= IN_uop.sqN;
        OUT_uop.tagDst <= IN_uop.tagDst;

        if (IN_uop.opcode == CSR_MRET || IN_uop.opcode == CSR_SRET) begin

            OUT_uop.flags <= FLAGS_XRET;

            if (IN_uop.opcode == CSR_MRET) begin

                if (priv < PRIV_MACHINE)
                    OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                else begin
                    mstatus.mie <= mstatus.mpie;
                    mstatus.mpie <= 1;
                    priv <= mstatus.mpp;
                    mstatus.mpp <= PRIV_USER;
                    if (mstatus.mpp != PRIV_MACHINE)
                        mstatus.mprv <= 0;

                    retvec <= mepc[31:1];
                end
            end
            else begin
                if (priv < PRIV_SUPERVISOR || (IN_uop.opcode == CSR_SRET && mstatus.tsr == 1))
                    OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                else begin
                    mstatus.sie <= mstatus.spie;
                    mstatus.spie <= 1;
                    priv <= PrivLevel'({1'b0, mstatus.spp});
                    mstatus.spp <= 1'b0;
                    mstatus.mprv <= 0;

                    retvec <= sepc[31:1];
                end
            end

        end
        else begin
            if ($unsigned(priv) < IN_uop.imm[9:8] || invalidCSR) begin
                OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
            end
            else begin
                // Do write?
                if (IN_uop.opcode != CSR_R) begin
                    reg[31:0] wdata;

                    // For CSRs with out-of-order implicit reads, we need to flush the pipeline
                    case (IN_uop.imm[11:0])
                        CSR_fflags,
                        CSR_frm,
                        CSR_fcsr,

                        CSR_sstatus,
                        CSR_sie,
                        //CSR_stvec,
                        CSR_scounteren,
                        CSR_senvcfg,
                        //CSR_sscratch,
                        //CSR_sepc,
                        //CSR_scause,
                        //CSR_stval,
                        CSR_sip,
                        CSR_satp,
                        //CSR_scontext,

                        CSR_mstatus,
                        CSR_misa,
                        //CSR_medeleg,
                        CSR_mideleg,
                        CSR_mie,
                        //CSR_mtvec,
                        CSR_mcounteren,
                        CSR_mstatush,
                        //CSR_mscratch,
                        //CSR_mepc,
                        //CSR_mcause,
                        //CSR_mtval,
                        CSR_mip,
                        //CSR_mtinst,
                        //CSR_mtval2,
                        CSR_menvcfg
                        //CSR_menvcfgh,
                        //CSR_mseccfg,
                        //CSR_mseccfgh,
                        : OUT_uop.flags <= FLAGS_ORDERING;

                        default: ;
                    endcase

                    // Don't write to read-only CSRs (this could already be handled in decode)
                    if (IN_uop.imm[11:10] == 2'b11)
                        OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                    else begin
                        case (IN_uop.opcode)

                            CSR_RW: wdata = IN_uop.srcA;
                            CSR_RW_I: wdata = {27'b0, IN_uop.imm[16:12]};

                            CSR_RS: wdata = rdata | IN_uop.srcA;
                            CSR_RS_I: wdata = rdata | {27'b0, IN_uop.imm[16:12]};

                            CSR_RC: wdata = rdata & (~IN_uop.srcA);
                            CSR_RC_I: wdata = rdata & (~{27'b0, IN_uop.imm[16:12]});

                            default: begin end
                        endcase

                        for (integer i = 3; i <= 11; i=i+1) begin
                            if (IN_uop.imm[11:0] == CSR_Id'(i) + CSR_mcycle)
                                mhpmcounter[i][31:0] <= wdata;
                            if (IN_uop.imm[11:0] == CSR_Id'(i) + CSR_mcycleh)
                                mhpmcounter[i][63:32] <= wdata;
                        end
                        case (IN_uop.imm[11:0])
`ifdef ENABLE_FP
                            CSR_fflags: fflags <= wdata[4:0];
                            CSR_frm: frm <= wdata[2:0];
                            CSR_fcsr: {frm, fflags} <= wdata[7:0];
`endif
                            CSR_mstatus: begin
                                MStatus_t temp = wdata;

                                mstatus.tsr <= temp.tsr;
                                mstatus.tw <= temp.tw;
                                mstatus.tvm <= temp.tvm;
                                mstatus.mxr <= temp.mxr;
                                mstatus.sum <= temp.sum;
                                mstatus.mprv <= temp.mprv;

                                mstatus.sie <= temp.sie;
                                mstatus.mie <= temp.mie;
                                mstatus.spie <= temp.spie;
                                mstatus.mpie <= temp.mpie;
                                mstatus.spp <= temp.spp;
                                mstatus.mpp <= temp.mpp;

                                mstatus.fs_ <= temp.fs_;
                                mstatus.sd <= |temp.fs_;
                            end

                            CSR_mcycle: mcycle[31:0] <= wdata;
                            CSR_mcycleh: mcycle[63:32] <= wdata;

                            CSR_minstret: minstret[31:0] <= wdata;
                            CSR_minstreth: minstret[63:32] <= wdata;

                            CSR_mcounteren: mcounteren[31:0] <= wdata[31:0];
                            CSR_mcountinhibit: begin
                                // do not allow disabling counters in verilator
                                // simulation for performance measurement.
                                `ifndef VERILATOR
                                mcountinhibit <= wdata;
                                `endif
                            end

                            CSR_mtvec: begin
                                mtvec.base <= wdata[31:2];
                                //mtvec.mode[0] <= wdata[0];
                            end
                            CSR_menvcfg: begin
                                MEnvCfg_t temp = wdata;

                                menvcfg.fiom <= temp.fiom;
                                menvcfg.cbie <= (temp.cbie == 2'b10) ? 0 : temp.cbie;
                                menvcfg.cbcfe <= temp.cbcfe;
                                menvcfg.cbze <= 0;//wdata.cbze;
                            end

                            CSR_medeleg: medeleg <= wdata[15:0];
                            CSR_mideleg: mideleg <= wdata[15:0];

                            CSR_mip: begin
                                mip[1] <= wdata[1];
                                // mip[3] <= wdata[3];   // MSIP
                                mip[5] <= wdata[5];
                                //mip[7] <= wdata[7];    // timer
                                mip[9] <= wdata[9];
                                // mip[11] <= wdata[11]; // external
                            end
                            CSR_mie: begin
                                mie[1] <= wdata[1];
                                mie[3] <= wdata[3];
                                mie[5] <= wdata[5];
                                mie[7] <= wdata[7];
                                mie[9] <= wdata[9];
                                mie[11] <= wdata[11];
                            end

                            CSR_mscratch: mscratch <= wdata;

                            CSR_mepc: mepc[31:1] <= wdata[31:1];
                            CSR_mcause: begin
                                mcause[4:0] <= wdata[4:0];
                                mcause[31] <= wdata[31];
                            end
                            CSR_mtval: mtval <= wdata;

                            CSR_misa: begin
                                misa_X <= wdata[23];
                            end

                            CSR_sstatus: begin
                                MStatus_t temp = wdata;

                                mstatus.mxr <= temp.mxr;
                                mstatus.sum <= temp.sum;

                                mstatus.sie <= temp.sie;
                                mstatus.spie <= temp.spie;
                                mstatus.spp <= temp.spp;
                            end

                            CSR_scounteren: scounteren[31:0] <= wdata[31:0];
                            CSR_sepc: sepc[31:1] <= wdata[31:1];
                            CSR_sscratch: sscratch <= wdata;
                            CSR_scause: begin
                                scause[0+:5] <= wdata[0+:5];
                                scause[31] <= wdata[31];
                            end
                            CSR_stval: stval <= wdata;
                            CSR_stvec: begin
                                stvec.base <= wdata[31:2];
                                //stvec.mode[0] <= wdata[0];
                            end

                            CSR_sip: begin
                                if (mideleg[1]) mip[1] <= wdata[1];
                                // mip[3] <= wdata[3];   // MSIP
                                if (mideleg[5]) mip[5] <= wdata[5];
                                //mip[7] <= wdata[7];    // timer
                                if (mideleg[9]) mip[9] <= wdata[9];
                                // mip[11] <= wdata[11]; // external
                            end

                            CSR_sie: begin
                                if (mideleg[1]) mie[1] <= wdata[1];
                                if (mideleg[3]) mie[3] <= wdata[3];
                                if (mideleg[5]) mie[5] <= wdata[5];
                                if (mideleg[7]) mie[7] <= wdata[7];
                                if (mideleg[9]) mie[9] <= wdata[9];
                                if (mideleg[11]) mie[11] <= wdata[11];
                            end

                            CSR_satp: begin
                                satp <= wdata;
                                // we only support 32 bits of physical address space.
                                satp.ppn[21:20] <= 2'b0;
                                satp.asid <= 0;
                            end

                            CSR_senvcfg: begin
                                MEnvCfg_t temp = wdata;

                                senvcfg.fiom <= temp.fiom;
                                senvcfg.cbie <= (temp.cbie == 2'b10) ? 0 : temp.cbie;
                                senvcfg.cbcfe <= temp.cbcfe;
                                senvcfg.cbze <= 0;//wdata.cbze;
                            end

                            default: begin end
                        endcase
                    end
                end

                // Do read?
                if (!IN_uop.tagDst[$bits(Tag)-1]) begin
                    OUT_uop.result <= rdata;
                    // read side effects
                end
            end
        end
    end
    else begin
        OUT_uop.valid <= 0;
    end

    if (rst) begin
        priv <= PRIV_MACHINE;
        fflags <= 0;
        frm <= 0;

        mstatus <= 0;
        mcycle <= 0;
        minstret <= 0;
        mcounteren <= 0;
        mcountinhibit <= 0;
        mtvec.base <= 30'((`ENTRY_POINT) >> 2);
        mtvec.mode <= 0;
        mepc <= 0;
        mcause <= 0;
        mtval <= 0;
        mideleg <= 0;
        medeleg <= 0;
        mip <= 0;
        mie <= 0;
        menvcfg <= 0;

        scounteren <= 0;
        sepc <= 0;
        scause <= 0;
        stval <= 0;
        stvec.base <= 30'((`ENTRY_POINT) >> 2);
        stvec.mode <= 0;
        satp <= 0;
        senvcfg <= 0;

        for (integer i = 0; i < NUM_PERFC; i=i+1)
            mhpmcounter[i] <= 0;

        OUT_uop.valid <= 0;

        misa_X <= 1;
    end
end

endmodule
