module StoreDataLoad#(parameter WIDTH=2)
(
    input wire clk,
    input wire rst,

    input BranchProv IN_branch,

    input StDataLookupUOp IN_uop[WIDTH-1:0],
    output logic OUT_ready[WIDTH-1:0],

    input AMO_Data_UOp IN_atomicUOp[WIDTH-1:0], 

    output RFTag OUT_readTag[WIDTH-1:0],
    input RegT IN_readData[WIDTH-1:0],
    
    output StDataUOp OUT_uop[WIDTH-1:0]
);

function automatic RegT ShiftData (RegT raw, StOff_t offs);
    // we can save some logic by only shifting necessary sections
    RegT shifted = 'x;
    case (offs)
        0: shifted = raw;
        1: shifted[8+:8] = raw[0+:8];
        2: shifted[16+:16] = raw[0+:16];
        3: shifted[24+:8] = raw[0+:8];
    endcase
    return shifted;
endfunction

always_comb begin
    for (integer i = 0; i < WIDTH; i=i+1)
        OUT_readTag[i] = RFTag'(IN_uop[i].tag);
end

generate for (genvar i = 0; i < WIDTH; i=i+1) begin
    
    assign OUT_ready[i] = !(uopATO.valid && uopIQ.valid);
    
    StOff_t offs;
    StDataUOp uopIQ;
    StDataUOp uopATO;

    wire RegT readDataShifted = ShiftData(IN_readData[i], offs);

    always_comb begin
        uopATO.valid = IN_atomicUOp[i].valid;
        uopATO.storeSqN = IN_atomicUOp[i].storeSqN;
        uopATO.data = IN_atomicUOp[i].result;
    end

    logic regFileLookup;
    always_ff@(posedge clk) begin
        regFileLookup <= 0;
        offs <= 'x;
        
        if (rst) begin
            uopIQ <= StDataUOp'{valid: 0, default: 'x};
        end
        else begin
            if (regFileLookup) begin
                assert(uopIQ.valid);
                uopIQ.data <= readDataShifted;
            end

            if (!uopATO.valid)
                uopIQ <= StDataUOp'{valid: 0, default: 'x};

            if (IN_uop[i].valid && OUT_ready[i] && (!IN_branch.taken ||
                (!IN_branch.flush && $signed(IN_uop[i].storeSqN - IN_branch.storeSqN) <= 0))
            ) begin
                uopIQ.valid <= 1;
                uopIQ.storeSqN <= IN_uop[i].storeSqN;

                if (IN_uop[i].tag[$bits(Tag)-1]) begin
                    uopIQ.data <= ShiftData({{26{IN_uop[i].tag[5]}}, IN_uop[i].tag[5:0]}, IN_uop[i].offs);
                end
                else begin 
                    regFileLookup <= 1;
                    offs <= IN_uop[i].offs;
                end
            end
        end
    end

    StDataUOp outUOp;
    always_comb begin
        outUOp = StDataUOp'{valid: 0, default: 'x};
        if (uopATO.valid)
            outUOp = uopATO;
        else if (uopIQ.valid) begin
            outUOp = uopIQ;
            if (regFileLookup)
                outUOp.data = readDataShifted;
        end
    end
    assign OUT_uop[i] = outUOp;
end endgenerate

endmodule
