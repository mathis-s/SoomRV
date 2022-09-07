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

    system((std::string("riscv32-unknown-elf-as -march=rv32idzba_zbb -o temp.o ") + std::string(argv[1])).c_str());
    system("riscv32-unknown-elf-ld -Tlinker.ld test_programs/entry.o temp.o");
    system("riscv32-unknown-elf-objcopy -I elf32-little -j .text -O binary ./a.out text.bin");
    system("riscv32-unknown-elf-objcopy -I elf32-little -j .rodata -O binary ./a.out data.bin");
    
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
    top->en = 1;

    // addresses is registered
    uint32_t instrAddrReg = 0;
    uint32_t memAddrReg = 0;
    uint32_t memDataReg = 0;
    bool instrCeReg = true;
    bool memWeReg = true;
    bool memCeReg = true;
    uint32_t memWmReg = 0;
    while (!Verilated::gotFinish())
    {
        if (top->OUT_halt)
            break;
        // zero right now, going to be one, so rising edge
        if (top->clk == 0)
        {
            size_t index;
            if (!instrCeReg)
            {
                index = instrAddrReg * 2;
                if (index >= 1023)
                    index = 0;
                top->IN_instrRaw = ((uint64_t)ram[index] | (((uint64_t)ram[index + 1]) << 32));
            }

            
            index = memAddrReg;
            if (index >= 1024)
            {
                //index = 1023;
                printf("tried to access ram at %zx, terminating\n", index);
                break;
            }

            if (!memCeReg && memWeReg)
            {
                //printf("read at %zu: %.8x\n", index, ram[index]);
                top->IN_MEM_readData = ram[index];
            }
            
            if (!memCeReg && !memWeReg)
            {
                //printf("write at %zu: %.8x\n", index, memDataReg);
                if (index == 255)
                {
                    printf("%c", (memDataReg) >> 24);
                    fflush(stdout);
                }

                if (memWmReg == 0b1111)
                    ram[index] = memDataReg;
                else
                {
                    uint32_t word = ram[index];
                    for (int i = 0; i < 4; i++)
                        if (memWmReg & (1 << i))
                        {
                            uint32_t mask = (1 << (8 * (i+1))) - 1;
                            if (i == 3) mask = 0xff000000;
                            mask &= ~((1 << (8 * (i))) - 1);
                            word = (word & ~mask) | (memDataReg & mask);
                        }
                    //printf("word %.8x\n", word);
                    ram[index] = word;
                }
            }
            
            
            memAddrReg = top->OUT_MEM_addr;
            memDataReg = top->OUT_MEM_writeData;
            memWeReg = top->OUT_MEM_writeEnable;
            memCeReg = top->OUT_MEM_readEnable;
            memWmReg = top->OUT_MEM_writeMask;
            instrCeReg = top->OUT_instrReadEnable;
            instrAddrReg = top->OUT_instrAddr;
            
        }

        top->clk = !top->clk;
        top->eval();              // Evaluate model
        tfp->dump(main_time);
        main_time++;              // Time passes...
    }
    
    printf("%lu cycles\n", main_time / 2);

    top->final(); // Done simulating
    tfp->close();
    delete top;
    delete tfp;
}
