module CSR#(parameter NUM_FLOAT_FLAG_UPD = 2)
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input EX_UOp IN_uop,
    input BranchProv IN_branch,
    
    input wire[4:0] IN_fpNewFlags,
    
    // for minstret
    input wire[3:0] IN_commitValid,
    
    input TrapInfoUpdate IN_trapInfo,
    output TrapControlState OUT_trapControl,
    output wire[2:0] OUT_fRoundMode,
    
    output RES_UOp OUT_uop
);

integer i;

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
    
    CSR_mcounterinhibit=12'h320,
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
    CSR_mhpmevent31=12'h33F
} CSRAddr;

PrivLevel priv;


reg[4:0] fflags;
reg[2:0] frm;

reg[63:0] mcycle;
reg[63:0] minstret;

typedef struct packed
{
    bit sd; // state dirty
    bit[7:0] wpri23;
    bit tsr; // trap sret
    bit tw; // timeout wait (1 -> illegal instr on wfi)
    bit tvm; // trap virtual memory
    bit mxr; // make exectuable readable, 0 if s mode not supported
    bit sum; // permit supervisor user memory access
    bit mprv; // memory privilege (1 -> ld/st memory access via mode in MPP), 0 if u mode not supported
    bit[1:0] xs; // extended register state
    bit[1:0] fs_; // floating point register state
    PrivLevel mpp; // machine prior privilege
    bit[1:0] vs; // vector register state
    bit spp; // supervisor prior privilege 
    bit mpie; // machine prior interrupt enable
    bit ube; // user big endian
    bit spie; // supervisor prior interrupt enable
    bit wpri4;
    bit mie; // machine interrupt enable
    bit wpri2;
    bit sie; // supervisor interrupt enable
    bit wpri0;
} MStatus_t;

MStatus_t mstatus;

typedef struct packed
{
    bit[29:0] base;
    bit[1:0] mode;
} TVec_t;

TVec_t mtvec;
TVec_t stvec;

reg[31:0] mscratch;

reg[31:0] mepc;
reg[31:0] mcause;
reg[31:0] mtval;
reg[15:0] medeleg;
reg[15:0] mideleg;
reg[31:0] mcounteren;

reg[31:0] scounteren;
reg[31:0] sepc;
reg[31:0] sscratch;
reg[31:0] scause;
reg[31:0] stval;

reg[30:0] retvec;

assign OUT_trapControl.mvectord = mtvec.mode[0];
assign OUT_trapControl.mtvec = mtvec.base;
assign OUT_trapControl.svectord = stvec.mode[0];
assign OUT_trapControl.stvec = stvec.base;
assign OUT_trapControl.retvec = retvec;
assign OUT_trapControl.mideleg = mideleg;
assign OUT_trapControl.medeleg = medeleg;
assign OUT_trapControl.priv = priv;
assign OUT_fRoundMode = frm;

reg[31:0] rdata;
reg invalidCSR;
always_comb begin
    invalidCSR = 0;
    rdata = 32'bx;
    
    case (IN_uop.imm[11:0])
    
        CSR_fflags: rdata = {27'b0, fflags};
        CSR_frm: rdata = {29'b0, frm};
        CSR_fcsr: rdata = {24'b0, frm, fflags};
        
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
            rdata = mcycle[31:0];
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
            rdata = minstret[31:0];
        end
        
        CSR_misa: rdata = 32'b01_0000_11100000100010000000000100;
        CSR_marchid: rdata = 32'h50087501;
        CSR_mimpid: rdata = 32'h50087532;
        CSR_mstatus: rdata = mstatus;
        
        CSR_mcycle: rdata = mcycle[31:0];
        CSR_mcycleh: rdata = mcycle[63:32];
        
        CSR_minstret: rdata = minstret[31:0];
        CSR_minstreth: rdata = minstret[63:32];
        
        CSR_mcounteren: rdata = mcounteren;
        
        CSR_mtvec: rdata = mtvec;
        CSR_medeleg: rdata = {16'b0, medeleg};
        CSR_mideleg: rdata = {16'b0, mideleg};
        CSR_mscratch: rdata = mscratch;
        CSR_mepc: rdata = mepc;
        CSR_mcause: rdata = mcause;
        CSR_mtval: rdata = mtval;
        
        CSR_scounteren: rdata = scounteren;
        CSR_sepc: rdata = sepc;
        CSR_sscratch: rdata = sscratch;
        CSR_scause: rdata = scause;
        CSR_stval: rdata = stval;
        CSR_stvec: rdata = stvec;
        
        CSR_mhpmevent3: rdata = 3;
        CSR_mhpmevent4: rdata = 4;
        CSR_mhpmevent5: rdata = 5;
        
        // read-only zero CSRs
        CSR_mcounterinhibit,
        CSR_mvendorid,
        CSR_mconfigptr,
        CSR_mstatush,
        CSR_mhartid: rdata = 0;
        
        // all unused perf counter stuff, also r/o zero
        CSR_hpmcounter3, CSR_hpmcounter4, CSR_hpmcounter5, CSR_hpmcounter6, CSR_hpmcounter7, CSR_hpmcounter8, CSR_hpmcounter9,
        CSR_hpmcounter10, CSR_hpmcounter11, CSR_hpmcounter12, CSR_hpmcounter13, CSR_hpmcounter14, CSR_hpmcounter15,
        CSR_hpmcounter16, CSR_hpmcounter17, CSR_hpmcounter18, CSR_hpmcounter19, CSR_hpmcounter20, CSR_hpmcounter21,
        CSR_hpmcounter22, CSR_hpmcounter23, CSR_hpmcounter24, CSR_hpmcounter25, CSR_hpmcounter26, CSR_hpmcounter27,
        CSR_hpmcounter28, CSR_hpmcounter29, CSR_hpmcounter30, CSR_hpmcounter31, 
        
        CSR_hpmcounter3h, CSR_hpmcounter4h, CSR_hpmcounter5h, CSR_hpmcounter6h, CSR_hpmcounter7h, CSR_hpmcounter8h,
        CSR_hpmcounter9h, CSR_hpmcounter10h, CSR_hpmcounter11h, CSR_hpmcounter12h, CSR_hpmcounter13h, CSR_hpmcounter14h,
        CSR_hpmcounter15h, CSR_hpmcounter16h, CSR_hpmcounter17h, CSR_hpmcounter18h, CSR_hpmcounter19h, CSR_hpmcounter20h,
        CSR_hpmcounter21h, CSR_hpmcounter22h, CSR_hpmcounter23h, CSR_hpmcounter24h, CSR_hpmcounter25h, CSR_hpmcounter26h,
        CSR_hpmcounter27h, CSR_hpmcounter28h, CSR_hpmcounter29h, CSR_hpmcounter30h, CSR_hpmcounter31h,
        
        CSR_mhpmcounter3, CSR_mhpmcounter4, CSR_mhpmcounter5, CSR_mhpmcounter6, CSR_mhpmcounter7, CSR_mhpmcounter8,
        CSR_mhpmcounter9, CSR_mhpmcounter10, CSR_mhpmcounter11, CSR_mhpmcounter12, CSR_mhpmcounter13, CSR_mhpmcounter14,
        CSR_mhpmcounter15, CSR_mhpmcounter16, CSR_mhpmcounter17, CSR_mhpmcounter18, CSR_mhpmcounter19, CSR_mhpmcounter20,
        CSR_mhpmcounter21, CSR_mhpmcounter22, CSR_mhpmcounter23, CSR_mhpmcounter24, CSR_mhpmcounter25, CSR_mhpmcounter26,
        CSR_mhpmcounter27, CSR_mhpmcounter28, CSR_mhpmcounter29, CSR_mhpmcounter30, CSR_mhpmcounter31,
 
        CSR_mhpmcounter3h, CSR_mhpmcounter4h, CSR_mhpmcounter5h, CSR_mhpmcounter6h, CSR_mhpmcounter7h, CSR_mhpmcounter8h,
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
end

always_ff@(posedge clk) begin
    
    // implicit writes
    if (!rst) begin
        if (IN_trapInfo.valid) begin
            if (IN_trapInfo.delegate) begin
                mstatus.spie <= mstatus.sie;
                mstatus.sie <= 0;
                mstatus.spp <= priv[0];
                sepc <= IN_trapInfo.trapPC;
                scause[3:0] <= IN_trapInfo.cause;
                scause[31] <= IN_trapInfo.isInterrupt;
                stval <= 0;
                
                priv <= PRIV_SUPERVISOR;
            end
            else begin
                mstatus.mpie <= mstatus.mie;
                mstatus.mie <= 0;
                mstatus.mpp <= priv;
                mepc <= IN_trapInfo.trapPC;
                mcause[3:0] <= IN_trapInfo.cause;
                mcause[31] <= IN_trapInfo.isInterrupt;
                mtval <= 0;
                
                priv <= PRIV_MACHINE;
            end
        end
        fflags <= fflags | IN_fpNewFlags;
        mcycle <= mcycle + 1;
        
        begin
            reg[2:0] temp = 0;
            for (i = 0; i < 4; i=i+1)
                if (IN_commitValid[i]) temp = temp + 1;
            minstret <= minstret + {32'b0, 29'b0, temp};
        end
    end
    
    if (rst) begin
        priv <= PRIV_MACHINE;
        fflags <= 0;
        frm <= 0;
        
        mstatus <= 0;
        mcycle <= 0;
        minstret <= 0;
        mcounteren <= 0;
        mtvec <= 0;
        mepc <= 0;
        mcause <= 0;
        mtval <= 0;
        mideleg <= 0;
        medeleg <= 0;
        
        scounteren <= 0;
        sepc <= 0;
        scause <= 0;
        stval <= 0;
        stvec <= 0;
        
        OUT_uop.valid <= 0;
    end
    else if (en && IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
    
        OUT_uop.valid <= 1;
        OUT_uop.compressed <= IN_uop.compressed;
        OUT_uop.doNotCommit <= 0;
        OUT_uop.flags <= FLAGS_NONE;
        OUT_uop.pc <= IN_uop.pc;
        OUT_uop.sqN <= IN_uop.sqN;
        OUT_uop.nmDst <= IN_uop.nmDst;
        OUT_uop.tagDst <= IN_uop.tagDst;
        
        if (IN_uop.opcode == CSR_MRET || IN_uop.opcode == CSR_SRET) begin
            
            OUT_uop.flags <= FLAGS_XRET;
            
            if (IN_uop.opcode == CSR_SRET && mstatus.tsr == 1)
                OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                
            if (IN_uop.opcode == CSR_MRET) begin
                
                if (priv < PRIV_MACHINE)
                    OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                    
                mstatus.mie <= mstatus.mpie;
                priv <= mstatus.mpp;
                mstatus.mpp <= PRIV_USER;
                mstatus.mprv <= 0;
                
                retvec <= mepc[31:1];
            end
            else begin
                if (priv < PRIV_SUPERVISOR)
                    OUT_uop.flags <= FLAGS_ILLEGAL_INSTR;
                
                mstatus.sie <= mstatus.spie;
                priv <= PrivLevel'({1'b0, mstatus.spp});
                mstatus.spp <= 1'b0;
                mstatus.mprv <= 0;
                
                retvec <= sepc[31:1];
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
                    
                    // TODO: writes to CSR without implicit reads do not need ordering
                    OUT_uop.flags <= FLAGS_ORDERING;
                    
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
                        
                        case (IN_uop.imm[11:0])
                        
                            CSR_fflags: fflags <= wdata[4:0];
                            CSR_frm: frm <= wdata[2:0];
                            CSR_fcsr: {frm, fflags} <= wdata[7:0];
                            
                            CSR_mstatus: begin
                                MStatus_t temp = wdata;
                                mstatus.sie <= temp.sie;
                                mstatus.mie <= temp.mie;
                                mstatus.spie <= temp.spie;
                                mstatus.mpie <= temp.mpie;
                                mstatus.spp <= temp.spp;
                                mstatus.mpp <= temp.mpp;
                                mstatus.mprv <= temp.mprv;
                            end
                            
                            CSR_mcycle: mcycle[31:0] <= wdata;
                            CSR_mcycleh: mcycle[63:32] <= wdata;
                            
                            CSR_minstret: minstret[31:0] <= wdata;
                            CSR_minstreth: minstret[63:32] <= wdata;
                            
                            CSR_mcounteren: mcounteren[5:0] <= wdata[5:0];
                            
                            CSR_mtvec: begin
                                mtvec.base <= wdata[31:2];
                                mtvec.mode[0] <= wdata[0];
                            end
                            
                            CSR_medeleg: medeleg <= wdata[15:0];
                            CSR_mideleg: mideleg <= wdata[15:0];
                            
                            CSR_mscratch: mscratch <= wdata;
                            
                            CSR_mepc: mepc[31:1] <= wdata[31:1];
                            CSR_mcause: begin
                                mcause[3:0] <= wdata[3:0];
                                mcause[31] <= wdata[31];
                            end
                            CSR_mtval: mtval <= wdata;
                            
                            CSR_scounteren: scounteren[5:0] <= wdata[5:0];
                            
                            CSR_sepc: sepc[31:1] <= wdata[31:1];
                            CSR_sscratch: sscratch <= wdata;
                            CSR_scause: begin
                                scause[4:0] <= wdata[4:0];
                                scause[31] <= wdata[31];
                            end
                            CSR_stval: stval <= wdata;
                            CSR_stvec: begin
                                stvec.base <= wdata[31:2];
                                stvec.mode[0] <= wdata[0];
                            end
                            
                            default: begin end
                        endcase
                    end
                end
                
                // Do read?
                if ((IN_uop.opcode != CSR_RW && IN_uop.opcode != CSR_RW_I) || IN_uop.nmDst != 0) begin
                    OUT_uop.result <= rdata;
                    // read side effects
                end
            end
        end
    end
    else begin
        OUT_uop.valid <= 0;
    end
end

endmodule















