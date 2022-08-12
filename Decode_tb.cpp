#include "VDecode.h"
#include <iostream>    // Need std::cout
#include <verilated.h> // Defines common routines
#include "verilated_vcd_c.h"

VDecode* top; // Instantiation of model

uint64_t main_time = 0;

double sc_time_stamp()
{                     // Called by $time in Verilog
    return main_time; // converts to double, to match
                      // what SystemC does
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv); // Remember args
    Verilated::traceEverOn(true);

    top = new VDecode; // Create model
    // Do not instead make Vtop as a file-scope static
    // variable, as the "C++ static initialization order fiasco"
    // may cause a crash
    top->clk = 0;

    size_t i = 0;
    const uint32_t instrs[] = 
    {
        /*0xFF010113,
        0x40B787B3,
        0x00f62023,
        0xfeb7fce3,
        0xfb5ff0ef, //jal	ra,100b8 <dbg_printnum>
        0xfb5ff0ef, //jal	ra,100b8 <dbg_printnum>
        0xfb5ff0ef, //jal	ra,100b8 <dbg_printnum>
        0xfb5ff0ef, //jal	ra,100b8 <dbg_printnum>*/
        
        0x00a50513,//                addi    a0,a0,10
        0x00510113,//                addi    sp,sp,5
        0xfff10593,//                addi    a1,sp,-1
        0x00000013,//                nop
        0x00000013,//                nop
        0x00250533,//                add     a0,a0,sp
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00510113,//                addi    sp,sp,5
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
        0x00000013,//                nop
    };
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("Decode_tb.vcd");

    // Reset
    top->rst = 1;
    for (size_t j = 0; j < 4; j++)
    {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(main_time);
        main_time++;
    }
    top->rst = 0;

    // Run
    while (!Verilated::gotFinish())
    {
        if (top->clk == 0)
        {
            if (i >= sizeof(instrs) / sizeof(instrs[0])) break;
            top->IN_instr = instrs[i++];
            top->IN_pc = i*2;
        }
        if (top->clk == 1)
        {
            //printf("instr %.8x | imm %x | immpc %x | srcA %x\n", (uint32_t)top->IN_instr, (uint32_t)top->OUT_uop.at(0), (uint32_t)top->OUT_uop.at(1), (uint32_t)top->OUT_uop.at(2));
        }

        top->clk = !top->clk;
        top->eval();              // Evaluate model
        tfp->dump(main_time);
        main_time++;              // Time passes...
    }

    top->final(); // Done simulating
    tfp->close();
    delete top;
    delete tfp;
}