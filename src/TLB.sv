module TLB#(parameter NUM_RQ=1, parameter SIZE=8, parameter ASSOC=4, parameter IS_IFETCH=0)
(
    input wire clk,
    input wire rst,
    input wire clear,
    
    input PageWalk_Res IN_pw,
    input TLB_Req IN_rqs[NUM_RQ-1:0],
    output TLB_Res OUT_res[NUM_RQ-1:0]
);

localparam LEN = SIZE / ASSOC;
localparam VIRT_LEN = 20 - $clog2(LEN);
typedef struct packed
{
    logic[VIRT_LEN-1:0] vpn;
    logic[19:0] ppn;
    logic isSuper;
    logic user;
    logic globl;
    logic[2:0] rwx; // 0 is invalid
} TLBEntry;

TLBEntry tlb[LEN-1:0][ASSOC-1:0];
reg[$clog2(ASSOC)-1:0] counters[LEN-1:0];
reg[LEN-1:0] inc;

always_comb begin
    inc = '0;
    for (integer i = 0; i < NUM_RQ; i=i+1) begin
        reg[$clog2(LEN)-1:0] idx = IN_rqs[i].vpn[$clog2(LEN)-1:0];
        OUT_res[i].fault = 0;
        OUT_res[i].hit = 0;
        
        if (IN_rqs[i].valid)
            for (integer j = 0; j < ASSOC; j=j+1)
                if (tlb[idx][j].rwx != 0 && 
                    (tlb[idx][j].isSuper ? 
                        tlb[idx][j].vpn[19-$clog2(LEN):10-$clog2(LEN)] == IN_rqs[i].vpn[19:10] :
                        tlb[idx][j].vpn == IN_rqs[i].vpn[19:$clog2(LEN)])
                ) begin
                    OUT_res[i].fault = 0;
                    OUT_res[i].rwx = tlb[idx][j].rwx;
                    OUT_res[i].user = tlb[idx][j].user;
                    OUT_res[i].isSuper = tlb[idx][j].isSuper;
                    OUT_res[i].hit = 1;
                    OUT_res[i].ppn = tlb[idx][j].isSuper ? {tlb[idx][j].ppn[19:10], IN_rqs[i].vpn[9:0]} : tlb[idx][j].ppn;
                    
                    if (counters[idx] == j[$clog2(ASSOC)-1:0] ) inc[i] = 1;
                end
    end
end

reg ignoreCur;

always_ff@(posedge clk) begin
    if (rst || clear) begin
        for (integer i = 0; i < LEN; i=i+1)
            for (integer j = 0; j < ASSOC; j=j+1)
                tlb[i][j].rwx <= 0;
        
        // When an sfence.vma commits, the translation in progress
        // is also stale.
        if (clear) ignoreCur <= 1;

        if (rst) ignoreCur <= 0;
    end
    else begin
        
        if (ignoreCur && !IN_pw.busy)
            ignoreCur <= 0;

        // FIXME: Currently, we might double insert if both AGUs tlb miss on the same address.
        if (IN_pw.valid && !IN_pw.pageFault && IN_pw.ppn[21:20] == 0 && !ignoreCur &&
            // only cache useful translations
            (IS_IFETCH ? (IN_pw.rwx[0] != 0) : (IN_pw.rwx[2:1] != 0)) &&
            // disambiguate between ifetch and regular ld/st
            (IS_IFETCH ? IN_pw.rqID == 0 : IN_pw.rqID != 0)
        ) begin
            reg[$clog2(LEN)-1:0] idx = IN_pw.vpn[$clog2(LEN)-1:0];
            reg[$clog2(ASSOC)-1:0] assocIdx = counters[idx];
            
            tlb[idx][assocIdx].rwx <= IN_pw.rwx;
            
            tlb[idx][assocIdx].isSuper <= IN_pw.isSuperPage;

            tlb[idx][assocIdx].ppn <= IN_pw.ppn[19:0];
            tlb[idx][assocIdx].vpn <= IN_pw.vpn[19:$clog2(LEN)];

            tlb[idx][assocIdx].globl <= IN_pw.globl;
            tlb[idx][assocIdx].user <= IN_pw.user;
        end

        for (integer i = 0; i < LEN; i=i+1)
            if (inc[i]) counters[i] <= counters[i] + 1;
    end
end


endmodule
