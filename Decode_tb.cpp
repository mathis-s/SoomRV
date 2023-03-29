//#define TRACE

#include "VTop_Core.h"
#include "VTop.h"
#include "VTop_Top.h"
#include "VTop_ExternalMemorySim.h"
#include "VTop_MemRTL.h"
#include "VTop___024root.h"
#include <cstdio>
#include <iostream>    // Need std::cout
#include <unistd.h>
#include <verilated.h> // Defines common routines
#ifdef TRACE
#include "verilated_vcd_c.h"
#endif
#include <array>
#include <cstring>

VTop* top; // Instantiation of model

uint64_t main_time = 0;

double sc_time_stamp()
{                   
    return main_time;
}

uint32_t pram[1<<24];

template<std::size_t N>
uint32_t ExtractField (VlWide<N> wide, uint32_t startBit, uint32_t len)
{
        uint32_t wlen = (sizeof(EData) * 8);
        uint32_t endBit = startBit + len - 1;
        uint32_t startI = startBit / wlen;
        uint32_t endI = endBit / wlen;
        if (startI != endI)
        {
            uint32_t indexInFirst = startBit - startI * wlen;
            uint32_t indexInLast = endBit - endI * wlen;
            
            uint32_t maskLast = (1UL << (indexInLast + 1)) - 1;
            
            uint32_t maskFirst = ~((1UL << indexInFirst) - 1);
            
            return ((wide.at(startI) & maskFirst) >> indexInFirst) |
                ((wide.at(endI) & maskLast) << ((32 - startBit % 32)));
        }
        else
        {
            uint32_t indexInFirst = startBit - startI * wlen;
            uint32_t indexInLast = endBit - endI * wlen;
             
            uint32_t maskFirst = ~((1UL << indexInFirst) - 1);
            uint32_t maskLast = (1UL << (indexInLast + 1)) - 1;
            
            return ((wide.at(startI) & maskFirst & maskLast) >> indexInFirst);
        }
}

uint32_t id = 0;   
struct Inst
{
    uint32_t pc;
    uint32_t inst;
    uint32_t id;
    uint32_t sqn;
};
Inst pd[4];
Inst de[4];
Inst rn[4];
    
/*void LogInstructions ()
{
    auto core = top->rootp->Top->core;
    
    // Rename
    if (!core->RN_stall && core->rn__DOT__frontEn)
        for (size_t i = 0; i < 4; i++)
            if (core->RN_uopValid[i])
            {
                rn[i] = de[i];
                rn[i].sqn = ExtractField<4>(core->RN_uop[i], 45, 7);
                printf("%.2x ", rn[i].sqn);
            }
    
    // Decoded
    if (core->rn__DOT__frontEn)
        for (size_t i = 0; i < 4; i++)
            if (top->rootp->Top->core->DE_uop[i].at(0) & (1<<0))
            {
                de[i] = pd[i];
            }
    // Predec
    if (!core->FUSE_full)
        for (size_t i = 0; i < 4; i++)
            if (core->PD_instrs[i].at(0) & 1)
            {
                pd[i].id = id++;
                pd[i].pc = ExtractField<3>(core->PD_instrs[i], 7, 31) << 1;
                pd[i].inst = ExtractField<3>(core->PD_instrs[i], 38, 32);
                
                if ((pd[i].inst & 3) != 3) pd[i].inst &= 0xffff;
            }
    
    printf("\n");
}*/


int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv); // Remember args
    Verilated::traceEverOn(true);

    top = new VTop;
    top->clk = 0;
    
    if (argc != 1 && argv[1][0] != '+')
    {
        system((std::string("riscv32-elf-as -mabi=ilp32 -march=rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei -o temp.o ") + std::string(argv[1])).c_str());
        system("riscv32-elf-ld -Tlinker.ld test_programs/entry.o temp.o");
    }
    system("riscv32-elf-objcopy -I elf32-little -j .text -O binary ./a.out text.bin");
    system("riscv32-elf-objcopy -I elf32-little -j .data -O binary ./a.out data.bin");
    
    size_t numInstrBytes = 0;
    {
        uint8_t* pramBytes = (uint8_t*)pram;
        
        FILE* f = fopen("text.bin", "rb");
        numInstrBytes = fread(pramBytes, sizeof(uint8_t), sizeof(pram), f);
        fclose(f);
        printf("Read %zu bytes of instructions\n", numInstrBytes);
        
        if (numInstrBytes & 3) numInstrBytes = (numInstrBytes & ~3) + 4;
        
        f = fopen("data.bin", "rb");
        numInstrBytes += fread(&pramBytes[numInstrBytes], sizeof(uint8_t), sizeof(pram) - numInstrBytes, f);
    
        fclose(f);
    }

#ifdef TRACE
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("Decode_tb.vcd");
#endif
    
    for (size_t i = 0; i < (1<<24); i++)
    {
        top->rootp->Top->extMem->mem[i] = 0;
    }
    
    for (size_t i = 0; i < (numInstrBytes/4)+1; i++)
    {
        top->rootp->Top->extMem->mem[i] = pram[i];
    }
    
    // Reset
    top->rst = 1;
    for (size_t j = 0; j < 4; j++)
    {
        top->clk = !top->clk;
        top->eval();
#ifdef TRACE
        tfp->dump(main_time);
#endif
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
        //if (top->clk == 1) LogInstructions ();
#ifdef TRACE
        tfp->dump(main_time);
#endif
        main_time++;              // Time passes...
        
        //if (!(main_time & 0xffff)) printf("pc %.8x\n", instrAddrReg);
    }
    
    // Run a few more cycles ...
    for (int i = 0; i < 1600; i=i+1)
    {
        top->clk = !top->clk;
        top->eval();              // Evaluate model
#ifdef TRACE
        tfp->dump(main_time);
#endif
        main_time++;              // Time passes...
    }
    
    printf("%lu cycles\n", main_time / 2);

    top->final(); // Done simulating
#ifdef TRACE
    tfp->close();
    delete tfp;
#endif
    delete top;
}
