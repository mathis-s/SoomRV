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

    top = new VCore;
    top->clk = 0;
    
    if (argc == 1)
    {
        printf("Invalid argument\n");
        return 0;
    }

    system((std::string("riscv32-unknown-elf-as -o temp.o ") + std::string(argv[1])).c_str());
    system("riscv32-unknown-elf-ld -Tlinker.ld temp.o");
    system("riscv32-unknown-elf-objcopy -I elf32-little -j .text -O binary ./a.out text.bin");
    system("riscv32-elf-objcopy -I elf32-little -j .rodata -O binary ./a.out data.bin");
    
    size_t numInstrs = 0;
    {
        FILE* f = fopen("text.bin", "rb");
        while (numInstrs < 1024)
        {
            uint32_t data;
            if (fread(&data, sizeof(uint32_t), 1, f) <= 0)
                break;
            ram[numInstrs] = data;
            numInstrs++;
        }
        fclose(f);
        printf("Read %zu instructions\n", numInstrs);
        
        
        size_t dataIndex = numInstrs;
        f = fopen("data.bin", "rb");
        while (dataIndex < 1024)
        {
            uint32_t data;
            if (fread(&data, 1, sizeof(uint32_t), f) == 0)
                break;
            ram[dataIndex] = data;
            dataIndex++;
        }
        fclose(f);
    }
    
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
        if (top->OUT_halt)
            break;
        if (top->clk == 0)
        {
            size_t index;
            for (int j = 0; j < 2; j++)
            {
                index = top->OUT_pc[j] / 4;
                if (index >= 1024)
                {
                    index = 0;
                }
                top->IN_instr[j] = ram[index];
            }
            
            
            index = top->OUT_MEM_addr;
            if (index >= 1024)
            {
                printf("tried to access ram at %zx, terminating\n", index);
                break;
            }

            if (top->OUT_MEM_readEnable)
            {
                //printf("read at %zu: %.8x\n", index, ram[index]);
                top->IN_MEM_readData = ram[index];
            }
            else if (top->OUT_MEM_writeEnable)
            {
                //printf("write at %zu: %.8x\n", index, top->OUT_MEM_writeData);
                if (index == 255)
                {
                    printf("%c", ((uint32_t)top->OUT_MEM_writeData) >> 24);
                    //printf("%u\n", top->OUT_MEM_writeData);
                    fflush(stdout);
                }

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
    break_main:
    top->final(); // Done simulating
    tfp->close();
    delete top;
    delete tfp;
}
