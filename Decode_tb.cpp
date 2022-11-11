#include "VTop.h"
#include "VTop_Top.h"
#include "VTop_ExternalMemorySim.h"
#include "VTop_MemRTL.h"
#include "VTop___024root.h"
#include <cstdio>
#include <iostream>    // Need std::cout
#include <unistd.h>
#include <verilated.h> // Defines common routines
#include "verilated_vcd_c.h"
#include <array>

VTop* top; // Instantiation of model

uint64_t main_time = 0;

double sc_time_stamp()
{                   
    return main_time;
}

uint32_t ram[65536];
uint32_t pram[65536];


int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv); // Remember args
    Verilated::traceEverOn(true);

    top = new VTop;
    top->clk = 0;
    
    if (argc != 1 && argv[1][0] != '+')
    {
        system((std::string("riscv32-unknown-elf-as -mabi=ilp32 -march=rv32imczba_zbb_zicbom -o temp.o ") + std::string(argv[1])).c_str());
        system("riscv32-unknown-elf-ld -Tlinker.ld test_programs/entry.o temp.o");
    }
    system("riscv32-unknown-elf-objcopy -I elf32-little -j .text -O binary ./a.out text.bin");
    system("riscv32-unknown-elf-objcopy -I elf32-little -j .data -O binary ./a.out data.bin");
    
    size_t numInstrBytes = 0;
    size_t dataStart, dataIndex;
    {
        FILE* f = fopen("text.bin", "rb");
        uint8_t* pramBytes = (uint8_t*)pram;
        while (numInstrBytes < 65536 * 4)
        {
            uint8_t data;
            if (fread(&data, sizeof(uint8_t), 1, f) <= 0)
                break;
            pramBytes[numInstrBytes] = data;
            numInstrBytes++;
        }
        fclose(f);
        printf("Read %zu bytes of instructions\n", numInstrBytes);
        if (numInstrBytes & 3)
            numInstrBytes = (numInstrBytes & -4) + 4;
        
        
        dataIndex = numInstrBytes;
        dataStart = dataIndex;
        uint8_t* ramBytes = (uint8_t*)ram;
        f = fopen("data.bin", "rb");
        while (dataIndex < 65536 * 4)
        {
            uint8_t data;
            if (fread(&data, 1, sizeof(uint8_t), f) == 0)
                break;
            ramBytes[dataIndex] = data;
            
            dataIndex++;
        }
        // printf("Wrote data from %.8zx to %.8zx\n", dataStart, dataIndex);
        fclose(f);
    }

    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("Decode_tb.vcd");
    
    for (size_t i = 0; i < dataStart/4; i++)
    {
        //printf("%.8x\n", pram[i]);
        top->rootp->Top->extMem->mem[i] = pram[i];
    }
    for (size_t i = dataStart/4; i < dataIndex; i++)
    {
        /*if (ram[i] != 0) *///printf("%.8x\n", ram[i]);
        top->rootp->Top->extMem->mem[i] = ram[i];
        //top->rootp->Top->dcache->mem[i] = ram[i];
    }

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
    
    while (!Verilated::gotFinish())
    {
        if (top->OUT_halt)
        {
            top->en = 0;
            break;
        }

        top->clk = !top->clk;
        top->eval();              // Evaluate model
        //tfp->dump(main_time);
        main_time++;              // Time passes...
        
        //if (!(main_time & 0xffff)) printf("pc %.8x\n", instrAddrReg);
    }
    
    // Run a few more cycles ...
    for (int i = 0; i < 200; i=i+1)
    {
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
