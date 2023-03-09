module CSR#(parameter NUM_FLOAT_FLAG_UPD = 2)
(
    input wire clk,
    input wire rst,
    input wire en,
    
    input EX_UOp IN_uop,
    input BranchProv IN_branch,
    
    input wire[4:0] IN_fpNewFlags,
    
    input TrapInfoUpdate IN_trapInfo,
    output TrapControlState OUT_trapControl,
    output wire[2:0] OUT_fRoundMode,
    
    output RES_UOp OUT_uop
);


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
    //...
    CSR_hpmcounter31=12'hC1F,
    
    CSR_cycleh=12'hC80,
    CSR_timeh=12'hC81,
    CSR_instreth=12'hC82,
    CSR_hpmcounter3h=12'hC83,
    CSR_hpmcounter4h=12'hC84,
    CSR_hpmcounter5h=12'hC85,
    CSR_hpmcounter6h=12'hC86,
    CSR_hpmcounter7h=12'hC87,
    //...
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
    // ...
    CSR_mhpmcounter31=12'hB1F,
    
    CSR_mcycleh=12'hB80,
    CSR_minstreth=12'hB82,
    CSR_mhpmcounter3h=12'hB83,
    CSR_mhpmcounter4h=12'hB84,
    // ...
    CSR_mhpmcounter31h=12'hB9F,
    
    CSR_mcounterinhibit=12'h320,
    CSR_mhpmevent3=12'h323,
    CSR_mhpmevent4=12'h324,
    // ...
    CSR_mhpmevent31=12'h33F
} CSRAddr;

struct packed
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
    bit[1:0] mpp; // machine prior privilege
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
} mstatus;

struct packed
{
    bit[29:0] base;
    bit[1:0] mode;
} mtvec;

reg[63:0] mcycle;
reg[63:0] minstret;

reg[31:0] mepc;
reg[31:0] mcause;
reg[31:0] mtval;

reg[31:0] rdata;

reg[4:0] fflags;
reg[2:0] frm;

assign OUT_trapControl.vectord = mtvec.mode[0];
assign OUT_trapControl.tvec = mtvec.base;
assign OUT_fRoundMode = frm;

always_comb begin
    case (IN_uop.imm[11:0])
        CSR_misa: rdata = 32'b01_0000_11100000100010000000000100;
        CSR_marchid: rdata = 32'h50087501;
        CSR_mimpid: rdata = 32'h50087532;
        
        CSR_mstatus: rdata = mstatus;
        CSR_mtvec: rdata = mtvec;
        CSR_mepc: rdata = mepc;
        CSR_mcause: rdata = mcause;
        CSR_mtval: rdata = mtval;

        CSR_mcycle: rdata = mcycle[31:0];
        CSR_mcycleh: rdata = mcycle[63:32];
        
        CSR_minstret: rdata = minstret[31:0];
        CSR_minstreth: rdata = minstret[63:32];
        
        CSR_fflags: rdata = {27'b0, fflags};
        CSR_frm: rdata = {29'b0, frm};
        CSR_fcsr: rdata = {24'b0, frm, fflags};
        
        //CSR_mcounteren,
        //CSR_mstatush,
        //CSR_mhartid,
        default: rdata = 0;
    endcase
end

always_ff@(posedge clk) begin

    // implicit writes
    if (!rst) begin
    
        if (IN_trapInfo.valid) begin
            mtval <= 0;
            mcause[3:0] <= IN_trapInfo.cause;
            mcause[31] <= IN_trapInfo.isInterrupt;
            mepc <= IN_trapInfo.trapPC;
        end
        
        fflags <= fflags | IN_fpNewFlags;
        mcycle <= mcycle + 1;
    end
    
    if (rst) begin
        mcycle <= 0;
        minstret <= 0;
        mtvec <= 0;
        mepc <= 0;
        mcause <= 0;
        mtval <= 0;
        fflags <= 0;
        frm <= 0;
        // ...
        
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
        
        // Do write?
        if (IN_uop.opcode != CSR_R) begin
            reg[31:0] wdata;
            
            // TODO: writes to CSR without implicit reads do not need ordering
            OUT_uop.flags <= FLAGS_ORDERING;
            
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
                CSR_mcycle: mcycle[31:0] <= wdata;
                CSR_mcycleh: mcycle[63:32] <= wdata;
                
                CSR_minstret: minstret[31:0] <= wdata;
                CSR_minstreth: minstret[63:32] <= wdata;
                
                CSR_mtvec: begin
                    mtvec.base <= wdata[31:2];
                    mtvec.mode[0] <= wdata[0];
                end
                
                CSR_mepc: mepc[31:1] <= wdata[31:1];
                CSR_mcause: begin
                    mcause[3:0] <= wdata[3:0];
                    mcause[31] <= wdata[31];
                end
                CSR_mtval: mtval <= wdata;
                
                CSR_fflags: fflags <= wdata[4:0];
                CSR_frm: frm <= wdata[2:0];
                CSR_fcsr: {frm, fflags} <= wdata[7:0];
                
                default: begin end
            endcase
        end
        
        // Do read?
        if ((IN_uop.opcode != CSR_RW && IN_uop.opcode != CSR_RW_I) || IN_uop.nmDst != 0) begin
            OUT_uop.result <= rdata;
            // read side effects
        end
    end
    else begin
        OUT_uop.valid <= 0;
    end
end

endmodule















