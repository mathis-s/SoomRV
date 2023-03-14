


module ProgramCounter
#(
    parameter NUM_UOPS=3,
    parameter NUM_BLOCKS=8
)
(
    input wire clk,
    input wire en0,
    input wire en1,
    input wire rst,
    
    input wire[31:0] IN_pc,
    input wire IN_write,
    input wire IN_branchTaken,
    input FetchID_t IN_fetchID,

    input wire[127:0] IN_instr,
    
    input wire IN_clearICache,
    
    input wire IN_BP_branchFound,
    input wire IN_BP_branchTaken,
    input wire IN_BP_isJump,
    input wire[31:0] IN_BP_branchSrc,
    input wire[31:0] IN_BP_branchDst,
    
    input BHist_t IN_BP_history,
    input BranchPredInfo IN_BP_info,
    
    input wire IN_BP_multipleBranches,
    input wire IN_BP_branchCompr,
    
    input FetchID_t IN_pcReadAddr[4:0],
    output PCFileEntry OUT_pcReadData[4:0],
    
    input FetchID_t IN_ROB_curFetchID,

    output wire[31:0] OUT_pcRaw,
    output wire[27:0] OUT_instrAddr,
    
    output IF_Instr OUT_instrs[NUM_BLOCKS-1:0],
    
    output wire OUT_stall,
    
    output IF_MemoryController OUT_MC_if,
    input wire[0:0] IN_MC_cacheID,
    input wire[9:0] IN_MC_progress,
    input wire IN_MC_busy
);

integer i;

FetchID_t fetchID;

reg[30:0] pc;
reg[30:0] pcLast;
FetchID_t fetchIDlast;
BHist_t histLast;
BranchPredInfo infoLast;
reg[2:0] branchPosLast;
reg multipleLast;

assign OUT_pcRaw = {pc, 1'b0};

always_comb begin
    for (i = 0; i < NUM_BLOCKS; i=i+1)
        OUT_instrs[i].instr = IN_instr[(16*i)+:16];
end
    
PCFileEntry PCF_writeData;
assign PCF_writeData.pc = pcLast;
assign PCF_writeData.hist = histLast;
assign PCF_writeData.bpi = infoLast;
assign PCF_writeData.branchPos = branchPosLast;
PCFile#($bits(PCFileEntry)) pcFile
(
    .clk(clk),
    
    .wen0(en1),
    .waddr0(fetchID),
    .wdata0(PCF_writeData),
    
    .raddr0(IN_pcReadAddr[0]), .rdata0(OUT_pcReadData[0]),
    .raddr1(IN_pcReadAddr[1]), .rdata1(OUT_pcReadData[1]),
    .raddr2(IN_pcReadAddr[2]), .rdata2(OUT_pcReadData[2]),
    .raddr3(IN_pcReadAddr[3]), .rdata3(OUT_pcReadData[3]),
    .raddr4(IN_pcReadAddr[4]), .rdata4(OUT_pcReadData[4])
);

wire icacheStall;
ICacheTable ict
(
    .clk(clk),
    .rst(rst || IN_clearICache),
    .IN_lookupValid(en0),
    .IN_lookupPC(pc),
    
    .OUT_lookupAddress(OUT_instrAddr),
    .OUT_stall(icacheStall),
    
    .OUT_MC_if(OUT_MC_if),
    .IN_MC_cacheID(IN_MC_cacheID),
    .IN_MC_progress(IN_MC_progress),
    .IN_MC_busy(IN_MC_busy)
);

assign OUT_stall = (IN_ROB_curFetchID == fetchID) || icacheStall;

always_ff@(posedge clk) begin
    if (rst) begin
        pc <= 0;
        fetchID <= 0;
    end
    else if (IN_write) begin
        pc <= IN_pc[31:1];
        fetchID <= IN_fetchID + 1;
    end
    else begin
        if (en1) begin
            for (i = 0; i < NUM_BLOCKS; i=i+1) begin
                OUT_instrs[i].pc <= {{pcLast[30:3], i[2:0]}};
                OUT_instrs[i].valid <= (i[2:0] >= pcLast[2:0]) && 
                    (!infoLast.taken || i[2:0] <= branchPosLast) &&
                    (!multipleLast || i[2:0] <= branchPosLast);
                OUT_instrs[i].fetchID <= fetchID;
                OUT_instrs[i].predTaken <= (infoLast.taken && i[2:0] == branchPosLast);
            end
            fetchID <= fetchID + 1;
        end

        if (en0) begin
            
            histLast <= IN_BP_history;
            infoLast <= IN_BP_info;
            pcLast <= pc;
            branchPosLast <= IN_BP_branchSrc[3:1];
            multipleLast <= IN_BP_multipleBranches;
            
            if (IN_BP_branchFound) begin
                if (IN_BP_isJump || IN_BP_branchTaken) begin
                    pc <= IN_BP_branchDst[31:1];
                end
                // Branch found, not taken
                else begin                    
                    // There is a second branch in this block,
                    // go there.
                    if (IN_BP_multipleBranches) begin
                        pc <= IN_BP_branchSrc[31:1] + 1;
                    end
                    else begin
                        pc <= {pc[30:3] + 28'b1, 3'b000};
                    end
                end
            end
            else begin
                pc <= {pc[30:3] + 28'b1, 3'b000};
                
            end
        end
    end
end

endmodule
