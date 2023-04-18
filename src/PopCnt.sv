module PopCnt(
    
    input wire[31:0] a,
    output reg[5:0] res
);

reg[5:0] resPopCnt;

reg[1:0] resStage0[15:0]; // max 2
reg[2:0] resStage1[7:0]; // max 4
reg[3:0] resStage2[3:0]; // max 8
reg[4:0] resStage3[1:0]; // max 16

always_comb begin

    resPopCnt = 0;
    for (integer i = 0; i < 16; i=i+1)
        resStage0[i] = {1'b0, a[2*i]} + {1'b0, a[2*i+1]};
    
    for (integer i = 0; i < 8; i=i+1)
        resStage1[i] = {1'b0, resStage0[2*i]} + {1'b0, resStage0[2*i+1]};
        
    for (integer i = 0; i < 4; i=i+1)
        resStage2[i] = {1'b0, resStage1[2*i]} + {1'b0, resStage1[2*i+1]};

    for (integer i = 0; i < 2; i=i+1)
        resStage3[i] = {1'b0, resStage2[2*i]} + {1'b0, resStage2[2*i+1]};

    
    res = {1'b0, resStage3[0]} + {1'b0, resStage3[1]};
end

endmodule
