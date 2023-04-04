// #define TRACE
// #define KONATA
// #define COSIM
#define TOOLCHAIN "riscv32-unknown-linux-gnu-"

#include "VTop.h"
#include "VTop_Core.h"
#include "VTop_ExternalMemorySim.h"
#include "VTop_MemRTL.h"
#include "VTop_RF.h"
#include "VTop_Rename.h"
#include "VTop_RenameTable__N8.h"
#include "VTop_Top.h"
#include "VTop___024root.h"
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
#include "riscv/disasm.h"
#include "riscv/log_file.h"
#include "riscv/mmu.h"
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
    uint8_t fetchID;
    uint8_t sqn;
    uint8_t fu;
    uint8_t rd;
    uint8_t tag;
    uint8_t flags;
    enum InterruptType { IR_NONE, IR_SQUASH, IR_KEEP } interrupt;
    bool valid;
};

VTop* top; // Instantiation of model
uint32_t pram[1 << 24];
uint64_t main_time = 0;

double sc_time_stamp()
{
    return main_time;
}

uint32_t ReadRegister(uint32_t rid);

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
    uint64_t mtime;
    uint64_t mtimecmp;

    bool compare_state()
    {
        for (size_t i = 0; i < 32; i++)
            if ((uint32_t)processor->get_state()->XPR[i] != ReadRegister(i))
            {
                // printf("mismatch x%zu\n", i);
                return false;
            }
        return true;
    }

    static bool is_pass_thru_inst(const Inst& i)
    {
        // pass through some HPM counter reads
        // WARNING: this explicitly stops us from testing
        // mcounterinhibit for these!
        if ((i.inst & 0b1111111) == 0b1110011)
            switch ((i.inst >> 12) & 0b11)
            {
                case 0b001:
                case 0b010:
                case 0b011:
                case 0b101:
                case 0b110:
                case 0b111:
                {
                    uint32_t csrID = i.inst >> 20;
                    switch (csrID)
                    {
                        // FIXME: minstret should be the same, barring
                        // multiple commits per cycle. This is a bit overzealous.
                        case CSR_MINSTRETH:
                        case CSR_MINSTRET:
                        case CSR_CYCLE:
                        case CSR_CYCLEH:
                        case CSR_MCYCLE:
                        case CSR_MCYCLEH:
                        case CSR_MHPMCOUNTER3:
                        case CSR_MHPMCOUNTER4:
                        case CSR_MHPMCOUNTER5:
                        case CSR_MHPMCOUNTER3H:
                        case CSR_MHPMCOUNTER4H:
                        case CSR_MHPMCOUNTER5H:
                        

                        case CSR_MTVAL:
                        case CSR_MIP:
                        
                        case CSR_MVENDORID:
                        case CSR_MARCHID:
                        case CSR_MIMPID:
                        {
                            return true;
                        }
                        default: break;
                    }
                }
                default: break;
            }

        return false;
    }

  public:
    SpikeSimif()
    {
        cfg = new cfg_t(std::make_pair(0, 0), "", "rv32i", "M", DEFAULT_VARCH, false, endianness_little, 0,
                        {mem_cfg_t(0x80000000, 1 << 26)}, {0}, false, 0);
        isa_parser = std::make_unique<isa_parser_t>("rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei", "MSU");
        processor = std::make_unique<processor_t>(isa_parser.get(), cfg, this, 0, false, stderr, std::cerr);
        harts[0] = processor.get();

        processor->set_pmp_num(0);

        processor->get_state()->csrmap[0x139] = 0;
        processor->get_state()->pc = 0x80000000;// + 3361880;
        processor->set_mmu_capability(IMPL_MMU_SV32);
        processor->set_debug(false);
        processor->get_state()->XPR.reset();
        processor->set_privilege(3);
        processor->enable_log_commits();

        std::array csrs_to_reset = {
            CSR_MSTATUS,    CSR_MSTATUSH, CSR_MCOUNTEREN, CSR_MCOUNTINHIBIT, CSR_MTVEC, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL,
            CSR_MIDELEG,    CSR_MIDELEGH, CSR_MEDELEG,    CSR_MIP,           CSR_MIPH,  CSR_MIE,  CSR_MIEH,

            CSR_SCOUNTEREN, CSR_SEPC,     CSR_SCAUSE,     CSR_STVEC,         CSR_STVAL, CSR_SATP};

        for (auto csr : csrs_to_reset)
            processor->put_csr(csr, 0);
    }

    virtual char* addr_to_mem(reg_t addr) override
    {
        if (addr >= 0x80000000)
            return (char*)pram + (addr - 0x80000000);
        return nullptr;
    }
    virtual bool mmio_load(reg_t addr, size_t len, uint8_t* bytes) override
    {
        if ((addr - 0x80000000) < sizeof(pram))
            memcpy(bytes, (uint8_t*)pram + (addr - 0x80000000), len);
        else
            memset(bytes, 0, len);

        if (addr == 0x2000000 + 0xbff8)
            memcpy(bytes, &mtime, len);
        if (addr == 0x2000000 + 0xbffc)
            memcpy(bytes, (uint8_t*)&mtime + 4, len);
        if (addr == 0x2000000 + 0x4000)
            memcpy(bytes, (uint8_t*)&mtimecmp, len);
        if (addr == 0x2000000 + 0x4004)
            memcpy(bytes, (uint8_t*)&mtimecmp + 4, len);

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
    virtual const cfg_t& get_cfg() const override
    {
        return *cfg;
    }

    virtual bool cosim_instr(const Inst& inst)
    {

        uint32_t initialSpikePC = processor->get_state()->pc & 0xffff'ffff;
        uint32_t instSIM;
        mmio_load(initialSpikePC, 4, (uint8_t*)&instSIM);

        processor->step(1);

        // TODO: Use this for adjusting WARL behaviour
        /*auto writes = processor->get_state()->log_reg_write;
        bool gprWritten = false;
        for (auto write : writes)
        {

        }*/

        bool mem_pass_thru = false;
        auto mem_reads = processor->get_state()->log_mem_read;
        for (auto read : mem_reads)
        {
            uint32_t addr = std::get<0>(read);
            addr &= ~3;

            switch (addr)
            {

                case 0x1100bff8:
                case 0x1100bffc:
                case 0x11004000:
                case 0x11004004:
                case 0x10000000:
                case 0x10000004:
                case 0x11100000: mem_pass_thru = true;
            }
        }

        if ((mem_pass_thru || is_pass_thru_inst(inst)) && inst.rd != 0 && inst.flags < 6)
        {
            processor->get_state()->XPR.write(inst.rd, inst.result);
        }

        if (inst.interrupt == Inst::IR_KEEP)
        {
            printf("INTERRUPT %.8x (keep)", (uint32_t)processor->get_state()->pc);
            take_trap(true, 7, processor->get_state()->pc);
        }

        bool instrEqual = ((instSIM & 3) == 3) ? instSIM == inst.inst : (instSIM & 0xFFFF) == (inst.inst & 0xFFFF);
        return instrEqual && inst.pc == initialSpikePC && compare_state();
    }

    const std::map<size_t, processor_t*>& get_harts() const override
    {
        return harts;
    }

    void dump_state(FILE* stream, uint32_t ppc) const
    {
        fprintf(stream, "ir=%.8lx ppc=%.8x pc=%.8x\n", processor->get_state()->minstret->read() - 1, ppc, get_pc());
        for (size_t j = 0; j < 4; j++)
        {
            for (size_t k = 0; k < 8; k++)
                fprintf(stream, "x%.2zu=%.8x ", j * 8 + k, (uint32_t)processor->get_state()->XPR[j * 8 + k]);
            fprintf(stream, "\n");
        }
    }

    uint32_t get_pc() const
    {
        return processor->get_state()->pc;
    }

    void take_trap(bool interrupt, reg_t cause, reg_t epc)
    {
        // taken from spike riscv/processor.cc: take_trap (which is private ...)

        auto& state = *processor->get_state();
        processor->set_virt(false);
        const reg_t vector = (state.mtvec->read() & 1) && interrupt ? 4 * cause : 0;
        const reg_t trap_handler_address = (state.mtvec->read() & ~(reg_t)1) + vector;
        // RNMI exception vector is implementation-defined.  Since we don't model
        // RNMI sources, the feature isn't very useful, so pick an invalid address.
        const reg_t rnmi_trap_handler_address = 0;
        const bool nmie = !(state.mnstatus && !get_field(state.mnstatus->read(), MNSTATUS_NMIE));
        state.pc = !nmie ? rnmi_trap_handler_address : trap_handler_address;
        state.mepc->write(epc);
        state.mcause->write(cause | (interrupt ? 0x80000000 : 0));
        state.mtval->write(0);
        // state.mtval2->write(0);
        // state.mtinst->write(t.get_tinst());

        reg_t s = state.mstatus->read();
        s = set_field(s, MSTATUS_MPIE, get_field(s, MSTATUS_MIE));
        s = set_field(s, MSTATUS_MPP, state.prv);
        s = set_field(s, MSTATUS_MIE, 0);
        // s = set_field(s, MSTATUS_MPV, curr_virt);
        // s = set_field(s, MSTATUS_GVA, t.has_gva());
        state.mstatus->write(s);
        if (state.mstatush)
            state.mstatush->write(s >> 32); // log mstatush change
        processor->set_privilege(PRV_M);
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

std::array<uint8_t, 32> regTagOverride;
uint32_t ReadRegister(uint32_t rid)
{
    auto core = top->rootp->Top->core;

    uint8_t comTag = regTagOverride[rid];
    if (comTag == 0xff)
        comTag = (core->rn->rt->rat[rid] >> 7) & 127;

    if (comTag & 64)
        return ((int32_t)(comTag & 63) << (32 - 6)) >> (32 - 6);
    else
        return core->rf->mem[comTag];
}

SpikeSimif simif;

void DumpState(FILE* stream, uint32_t pc, uint32_t inst)
{
    auto core = top->rootp->Top->core;
    fprintf(stream, "ir=%.8lx ppc=%.8x inst=%.8x\n", core->csr__DOT__minstret, pc, inst);
    for (size_t j = 0; j < 4; j++)
    {
        for (size_t k = 0; k < 8; k++)
            fprintf(stream, "x%.2zu=%.8x ", j * 8 + k, ReadRegister(j * 8 + k));
        fprintf(stream, "\n");
    }
    fprintf(stream, "\n");
}

FILE* konataFile;

void LogCommit(Inst& inst)
{
    if (inst.interrupt == Inst::IR_SQUASH)
    {
#ifdef COSIM
        printf("INTERRUPT %.8x\n", inst.pc);
        simif.take_trap(true, 7, inst.pc);
#endif
    }
    else
    {
        if (inst.rd != 0 && inst.flags < 6)
            regTagOverride[inst.rd] = inst.tag;

#ifdef COSIM
        uint32_t startPC = simif.get_pc();
        if (!simif.cosim_instr(inst))
        {
            fprintf(stdout, "ERROR\n");
            DumpState(stdout, inst.pc, inst.inst);

            fprintf(stdout, "\nSHOULD BE\n");
            simif.dump_state(stdout, startPC);

            exit(-1);
#ifdef KONATA
            fprintf(konataFile, "L\t%u\t%u\t COSIM ERROR \n", inst.id, 0);
#endif
        }
#endif

#ifdef KONATA
        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "COM");
        fprintf(konataFile, "R\t%u\t%u\t0\n", inst.id, inst.sqn);
#else
        // DumpState(inst.pc);
#endif
    }
}

void LogPredec(Inst& inst)
{
#ifdef KONATA
    char buf[128] = {0};
    // TODO: re-add disassembly using Spike
    fprintf(konataFile, "I\t%u\t%u\t%u\n", inst.id, inst.fetchID, 0);
    fprintf(konataFile, "L\t%u\t%u\t%.8x: %s\n", inst.id, 0, inst.pc, buf);
    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "DEC");
#endif
}

void LogDecode(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "RN");
#endif
}

void LogFlush(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "R\t%u\t0\t1\n", inst.id);
#endif
}

void LogRename(Inst& inst)
{
#ifdef KONATA
    if (inst.fu == 8 || inst.fu == 11)
        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "WFC");
    else
        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "IS");
#endif
}

void LogResult(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "WFC");
    if (!(inst.tag & 0x40))
        fprintf(konataFile, "L\t%u\t%u\tres=%.8x\n", inst.id, 1, inst.result);
#endif
}

void LogExec(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "EX");
    fprintf(konataFile, "L\t%u\t%u\topA=%.8x \n", inst.id, 1, inst.srcA);
    fprintf(konataFile, "L\t%u\t%u\topB=%.8x \n", inst.id, 1, inst.srcB);
    fprintf(konataFile, "L\t%u\t%u\timm=%.8x \n", inst.id, 1, inst.imm);
#endif
}

void LogIssue(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "LD");
#endif
}

void LogCycle()
{
    memset(regTagOverride.data(), 0xFF, sizeof(regTagOverride));
#ifdef KONATA
    fprintf(konataFile, "C\t1\n");
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
            insts[sqn].result = result;
            insts[sqn].flags = ExtractField(core->wbUOp[i], 3, 4);

            // FP ops use a different flag encoding. These are not traps, so ignore them.
            if ((insts[sqn].fu == 5 || insts[sqn].fu == 6 || insts[sqn].fu == 7) && insts[sqn].flags >= 8 &&
                insts[sqn].flags <= 13)
                insts[sqn].flags = 0;

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
                // assert(insts[sqn].sqn == (uint32_t)sqn);

                bool isInterrupt = false;
                bool isXRETinterrupt = false;
                if (core->ROB_trapUOp & 1)
                {
                    int trapSQN = (core->ROB_trapUOp >> 15) & 127;
                    int flags = (core->ROB_trapUOp >> 29) & 15;
                    int rd = (core->ROB_trapUOp >> 10) & 31;
                    isInterrupt = (trapSQN == sqn) && flags == 7 && rd == 16;
                    isXRETinterrupt = (trapSQN == sqn) && ((flags == 5 || flags == 14) && core->rob__DOT__IN_interruptPending);
                }
                insts[sqn].interrupt = isInterrupt ? Inst::IR_SQUASH : Inst::IR_NONE;
                if (isXRETinterrupt) insts[sqn].interrupt = Inst::IR_KEEP;

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
            if (insts[i].valid)
                LogFlush(insts[i]);
            i = (i + 1) & 127;
        }

        for (size_t i = 0; i < 4; i++)
        {
            if (de[i].valid)
                LogFlush(de[i]);
            if (pd[i].valid)
                LogFlush(pd[i]);
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
                    uint8_t tagDst = ExtractField<4>(core->RN_uop[i], 45 - 7, 7);

                    insts[sqn].valid = 1;
                    insts[sqn] = de[i];
                    insts[sqn].sqn = sqn;
                    insts[sqn].fu = fu;
                    insts[sqn].tag = tagDst;
                    nextSqN = (sqn + 1) & 127;

                    LogRename(insts[sqn]);
                }

        // Decoded (TODO: decBranch)
        if (core->rn->frontEn && !core->RN_stall)
        {
            for (size_t i = 0; i < 4; i++)
                if (top->rootp->Top->core->DE_uop[i].at(0) & (1 << 0))
                {
                    de[i] = pd[i];
                    de[i].rd = ExtractField(core->DE_uop[i], 68 - 32 - 5 - 5 - 1 - 5, 5);
                    LogDecode(de[i]);
                }
                else
                {
                    if (pd[i].valid)
                        LogFlush(pd[i]);
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
                    pd[i].flags = 0;
                    pd[i].id = id++;
                    pd[i].pc = ExtractField<4>(top->rootp->Top->core->PD_instrs[i], 123 - 31 - 32, 31) << 1;
                    pd[i].inst = ExtractField<4>(top->rootp->Top->core->PD_instrs[i], 123 - 32, 32);
                    pd[i].fetchID = ExtractField(top->rootp->Top->core->PD_instrs[i], 4, 5);
                    if ((pd[i].inst & 3) != 3)
                        pd[i].inst &= 0xffff;

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
    memset(regTagOverride.data(), 0xFF, sizeof(regTagOverride));

    Verilated::commandArgs(argc, argv); // Remember args
#ifdef TRACE
    Verilated::traceEverOn(true);
#endif

    top = new VTop;
    top->clk = 0;

    if (argc != 1 && argv[1][0] != '+')
    {
        system((std::string(TOOLCHAIN "as -mabi=ilp32 -march=rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei -o temp.o ") +
                std::string(argv[1]))
                   .c_str());
        system(TOOLCHAIN "ld --no-warn-rwx-segments -Tlinker.ld test_programs/entry.o temp.o");
    }
    system(TOOLCHAIN "objcopy -I elf32-little -j .text -O binary ./a.out text.bin");
    system(TOOLCHAIN "objcopy -I elf32-little -j .data -O binary ./a.out data.bin");

    size_t numInstrBytes = 0;
    {
        uint8_t* pramBytes = (uint8_t*)pram;

        FILE* f = fopen("text.bin", "rb");
        numInstrBytes = fread(pramBytes, sizeof(uint8_t), sizeof(pram), f);
        fclose(f);

        if (numInstrBytes & 3)
            numInstrBytes = (numInstrBytes & ~3) + 4;
        printf("Read %zu bytes of instructions\n", numInstrBytes);

        f = fopen("data.bin", "rb");
        numInstrBytes += fread(&pramBytes[numInstrBytes], sizeof(uint8_t), sizeof(pram) - numInstrBytes, f);

        fclose(f);
    }

#ifdef KONATA
    konataFile = fopen("trace_konata.txt", "w");
    fprintf(konataFile, "Kanata	0004\n");
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

        if (top->clk == 1)
            LogInstructions();

            // if ((main_time & (0xfffff)) == 0) printf("%.10lu pc=%.8x\n", core->csr__DOT__minstret, mostRecentPC);

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
