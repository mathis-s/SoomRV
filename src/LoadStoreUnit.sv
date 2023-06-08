module LoadStoreUnit
(
    input wire clk,
    input wire rst,
    
    input BranchProv IN_branch,
    output wire OUT_ldStall,
    output wire OUT_stStall,
    
    input LD_UOp IN_uopLd,
    input ST_UOp IN_uopSt,

    // Forwarded data from store queue
    input wire[3:0] IN_SQ_lookupMask,
    input wire[31:0] IN_SQ_lookupData,
    
    IF_Mem.HOST IF_mem,
    IF_MMIO.HOST IF_mmio,

    output MemController_Req OUT_memc,
    input MemController_Res IN_memc,
    
    output RES_UOp OUT_uopLd,
    output PW_LD_RES_UOp OUT_uopPwLd,
    
    output wire OUT_loadFwdValid,
    output Tag OUT_loadFwdTag
);

wire BLSU_stStall;
reg stStall;
assign OUT_stStall = BLSU_stStall || stStall;

typedef struct packed
{
    logic[31:0] data;
    logic[3:0] wmask;
    logic[31:0] addr;
    logic signExtend;
    logic[1:0] size;
    Tag tagDst;
    SqN sqN;
    logic doNotCommit;
    logic external;
    AGU_Exception exception;
    logic isMMIO;
    logic valid;
} Stage;

function Stage ToStage(LD_UOp uop);
    Stage s;
    s = {36'bx, uop};
    return s;
endfunction

Stage uopLd_0;
Stage uopLd_1;

assign OUT_ldStall = BLSU_ldStall;

wire isCacheBypassLdUOp = 
    `ENABLE_EXT_MMIO && IN_uopLd.valid && IN_uopLd.isMMIO && 
    IN_uopLd.addr >= `EXT_MMIO_START_ADDR && IN_uopLd.addr < `EXT_MMIO_END_ADDR;
wire isCacheBypassStUOp = 
    `ENABLE_EXT_MMIO && IN_uopSt.valid && IN_uopSt.isMMIO && 
    IN_uopSt.addr >= `EXT_MMIO_START_ADDR && IN_uopSt.addr < `EXT_MMIO_END_ADDR;

wire BLSU_ldStall;
LD_UOp BLSU_uopLd;
wire[31:0] BLSU_ldResult;
Stage BLSU_stageUOpLd;
assign BLSU_stageUOpLd = {BLSU_ldResult, 4'b1111, BLSU_uopLd};
BypassLSU bypassLSU
(
    .clk(clk),
    .rst(rst),
    
    .IN_branch(IN_branch),
    .IN_uopLdEn(isCacheBypassLdUOp),
    .OUT_ldStall(BLSU_ldStall),
    .IN_uopLd(IN_uopLd),

    .IN_uopStEn(isCacheBypassStUOp),
    .OUT_stStall(BLSU_stStall),
    .IN_uopSt(IN_uopSt),

    .IN_ldStall(uopLd_1.valid),
    .OUT_uopLd(BLSU_uopLd),
    .OUT_ldData(BLSU_ldResult),

    .OUT_memc(OUT_memc),
    .IN_memc(IN_memc)
);

wire forwardUOpLd_0 = (uopLd_0.valid && !uopLd_0.external);
assign OUT_loadFwdValid = forwardUOpLd_0 || (!IN_uopLd.external && IN_uopLd.valid && IN_SQ_lookupMask == 4'b1111 && !uopLd_0.valid);
assign OUT_loadFwdTag = forwardUOpLd_0 ? uopLd_0.tagDst : IN_uopLd.tagDst;

always_comb begin
    IF_mmio.wdata = IF_mem.wdata;
    IF_mmio.wmask = IF_mem.wmask;
end

wire doRead = IN_uopLd.valid && (IN_uopLd.external || !IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0) &&
    (IN_SQ_lookupMask != 4'b1111 || IN_uopLd.external) && !isCacheBypassLdUOp;

always_comb begin
    
    stStall = 0;
    
    IF_mmio.raddr = IN_uopLd.addr;
    IF_mmio.rsize = IN_uopLd.size;
    IF_mmio.waddr = IN_uopSt.addr;
    
    IF_mem.raddr = IN_uopLd.addr[31:2];
    IF_mem.waddr = IN_uopSt.addr[31:2];
    IF_mem.wdata = IN_uopSt.data;
    IF_mem.wmask = IN_uopSt.wmask;
    
    IF_mem.we = 1;
    IF_mmio.we = 1;

    IF_mem.re = 1;
    IF_mmio.re = 1;
        
    // Load
    if (doRead) begin
        if (IN_uopLd.isMMIO)
            IF_mmio.re = 0;
        else
            IF_mem.re = 0;
    end

    // Store
    if (IN_uopSt.valid && !isCacheBypassStUOp) begin
        if (IN_uopSt.isMMIO) begin
            stStall = IF_mmio.wbusy;
            IF_mmio.we = stStall;
        end
        else begin
            
            // do not issue two ops at the same address at once
            // FIXME: compare only as many bits as required
            if (doRead && !IN_uopLd.isMMIO && IN_uopLd.addr[31:2] == IN_uopSt.addr[31:2]) begin
                stStall = 1;
            end
            else begin
                stStall = IF_mem.wbusy;
                IF_mem.we = 0;
            end
        end
    end
end

always_comb begin
    
    Stage ld = uopLd_1.valid ? uopLd_1 : BLSU_stageUOpLd;
    reg[31:0] result = 32'bx;
    reg[31:0] data;

    data[31:24] = ld.wmask[3] ? ld.data[31:24] : 
        (ld.isMMIO ?  IF_mmio.rdata[31:24] : IF_mem.rdata[31:24]);
    data[23:16] = ld.wmask[2] ? ld.data[23:16] : 
        (ld.isMMIO ? IF_mmio.rdata[23:16] : IF_mem.rdata[23:16]);
    data[15:8] = ld.wmask[1] ? ld.data[15:8] : 
        (ld.isMMIO ? IF_mmio.rdata[15:8] : IF_mem.rdata[15:8]);
    data[7:0] = ld.wmask[0] ? ld.data[7:0] : 
        (ld.isMMIO ? IF_mmio.rdata[7:0] : IF_mem.rdata[7:0]);
    
    case (ld.size)
        
        0: begin
            case (ld.addr[1:0])
                0: result[7:0] = data[7:0];
                1: result[7:0] = data[15:8];
                2: result[7:0] = data[23:16];
                3: result[7:0] = data[31:24];
            endcase
            
            result[31:8] = {24{ld.signExtend ? result[7] : 1'b0}};
        end
        
        1: begin
            case (ld.addr[1:0])
                default: result[15:0] = data[15:0];
                2: result[15:0] = data[31:16];
            endcase
            
            result[31:16] = {16{ld.signExtend ? result[15] : 1'b0}};
        end
        
        default: result = data;
    endcase
    
    OUT_uopLd = 'x;
    OUT_uopPwLd = 'x;
    
    OUT_uopLd.valid = ld.valid && !ld.external;
    OUT_uopPwLd.valid = ld.valid && ld.external;
    
    if (OUT_uopLd.valid) begin
        OUT_uopLd.result = result;
        OUT_uopLd.tagDst = ld.tagDst;
        OUT_uopLd.sqN = ld.sqN;
        case (ld.exception)
            AGU_NO_EXCEPTION: OUT_uopLd.flags = FLAGS_NONE;
            AGU_ADDR_MISALIGN: OUT_uopLd.flags = FLAGS_LD_MA;
            AGU_ACCESS_FAULT: OUT_uopLd.flags = FLAGS_LD_AF;
            AGU_PAGE_FAULT: OUT_uopLd.flags = FLAGS_LD_PF;
        endcase
        OUT_uopLd.doNotCommit = ld.doNotCommit;
    end
    
    if (OUT_uopPwLd.valid) begin
        OUT_uopPwLd.data = result;
    end
end

always_ff@(posedge clk) begin
    
    if (rst) begin
        uopLd_0.valid <= 0;
        uopLd_1.valid <= 0;
    end
    else begin
        uopLd_0.valid <= 0;
        uopLd_1.valid <= 0;
        
        if (uopLd_0.valid && (uopLd_0.external || !IN_branch.taken || $signed(uopLd_0.sqN - IN_branch.sqN) <= 0)) begin
            uopLd_1 <= uopLd_0;
        end
        
        if (IN_uopLd.valid && (IN_uopLd.external || !IN_branch.taken || $signed(IN_uopLd.sqN - IN_branch.sqN) <= 0)) begin
            
            // Loads that are entirely forwarded from the store queue can be written back one cycle earlier.
            if (IN_SQ_lookupMask == 4'b1111 && !(uopLd_0.valid && (uopLd_0.external || !IN_branch.taken || $signed(uopLd_0.sqN - IN_branch.sqN) <= 0)) && !IN_uopLd.external) begin
                uopLd_1 <= ToStage(IN_uopLd);
                uopLd_1.wmask <= IN_SQ_lookupMask;
                uopLd_1.data <= IN_SQ_lookupData;
            end
            else begin
                if (!isCacheBypassLdUOp) begin
                    uopLd_0 <= ToStage(IN_uopLd);
                    uopLd_0.wmask <= IN_uopLd.external ? 4'b0000 : IN_SQ_lookupMask;
                    uopLd_0.data <= IN_SQ_lookupData;
                end
            end
        end
    end

end

endmodule
