module Core
#(
    parameter NUM_UOPS=2
)
(
    input wire clk,
    input wire rst,
    input wire[63:0] IN_instrRaw,

    input wire[31:0] IN_MEM_readData,
    
    output wire[29:0] OUT_MEM_addr,
    output wire[31:0] OUT_MEM_writeData,
    output wire OUT_MEM_writeEnable,
    output wire OUT_MEM_readEnable,
    output wire[3:0] OUT_MEM_writeMask,
    
    output wire[28:0] OUT_instrAddr,
    output wire OUT_instrReadEnable,
    output wire OUT_halt
);

integer i;

RES_UOp wbUOp[NUM_UOPS-1:0];

wire wbHasResult[NUM_UOPS-1:0];
assign wbHasResult[0] = wbUOp[0].valid && wbUOp[0].nmDst != 0;
assign wbHasResult[1] = wbUOp[1].valid && wbUOp[1].nmDst != 0;

wire[4:0] comRegNm[NUM_UOPS-1:0];
wire[5:0] comRegTag[NUM_UOPS-1:0];
wire[5:0] comSqN[NUM_UOPS-1:0];
wire comValid[NUM_UOPS-1:0];

wire frontendEn;

// IF -> DE -> RN
reg[3:0] stateValid;
assign OUT_instrReadEnable = frontendEn && stateValid[0];

BranchProv branchProvs[2:0];
BranchProv branch;
always_comb begin
    branch.taken = 0;
    branch.sqN = 0;
    for (i = 0; i < 3; i=i+1) begin
        if (branchProvs[i].taken && (!branch.taken || $signed(branchProvs[i].sqN - branch.sqN) < 0)) begin
            branch.taken = 1;
            branch.dstPC = branchProvs[i].dstPC;
            branch.sqN = branchProvs[i].sqN;
            branch.loadSqN = branchProvs[i].loadSqN;
            branch.storeSqN = branchProvs[i].storeSqN;
        end
    end
end

reg disableMispredFlush;
reg mispredFlush;

reg [31:0] IF_pc[NUM_UOPS-1:0];
wire[31:0] IF_instr[NUM_UOPS-1:0];
wire IF_instrValid[NUM_UOPS-1:0];

wire[31:0] PC_pc;
assign OUT_instrAddr = PC_pc[31:3];


wire BP_branchTaken;
wire BP_isJump;
wire[31:0] BP_branchSrc;
wire[31:0] BP_branchDst;
wire[5:0] BP_branchID;
wire BP_multipleBranches;
wire BP_branchFound;

wire[5:0] IF_branchID[NUM_UOPS-1:0];
wire IF_branchPred[NUM_UOPS-1:0];

ProgramCounter progCnt
(
    .clk(clk),
    .en0(stateValid[0] && frontendEn),
    .en1(stateValid[1] && frontendEn),
    .rst(rst),
    .IN_pc(branch.dstPC),
    .IN_write(branch.taken),
    .IN_instr(IN_instrRaw),
    
    .IN_BP_branchTaken(BP_branchTaken),
    .IN_BP_isJump(BP_isJump),
    .IN_BP_branchSrc(BP_branchSrc),
    .IN_BP_branchDst(BP_branchDst),
    .IN_BP_branchID(BP_branchID),
    .IN_BP_multipleBranches(BP_multipleBranches),
    .IN_BP_branchFound(BP_branchFound),
    
    .OUT_pcRaw(PC_pc),
    .OUT_pc(IF_pc),
    .OUT_instr(IF_instr),
    .OUT_branchID(IF_branchID),
    .OUT_branchPred(IF_branchPred),
    .OUT_instrValid(IF_instrValid)
);

wire isBranch;
wire[31:0] branchSource;
wire branchIsJump;
wire[5:0] branchID;
wire branchTaken;
BranchPredictor bp
(
    .clk(clk),
    .rst(rst),
    
    .IN_pcValid(stateValid[0] && frontendEn),
    .IN_pc(PC_pc),
    .OUT_branchTaken(BP_branchTaken),
    .OUT_isJump(BP_isJump),
    .OUT_branchSrc(BP_branchSrc),
    .OUT_branchDst(BP_branchDst),
    .OUT_branchID(BP_branchID),
    .OUT_multipleBranches(BP_multipleBranches),
    .OUT_branchFound(BP_branchFound),
    
    .IN_branchValid(isBranch),
    .IN_branchID(branchID),
    .IN_branchAddr(branchSource),
    .IN_branchDest(branchProvs[1].dstPC),
    .IN_branchTaken(branchTaken),
    .IN_branchIsJump(branchIsJump)
);


wire[5:0] RN_nextSqN;
wire[5:0] ROB_curSqN;

always_ff@(posedge clk) begin
    if (rst) begin
        stateValid <= 4'b0000;
        mispredFlush <= 0;
        disableMispredFlush <= 0;
    end
    else if (branch.taken) begin
        stateValid <= 4'b0000;
        mispredFlush <= (ROB_curSqN != RN_nextSqN);
        disableMispredFlush <= 0;
    end
    // When a branch mispredict happens, we need to let the pipeline
    // run entirely dry.
    else if (mispredFlush) begin
        stateValid <= 4'b0000;
        disableMispredFlush <= (ROB_curSqN == RN_nextSqN);
        if (disableMispredFlush)
            mispredFlush <= 0;
        // TODO: Think about mispredict flush to make sure this is correct and clean it up.
        //mispredFlush <= (ROB_curSqN != RN_nextSqN);
    end
    else if (frontendEn)
        stateValid <= {stateValid[2:0], 1'b1};
end


D_UOp DE_uop[NUM_UOPS-1:0];

InstrDecoder idec
(
    .IN_instr(IF_instr),
    .IN_branchID(IF_branchID),
    .IN_branchPred(IF_branchPred),
    .IN_instrValid(IF_instrValid),
    .IN_pc(IF_pc),

    .OUT_uop(DE_uop)
);

R_UOp RN_uop[NUM_UOPS-1:0];
reg RN_uopValid[NUM_UOPS-1:0];
wire[5:0] RN_nextLoadSqN;
wire[5:0] RN_nextStoreSqN;

Rename rn 
(
    .clk(clk),
    .en(!branch.taken && stateValid[2]),
    .frontEn(frontendEn),
    .rst(rst),

    .IN_uop(DE_uop),

    .comValid(comValid),
    .comRegNm(comRegNm),
    .comRegTag(comRegTag),
    .comSqN(comSqN),

    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp),

    .IN_branchTaken(branch.taken),
    .IN_branchSqN(branch.sqN),
    .IN_branchLoadSqN(branch.loadSqN),
    .IN_branchStoreSqN(branch.storeSqN),
    .IN_mispredFlush(mispredFlush),   

    .OUT_uopValid(RN_uopValid),
    .OUT_uop(RN_uop),
    .OUT_nextSqN(RN_nextSqN),
    .OUT_nextLoadSqN(RN_nextLoadSqN),
    .OUT_nextStoreSqN(RN_nextStoreSqN)
);

wire RV_uopValid[NUM_UOPS-1:0];
R_UOp RV_uop[NUM_UOPS-1:0];

wire wbStall;

wire[4:0] RV_freeEntries;
ReservationStation rv
(
    .clk(clk),
    .rst(rst),
    .frontEn(stateValid[3] && frontendEn),

    .IN_wbStall('{0, wbStall}),
    .IN_uopValid(RN_uopValid),
    .IN_uop(RN_uop),
    
    .IN_LD_fu(LD_fu),
    .IN_LD_uop(LD_uop),
    .IN_LD_wbStall('{0, wbStall}),
    
    .IN_resultValid(wbHasResult),
    .IN_resultUOp(wbUOp),

    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .IN_nextCommitSqN(ROB_curSqN),

    .OUT_valid(RV_uopValid),
    .OUT_uop(RV_uop),
    .OUT_free(RV_freeEntries)
);


wire RF_readEnable[3:0];
wire[5:0] RF_readAddress[3:0];
wire[31:0] RF_readData[3:0];

wire[5:0] RF_writeAddress[1:0];
assign RF_writeAddress[0] = wbUOp[0].tagDst;
assign RF_writeAddress[1] = wbUOp[1].tagDst;
wire[31:0] RF_writeData[1:0];
assign RF_writeData[0] = wbUOp[0].result;
assign RF_writeData[1] = wbUOp[1].result;

RF rf
(
    .clk(clk),
    .rst(rst),
    .IN_readEnable(RF_readEnable),
    .IN_readAddress(RF_readAddress),
    .OUT_readData(RF_readData),

    .IN_writeEnable(wbHasResult),
    .IN_writeAddress(RF_writeAddress),
    .IN_writeData(RF_writeData)
);

EX_UOp LD_uop[NUM_UOPS-1:0];
wire[3:0] enabledXUs[NUM_UOPS-1:0];
FuncUnit LD_fu[NUM_UOPS-1:0];

wire[31:0] LD_zcFwdResult[1:0];
wire[5:0] LD_zcFwdTag[1:0];
wire LD_zcFwdValid[1:0];
Load ld
(
    .clk(clk),
    .rst(rst),
    .IN_wbStall('{0, wbStall}),
    .IN_uopValid(RV_uopValid),
    .IN_uop(RV_uop),
    
    .IN_wbHasResult(wbHasResult),
    .IN_wbUOp(wbUOp),
    
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .IN_zcFwdResult(LD_zcFwdResult),
    .IN_zcFwdTag(LD_zcFwdTag),
    .IN_zcFwdValid(LD_zcFwdValid),

    .OUT_rfReadValid(RF_readEnable),
    .OUT_rfReadAddr(RF_readAddress),
    .IN_rfReadData(RF_readData),
    
    .OUT_enableXU(enabledXUs),
    .OUT_funcUnit(LD_fu),
    .OUT_uop(LD_uop)
);
wire LSU_wbReq;

wire INTALU_wbReq;
RES_UOp INTALU_uop;
IntALU ialu
(
    .clk(clk),
    .en(enabledXUs[0][0]),
    .rst(rst),
    
    .IN_wbStall(LSU_wbReq),
    .IN_uop(LD_uop[0]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_wbReq(INTALU_wbReq),
    
    .OUT_isBranch(),
    .OUT_branchTaken(),
    .OUT_branchMispred(branchProvs[0].taken),
    .OUT_branchSource(),
    .OUT_branchAddress(branchProvs[0].dstPC),
    .OUT_branchIsJump(),
    .OUT_branchID(),
    .OUT_branchSqN(branchProvs[0].sqN),
    .OUT_branchLoadSqN(branchProvs[0].loadSqN),
    .OUT_branchStoreSqN(branchProvs[0].storeSqN),
    
    .OUT_zcFwdResult(LD_zcFwdResult[0]),
    .OUT_zcFwdTag(LD_zcFwdTag[0]),
    .OUT_zcFwdValid(LD_zcFwdValid[0]),
    
    .OUT_uop(INTALU_uop)
);

wire LB_valid[0:0];
wire LB_isLoad[0:0];
wire[31:0] LB_addr[0:0];
wire[5:0] LB_sqN[0:0];
wire[5:0] LB_loadSqN[0:0];
wire LB_mispred[0:0];
wire[5:0] LB_maxLoadSqN;
LoadBuffer lb
(
    .clk(clk),
    .rst(rst),
    .commitSqN(ROB_curSqN),
    
    .valid(LB_valid),
    .isLoad(LB_isLoad),
    .addr(LB_addr),
    .sqN(LB_sqN),
    .loadSqN(LB_loadSqN),
    
    .IN_branch(branch),
    
    .mispredict(LB_mispred),
    .OUT_maxLoadSqN(LB_maxLoadSqN)
);

RES_UOp LSU_uop;
assign wbStall = LSU_wbReq && INTALU_wbReq;
LSU lsu
(
    .clk(clk),
    .rst(rst),
    .IN_valid(LD_uop[0].valid && enabledXUs[0][1]),
    .IN_uop(LD_uop[0]),
    
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .OUT_SQ_valid(SQ_valid[0]),
    .OUT_SQ_isLoad(SQ_isLoad[0]),
    .OUT_SQ_addr(SQ_addr[0]),
    .OUT_SQ_data(SQ_data[0]),
    .OUT_SQ_wmask(SQ_wmask[0]),
    .OUT_SQ_sqN(SQ_sqN[0]),
    .OUT_SQ_storeSqN(SQ_storeSqN[0]),
        
    .IN_readData(SQ_readData[0]),
    
    .OUT_LB_valid(LB_valid[0]),
    .OUT_LB_isLoad(LB_isLoad[0]),
    .OUT_LB_addr(LB_addr[0]),
    .OUT_LB_sqN(LB_sqN[0]),
    .OUT_LB_loadSqN(LB_loadSqN[0]),
    .IN_LB_mispred(LB_mispred[0]),
    
    .OUT_branchProv(branchProvs[2]),
    
    .OUT_wbReq(LSU_wbReq),
    
    .OUT_uop(LSU_uop)
);

wire[31:0] SQ_readData[0:0];
wire SQ_valid[0:0];
wire SQ_isLoad[0:0];
wire[29:0] SQ_addr[0:0];
wire[31:0] SQ_data[0:0];
wire[3:0] SQ_wmask[0:0];
wire[5:0] SQ_sqN[0:0];
wire[5:0] SQ_storeSqN[0:0];
wire[5:0] SQ_maxStoreSqN;

StoreQueue sq
(
    .clk(clk),
    .rst(rst),
    
    .IN_valid(SQ_valid),
    .IN_isLoad(SQ_isLoad),
    .IN_addr(SQ_addr),
    .IN_data(SQ_data),
    .IN_wmask(SQ_wmask),
    .IN_sqN(SQ_sqN),
    .IN_storeSqN(SQ_storeSqN),
    
    .IN_curSqN(ROB_curSqN),
    
    .IN_branch(branch),
    .IN_MEM_data('{IN_MEM_readData}),
    .OUT_MEM_addr('{OUT_MEM_addr}),
    .OUT_MEM_data('{OUT_MEM_writeData}),
    .OUT_MEM_we('{OUT_MEM_writeEnable}),
    .OUT_MEM_ce('{OUT_MEM_readEnable}),
    .OUT_MEM_wm('{OUT_MEM_writeMask}),
    
    .OUT_data(SQ_readData),
    .OUT_maxStoreSqN(SQ_maxStoreSqN)
);

assign wbUOp[0] = !LSU_uop.valid ? INTALU_uop : LSU_uop;

IntALU ialu1
(
    .clk(clk),
    .en(enabledXUs[1][0]),
    .rst(rst),
    
    .IN_wbStall(0),
    .IN_uop(LD_uop[1]),
    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),

    .OUT_wbReq(),
    
    .OUT_isBranch(isBranch),
    .OUT_branchTaken(branchTaken),
    .OUT_branchMispred(branchProvs[1].taken),
    .OUT_branchSource(branchSource),
    .OUT_branchAddress(branchProvs[1].dstPC),
    .OUT_branchIsJump(branchIsJump),
    .OUT_branchID(branchID),
    .OUT_branchSqN(branchProvs[1].sqN),
    .OUT_branchLoadSqN(branchProvs[1].loadSqN),
    .OUT_branchStoreSqN(branchProvs[1].storeSqN),
    
    .OUT_zcFwdResult(LD_zcFwdResult[1]),
    .OUT_zcFwdTag(LD_zcFwdTag[1]),
    .OUT_zcFwdValid(LD_zcFwdValid[1]),
    
    .OUT_uop(wbUOp[1])
);

wire[5:0] ROB_maxSqN;
ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_uop(wbUOp),

    .IN_invalidate(branch.taken),
    .IN_invalidateSqN(branch.sqN),
    
    .OUT_maxSqN(ROB_maxSqN),
    .OUT_curSqN(ROB_curSqN),

    .OUT_comNames(comRegNm),
    .OUT_comTags(comRegTag),
    .OUT_comValid(comValid),
    .OUT_comSqNs(comSqN),
    
    .OUT_halt(OUT_halt)
);

// this should be done properly, ideally effects in rename cycle instead of IF
assign frontendEn = (RV_freeEntries > NUM_UOPS) && 
    ($signed(RN_nextLoadSqN - LB_maxLoadSqN) <= -NUM_UOPS) && 
    ($signed(RN_nextStoreSqN - SQ_maxStoreSqN) <= -NUM_UOPS) && 
    ($signed(RN_nextSqN - ROB_maxSqN) <= -NUM_UOPS) && 
    !branch.taken;
    
//TODO: check these limits theoretically
wire dbgLoad = $signed(RN_nextLoadSqN - LB_maxLoadSqN) <= -NUM_UOPS;
wire dbgStore = $signed(RN_nextStoreSqN - SQ_maxStoreSqN) <= -NUM_UOPS;
wire dbgROB = $signed(RN_nextSqN - ROB_maxSqN) <= -NUM_UOPS;
wire dbgRV = (RV_freeEntries > 1 * NUM_UOPS);
    
endmodule
