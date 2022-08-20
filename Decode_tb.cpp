#include "VCore.h"
#include <cstdio>
#include <iostream>    // Need std::cout
#include <unistd.h>
#include <verilated.h> // Defines common routines
#include "verilated_vcd_c.h"
#include <array>

VCore* top; // Instantiation of model

uint64_t main_time = 0;

double sc_time_stamp()
{                   
    return main_time;
}

uint32_t ram[1024];

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv); // Remember args
    Verilated::traceEverOn(true);

    top = new VCore; // Create model
    // Do not instead make Vtop as a file-scope static
    // variable, as the "C++ static initialization order fiasco"
    // may cause a crash
    top->clk = 0;
    
    if (argc == 1)
    {
        printf("Invalid argument\n");
        return 0;
    }
    
    size_t i = 0;
    std::vector<uint32_t> instrs;
    
    ram[1] = 8;
    strcpy((char*)&ram[2], "strlen test string with length 33");
    
    system((std::string("riscv32-elf-as ") + std::string(argv[1])).c_str());
    system("riscv32-elf-objcopy -I elf32-little -j .text -O binary ./a.out text.bin");

    FILE* f = fopen("text.bin", "rb");
    
    while (!feof(f))
    {
        uint32_t data;
        fread(&data, sizeof(uint32_t), 1, f);
        instrs.push_back(data);
    }
    
    printf("Read %zu instructions\n", instrs.size());
    
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
            if (i >= instrs.size()) break;
            size_t index = top->OUT_pc / 4;
            if (index >= (instrs.size()))
                break;
            top->IN_instr = instrs[index];
            
            index = top->OUT_MEM_addr;
            if (index > (sizeof(ram) / sizeof(ram[0]))) break;

            if (top->OUT_MEM_readEnable)
            {
                printf("read at %zu: %.8x\n", index, ram[index]);
                top->IN_MEM_readData = ram[index];
            }
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
