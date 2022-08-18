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

uint32_t ram[1024];

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
        
        /*0x00a50513,//                addi    a0,a0,10
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
        0x00000013,//                nop*/

        /*0x00a50513,                //addi    a0,a0,10
        0x00a585b3,                //add     a1,a1,a0
        0x00b60633,                //add     a2,a2,a1
        0x00a10113,                //addi    sp,sp,10
        0x00a68693,                //addi    a3,a3,10
        0x40c10133,                //sub     sp,sp,a2
        0x00d10133,                //add     sp,sp,a3
        0x00000013,                //nop
        0x00000013,                //nop
        0x00000013,                //nop
        0x00000013,                //nop
        0x00000013,                //nop
        0x00000013,                //nop
        0x00000013,                //nop
        0x00000013,                //nop*/

        0x08000593,//                li      a1,128
        0x00150513,//                addi    a0,a0,1
        0x3ea02fa3,//                sw      a0,1023(zero) # 3ff <.main-0xfc79>
        0xfeb54ce3,//                blt     a0,a1,1007c <.loop>
        0x00160613,//                addi    a2,a2,1
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
        top->rst = (j < 2);
    }

    // Run
    while (!Verilated::gotFinish())
    {
        if (top->clk == 0)
        {
            if (i >= sizeof(instrs) / sizeof(instrs[0])) break;
            size_t index = top->OUT_pc / 4;
            if (index > (sizeof(instrs) / sizeof(instrs[0])))
                break;
            top->IN_instr = instrs[index];
            
            index = top->OUT_MEM_addr;
            if (index > (sizeof(ram) / sizeof(ram[0]))) break;

            if (top->OUT_MEM_readEnable)
                top->IN_MEM_readData = ram[index];
            else if (top->OUT_MEM_writeEnable)
            {
                if (index == 255)
                    printf("%u\n", top->OUT_MEM_writeData);

                if (top->OUT_MEM_writeMask == 0b1111) 
                    ram[index] = top->OUT_MEM_writeData;
                else
                {
                    uint32_t word = ram[index];
                    for (int i = 0; i < 4; i++)
                        if (top->OUT_MEM_writeMask & (1 << i))
                        {
                            uint32_t mask = (1 << (8 * i)) - 1;
                            if (i != 0)
                                mask &= ~((1 << (8 * (i - 1))) - 1);
                            word = (word & mask) | (top->OUT_MEM_writeData & ~mask);
                        }
                    ram[index] = word;
                }
            }
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