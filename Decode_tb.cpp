// #define TRACE
// #define KANATA

#include "VTop.h"
#include "VTop_Core.h"
#include "VTop_ExternalMemorySim.h"
#include "VTop_MemRTL.h"
#include "VTop_RF.h"
#include "VTop_Rename.h"
#include "VTop_RenameTable__N8.h"
#include "VTop_Top.h"
#include "VTop___024root.h"
#include "riscv-disassembler/src/riscv-disas.h"
#include "riscv/cfg.h"
#include <cstdio>
#include <iostream> // Need std::cout
#include <unistd.h>
#include <verilated.h> // Defines common routines
#ifdef TRACE
#include "verilated_vcd_c.h"
#endif
#include <array>
#include <cstring>
#include <map>

#include "riscv/cfg.h"
#include "riscv/decode.h"
#include "riscv/devices.h"
#include "riscv/log_file.h"
#include "riscv/processor.h"
#include "riscv/simif.h"

struct Inst
{
    uint32_t inst;
    uint32_t id;
    uint32_t pc;
    uint32_t srcA;
    uint32_t srcB;
    uint32_t srcC;
    uint32_t imm;
    uint32_t result;
    uint8_t sqn;
    uint8_t fu;
    uint8_t tag;
    uint8_t fetchID;
    bool valid;
};

VTop* top; // Instantiation of model
uint32_t pram[1 << 24];
uint64_t main_time = 0;

double sc_time_stamp()
{
    return main_time;
}

class SpikeSimif : public simif_t
{

  private:
    std::unique_ptr<isa_parser_t> isa_parser;
    std::unique_ptr<processor_t> processor;
    bus_t bus;
    std::vector<std::unique_ptr<mem_t>> mems;
    std::vector<std::string> errors;
    cfg_t* cfg;
    std::map<size_t, processor_t*> harts;

  public:
    SpikeSimif()
    {
        cfg = new cfg_t(std::make_pair(0, 0), "", "rv32i", "m", DEFAULT_VARCH, false, endianness_little, 0,
                        {mem_cfg_t(0x80000000, 1 << 26)}, {0}, true, 0);
        isa_parser = std::make_unique<isa_parser_t>("rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei", "MSU");
        processor = std::make_unique<processor_t>(isa_parser.get(), cfg, this, 0, false, stdout, std::cerr);
        harts[0] = processor.get();

        processor->set_pmp_num(0);

        processor->get_state()->pc = 0x80000000;
        //processor->get_state()->csrmap[CSR_] = 0x80000000;
        processor->set_mmu_capability(IMPL_MMU_SV32);
        processor->set_debug(true);
    }

    virtual char* addr_to_mem(reg_t addr) override
    {
        return nullptr;
    }
    virtual bool mmio_load(reg_t addr, size_t len, uint8_t* bytes) override
    {
        if ((addr - 0x80000000) < sizeof(pram))
            memcpy(bytes, (uint8_t*)pram + (addr - 0x80000000), len);
        return true;
    }
    virtual bool mmio_store(reg_t addr, size_t len, const uint8_t* bytes) override
    {
        if ((addr - 0x80000000) < sizeof(pram))
            memcpy((uint8_t*)pram + (addr - 0x80000000), bytes, len);
        return true;
    }
    virtual void proc_reset(unsigned id) override
    {
    }
    virtual const char* get_symbol(uint64_t addr) override
    {
        return nullptr;
    }
    virtual const cfg_t & get_cfg() const override
    {
        return *cfg;
    }

    virtual bool cosim_instr (const Inst& inst)
    {
        uint32_t initialSpicePC = processor->get_state()->pc & 0xffff'ffff;
        bool retval = inst.pc == initialSpicePC;
        processor->step(1);
        return retval;
    }

    const std::map<size_t, processor_t *> & get_harts() const override
    {
        return harts;
    }
};

template <std::size_t N> uint32_t ExtractField(VlWide<N> wide, uint32_t startBit, uint32_t len)
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

        return ((wide.at(startI) & maskFirst) >> indexInFirst) | ((wide.at(endI) & maskLast) << ((32 - startBit % 32)));
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

uint32_t lastComSqN;
uint32_t id = 0;
uint32_t nextSqN;

uint64_t committed = 0;
Inst pd[4];
Inst de[4];
Inst insts[128];

uint32_t readRegister(uint32_t rid)
{
    auto core = top->rootp->Top->core;
    uint32_t comTag = (core->rn->rt->rat[rid] >> 7) & 127;
    if (comTag & 64)
        return comTag & 63;
    else
        return core->rf->mem[comTag];
}

SpikeSimif simif;

void LogCommit(Inst& inst)
{
    if (!simif.cosim_instr(inst))
    {
        printf("ERROR\n");
        exit(-1);
    }
    
#ifdef KANATA
    fprintf(stderr, "S\t%u\t0\t%s\n", inst.id, "COM");
    fprintf(stderr, "R\t%u\t%u\t0\n", inst.id, inst.sqn);
#else
    auto core = top->rootp->Top->core;
    fprintf(stderr, "id=%.8lx pc=%.8x\n", core->csr__DOT__minstret, inst.pc);
    for (size_t j = 0; j < 4; j++)
    {
        for (size_t k = 0; k < 8; k++)
            fprintf(stderr, "x%.2zu=%.8x ", j*8+k, readRegister(j*8+k));
        fprintf(stderr, "\n");
    }
    fprintf(stderr, "\n");
#endif
}

void LogPredec(Inst& inst)
{
#ifdef KANATA
    return;
    char buf[128];
    if (inst.inst == 0x2872d293)
        strcpy(buf, "2872d293          orc.b         t0,t0");
    else
        disasm_inst(buf, sizeof(buf), rv32, inst.pc, inst.inst);

    fprintf(stderr, "I\t%u\t%u\t%u\n", inst.id, inst.fetchID, 0);
    fprintf(stderr, "L\t%u\t%u\t%.8x: %s\n", inst.id, 0, inst.pc, buf);
    fprintf(stderr, "S\t%u\t0\t%s\n", inst.id, "DEC");
#endif
}

void LogDecode(Inst& inst)
{
#ifdef KANATA
    return;
    fprintf(stderr, "S\t%u\t0\t%s\n", inst.id, "RN");
#endif
}

void LogFlush(Inst& inst)
{
#ifdef KANATA
    return;
    fprintf(stderr, "R\t%u\t0\t1\n", inst.id);
#endif
}

void LogRename(Inst& inst)
{
#ifdef KANATA
    return;
    if (inst.fu == 8 || inst.fu == 11)
        fprintf(stderr, "S\t%u\t0\t%s\n", inst.id, "WFC");
    else
        fprintf(stderr, "S\t%u\t0\t%s\n", inst.id, "IS");
#endif
}

void LogResult(Inst& inst)
{
#ifdef KANATA
    return;
    fprintf(stderr, "S\t%u\t0\t%s\n", inst.id, "WFC");
    if (!(inst.tag & 0x40)) fprintf(stderr, "L\t%u\t%u\tres=%.8x\n", inst.id, 1, inst.result);
#endif
}

void LogExec(Inst& inst)
{
#ifdef KANATA
    return;
    fprintf(stderr, "S\t%u\t0\t%s\n", inst.id, "EX");
    fprintf(stderr, "L\t%u\t%u\topA=%.8x \n", inst.id, 1, inst.srcA);
    fprintf(stderr, "L\t%u\t%u\topB=%.8x \n", inst.id, 1, inst.srcB);
    fprintf(stderr, "L\t%u\t%u\timm=%.8x \n", inst.id, 1, inst.imm);
#endif
}

void LogIssue(Inst& inst)
{
#ifdef KANATA
    return;
    fprintf(stderr, "S\t%u\t0\t%s\n", inst.id, "LD");
#endif
}

void LogCycle()
{
#ifdef KANATA
    return;
    fprintf(stderr, "C\t1\n");
#endif
}

uint32_t mostRecentPC;
void LogInstructions()
{
    auto core = top->rootp->Top->core;

    bool brTaken = core->branch[0] & 1;
    int brSqN = ExtractField<3>(core->branch, 78 - 32 - 7, 7);

    // Issue
    for (size_t i = 0; i < 4; i++)
    {
        if (!core->stall[i] && core->RV_uopValid[i])
        {
            uint32_t sqn = ExtractField<4>(core->RV_uop[i], 108 - (32 + 1 + 7 + 1 + 7 + 1 + 7 + 7), 7);
            // assert(insts[sqn].valid);
            LogIssue(insts[sqn]);
        }
    }

    // Execute
    for (size_t i = 0; i < 4; i++)
    {
        // EX valid
        if ((core->LD_uop[i][0] & 1) && !core->stall[i])
        {
            uint32_t sqn = ExtractField(core->LD_uop[i], 237 - 32 * 5 - 6 - 7 - 5 - 7, 7);
            insts[sqn].srcA = ExtractField(core->LD_uop[i], 237 - 32, 32);
            insts[sqn].srcB = ExtractField(core->LD_uop[i], 237 - 32 - 32, 32);
            insts[sqn].srcC = ExtractField(core->LD_uop[i], 237 - 32 - 32 - 32, 32);
            insts[sqn].imm = ExtractField(core->LD_uop[i], 237 - 32 - 32 - 32 - 32 - 32, 32);
            LogExec(insts[sqn]);
        }
    }

    // Result
    for (size_t i = 0; i < 4; i++)
    {
        // WB valid
        if (core->wbUOp[i][0] & 1)
        {
            uint32_t sqn = ExtractField(core->wbUOp[i], 90 - 32 - 7 - 5 - 7, 7);
            uint32_t result = ExtractField(core->wbUOp[i], 90 - 32, 32);
            uint32_t tagDst = ExtractField(core->wbUOp[i], 90 - 32 - 7, 7);
            insts[sqn].result = result;
            insts[sqn].tag = tagDst;
            LogResult(insts[sqn]);
        }
    }

    // Commit
    {
        uint32_t curComSqN = core->ROB_curSqN;
        for (size_t i = 0; i < 4; i++)
        {
            if ((core->comUOps[i] & 1) && !core->csr__DOT__IN_mispredFlush)
            {
                int sqn = (core->comUOps[i] >> 4) & 127;

                // assert(insts[sqn].valid);
                assert(insts[sqn].sqn == (uint32_t)sqn);
                LogCommit(insts[sqn]);
                mostRecentPC = insts[sqn].pc;
                insts[sqn].valid = false;
            }
        }

        lastComSqN = curComSqN;
    }

    // Branch Taken
    if (brTaken)
    {
        uint32_t i = (brSqN + 1) & 127;
        while (i != nextSqN)
        {
            if (insts[i].valid) LogFlush(insts[i]);
            i = (i + 1) & 127;
        }

        for (size_t i = 0; i < 4; i++)
        {
            if (de[i].valid) LogFlush(de[i]);
            if (pd[i].valid) LogFlush(pd[i]);
        }
    }
    else
    {

        // Rename
        if (core->rn->frontEn && !core->csr__DOT__IN_mispredFlush && !core->RN_stall)
            for (size_t i = 0; i < 4; i++)
                if (core->RN_uopValid[i])
                {
                    int sqn = ExtractField<4>(core->RN_uop[i], 45, 7);
                    int fu = ExtractField<4>(core->RN_uop[i], 1, 4);

                    insts[sqn].valid = 1;
                    insts[sqn] = de[i];
                    insts[sqn].sqn = sqn;
                    insts[sqn].fu = fu;
                    nextSqN = (sqn + 1) & 127;

                    LogRename(insts[sqn]);
                }

        // Decoded (TODO: decBranch)
        if (core->rn->frontEn)
        {
            for (size_t i = 0; i < 4; i++)
                if (top->rootp->Top->core->DE_uop[i].at(0) & (1 << 0))
                {
                    de[i] = pd[i];
                    LogDecode(de[i]);
                }
                else
                {
                    if (pd[i].valid) LogFlush(pd[i]);
                    de[i].valid = false;
                }
        }
        // Predec
        if (!core->FUSE_full)
        {
            for (size_t i = 0; i < 4; i++)
                if (core->PD_instrs[i].at(0) & 1)
                {
                    pd[i].valid = true;
                    pd[i].id = id++;
                    pd[i].pc = ExtractField<4>(top->rootp->Top->core->PD_instrs[i], 122 - 31 - 32, 31) << 1;
                    pd[i].inst = ExtractField<4>(top->rootp->Top->core->PD_instrs[i], 122 - 32, 32);
                    pd[i].fetchID = ExtractField(top->rootp->Top->core->PD_instrs[i], 3, 5);
                    if ((pd[i].inst & 3) != 3) pd[i].inst &= 0xffff;

                    LogPredec(pd[i]);
                }
                else
                    pd[i].valid = false;
        }
    }
    LogCycle();
}

//#include "default64mbdtc.h"

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv); // Remember args
    Verilated::traceEverOn(true);

    top = new VTop;
    top->clk = 0;

    if (argc != 1 && argv[1][0] != '+')
    {
        system(
            (std::string("riscv32-elf-as -mabi=ilp32 -march=rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei -o temp.o ") +
             std::string(argv[1]))
                .c_str());
        system("riscv32-elf-ld --no-warn-rwx-segments -Tlinker.ld test_programs/entry.o temp.o");
    }
    system("riscv32-elf-objcopy -I elf32-little -j .text -O binary ./a.out text.bin");
    system("riscv32-elf-objcopy -I elf32-little -j .data -O binary ./a.out data.bin");

    size_t numInstrBytes = 0;
    {
        uint8_t* pramBytes = (uint8_t*)pram;

        FILE* f = fopen("text.bin", "rb");
        numInstrBytes = fread(pramBytes, sizeof(uint8_t), sizeof(pram), f);
        fclose(f);

        if (numInstrBytes & 3) numInstrBytes = (numInstrBytes & ~3) + 4;
        printf("Read %zu bytes of instructions\n", numInstrBytes);

        f = fopen("data.bin", "rb");
        numInstrBytes += fread(&pramBytes[numInstrBytes], sizeof(uint8_t), sizeof(pram) - numInstrBytes, f);

        fclose(f);
    }

#ifdef KANATA
    fprintf(stderr, "Kanata	0004\n");
#endif

#ifdef TRACE
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("Decode_tb.vcd");
#endif

    //memcpy(&pram[(0x800000) / 4], default64mbdtb, sizeof(default64mbdtb));

    for (size_t i = 0; i < (1 << 24); i++)
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
        top->eval(); // Evaluate model

        if (top->clk == 1) LogInstructions();

        //if ((main_time & (0xfffff)) == 0) printf("%.10lu pc=%.8x\n", core->csr__DOT__minstret, mostRecentPC);
        
#ifdef TRACE
        tfp->dump(main_time);
#endif
        main_time++; // Time passes...
    }

    // Run a few more cycles ...
    for (int i = 0; i < 1600; i = i + 1)
    {
        top->clk = !top->clk;
        top->eval(); // Evaluate model
#ifdef TRACE
        tfp->dump(main_time);
#endif
        main_time++; // Time passes...
    }

    printf("%lu cycles\n", main_time / 2);

    top->final(); // Done simulating
#ifdef TRACE
    tfp->close();
    delete tfp;
#endif
    delete top;
}
