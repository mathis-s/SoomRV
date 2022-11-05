typedef logic[5:0] ID_t;
typedef logic[7:0] Tag_t;

module TageTable
#(
    parameter SIZE=64,
    parameter TAG_SIZE=8,
    parameter USF_SIZE=2,
    parameter CNT_SIZE=2,
    parameter INTERVAL=5
)
(
    input wire clk,
    input wire rst,
    
    input ID_t IN_readAddr,
    input Tag_t IN_readTag,
    output reg OUT_readValid,
    output reg OUT_readTaken,
    
    input ID_t IN_writeAddr,
    input Tag_t IN_writeTag,
    input wire IN_writeTaken,
    input wire IN_writeValid,
    input wire IN_writeNew,
    input wire IN_writeUseful,
    input wire IN_writeUpdate,
    output reg OUT_writeAlloc,
    input wire IN_anyAlloc
);
integer i;

typedef struct packed
{
    bit[TAG_SIZE-1:0] tag;
    bit[USF_SIZE-1:0] useful;
    bit[CNT_SIZE-1:0] counter;
} TageEntry;

TageEntry entries[SIZE-1:0];


always_comb begin
    OUT_readValid = entries[IN_readAddr].tag == IN_readTag;
    OUT_readTaken = entries[IN_readAddr].counter[CNT_SIZE-1];
end

reg[INTERVAL-1:0] decrCnt;

always_comb begin
    OUT_writeAlloc = IN_writeValid && !IN_writeUpdate && IN_writeNew && entries[IN_writeAddr].useful == 0;
end

always_ff@(posedge clk) begin
    
    if (decrCnt == 0) begin
        for (i = 0; i < SIZE; i=i+1)
            if (entries[i].useful != 0) 
                entries[i].useful <= entries[i].useful - 1;
    end
     
    if (rst) begin
        decrCnt <= 0;
`ifdef __ICARUS__
        for (i = 0; i < SIZE; i=i+1)
            entries[i] <= 0;
`endif
    end
    else if (IN_writeValid) begin
        if (IN_writeUpdate) begin
            if (IN_writeTaken && entries[IN_writeAddr].counter != {CNT_SIZE{1'b1}})
                entries[IN_writeAddr].counter <= entries[IN_writeAddr].counter + 1;
            else if (!IN_writeTaken && entries[IN_writeAddr].counter != {CNT_SIZE{1'b0}})
                entries[IN_writeAddr].counter <= entries[IN_writeAddr].counter - 1;
                
            if (IN_writeUseful && entries[IN_writeAddr].useful != {USF_SIZE{1'b1}})
                entries[IN_writeAddr].useful <= entries[IN_writeAddr].useful + 1;
            else if (!IN_writeUseful && entries[IN_writeAddr].useful != {USF_SIZE{1'b0}})
                entries[IN_writeAddr].useful <= entries[IN_writeAddr].useful - 1;
        end
        else if(IN_writeNew) begin
            if (entries[IN_writeAddr].useful == 0) begin
                entries[IN_writeAddr].tag <= IN_writeTag;
                entries[IN_writeAddr].counter <= {IN_writeTaken, {(CNT_SIZE-1){1'b0}}};
                entries[IN_writeAddr].useful <= 0;
            end
            else if(!IN_anyAlloc) entries[IN_writeAddr].useful <= entries[IN_writeAddr].useful - 1;
        end
    end
    
    decrCnt <= decrCnt - 1;
end

endmodule
