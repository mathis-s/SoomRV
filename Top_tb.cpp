//#define TRACE
//#define DUMP_FLAT
#include "riscv/csrs.h"
#include "riscv/trap.h"
#include <memory>
// #define KONATA
#define COSIM
#define TOOLCHAIN "riscv32-unknown-linux-gnu-"

#include "VTop.h"
#include "VTop_Core.h"
#include "VTop_ExternalMemorySim.h"
#include "VTop_RF.h"
#include "VTop_Rename.h"
#include "VTop_RenameTable__N8.h"
#include "VTop_RenameTable__N4_NB2.h"
#include "VTop_Top.h"
#include "VTop_CSR.h"
#include "VTop_ROB.h"
#include <cstdio>
#include <iostream> // Need std::cout
#include <unistd.h>
#ifdef TRACE
#include "verilated_vcd_c.h"
#endif
#include <exception>
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
    uint32_t memAddr;
    uint32_t memData;
    uint8_t fetchID;
    uint8_t sqn;
    uint8_t fu;
    uint8_t rd;
    uint8_t tag;
    uint8_t flags;
    uint8_t interruptCause;
    bool interruptDelegate;
    enum InterruptType
    {
        IR_NONE,
        IR_SQUASH,
        IR_KEEP
    } interrupt;
    bool valid;
};

VTop* top; // Instantiation of model
#ifdef TRACE
VerilatedVcdC* tfp;
#endif
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
        if ((i.inst & 0b1111111) == 0b1110011) switch ((i.inst >> 12) & 0b11)
            {
            case 0b001:
            case 0b010:
            case 0b011:
            case 0b101:
            case 0b110:
            case 0b111: {
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
                case CSR_MISA:
                case CSR_TIME:
                case CSR_TIMEH:
                
                case CSR_STVAL:
                // TODO: these two only differ in warl behaviour,
                // adjust on write instead of read.
                case CSR_MCOUNTINHIBIT:
                case CSR_SATP:

                case CSR_MTVAL:
                case CSR_MIP:

                case CSR_MVENDORID:
                case CSR_MARCHID:
                case CSR_MIMPID: {
                    return true;
                }
                default:
                    break;
                }
            }
            default:
                break;
            }

        return false;
    }
    
    std::shared_ptr<basic_csr_t> timeCSR;
    std::shared_ptr<basic_csr_t> timehCSR;

  public:
    SpikeSimif()
    {

        cfg = new cfg_t(std::make_pair(0, 0), "", "rv32i", "M", DEFAULT_VARCH, false, endianness_little, 0,
                        {mem_cfg_t(0x80000000, 1 << 26)}, {0}, false, 0);
        isa_parser = std::make_unique<isa_parser_t>("rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei", "MSU");
        processor = std::make_unique<processor_t>(isa_parser.get(), cfg, this, 0, false, stderr, std::cerr);
        harts[0] = processor.get();

        processor->set_pmp_num(0);

        processor->get_state()->pc = 0x80000000;
        processor->set_mmu_capability(IMPL_MMU_SV32);
        processor->set_debug(false);
        processor->get_state()->XPR.reset();
        processor->set_privilege(3);
        processor->enable_log_commits();

        std::array csrs_to_reset = {
            CSR_MSTATUS,    CSR_MSTATUSH, CSR_MCOUNTEREN, CSR_MCOUNTINHIBIT, CSR_MTVEC, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL,
            CSR_MIDELEG,    CSR_MIDELEGH, CSR_MEDELEG,    CSR_MIP,           CSR_MIPH,  CSR_MIE,  CSR_MIEH,

            CSR_SCOUNTEREN, CSR_SEPC,     CSR_SCAUSE,     CSR_STVEC,         CSR_STVAL, CSR_SATP, CSR_SENVCFG, CSR_MENVCFG, CSR_MSCRATCH, CSR_SSCRATCH};
        
        timeCSR = std::make_shared<basic_csr_t>(processor.get(), CSR_TIME, 0);
        timehCSR = std::make_shared<basic_csr_t>(processor.get(), CSR_TIMEH, 0);
        processor->get_state()->csrmap[CSR_TIME] = timeCSR;
        processor->get_state()->csrmap[CSR_TIMEH] = timehCSR;
        
        for (auto csr : csrs_to_reset)
            processor->put_csr(csr, 0);
    }

    virtual char* addr_to_mem(reg_t addr) override
    {
        if (addr >= 0x80000000 && addr < (0x80000000 + sizeof(pram))) return (char*)pram + (addr - 0x80000000);
        return nullptr;
    }
    virtual bool reservable(reg_t addr) override { return true; }
    virtual bool mmio_load(reg_t addr, size_t len, uint8_t* bytes) override
    {
        if (addr >= 0x10000000 && addr < 0x12000000) 
        {
            memset(bytes, 0, len);
            return true;
        }
        return false;
    }
    virtual bool mmio_store(reg_t addr, size_t len, const uint8_t* bytes) override
    {
        if (addr >= 0x10000000 && addr < 0x12000000) 
        {
            return true;
        }
        return false;
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

    uint32_t get_phy_addr (uint32_t addr)
    {
        uint32_t satp = processor->get_csr(CSR_SATP);
        if (!(satp >> 31)) return addr;
    }

    virtual int cosim_instr(const Inst& inst)
    {

        uint32_t initialSpikePC = get_pc();
        uint32_t instSIM;

        try
        {
            instSIM = processor->get_mmu()->load_insn(initialSpikePC).insn.bits();
        } catch (mem_trap_t) { instSIM = 0; }

        // failed sc.w (TODO: what if address is invalid?)
        if (((instSIM & 0b11111'00'00000'00000'111'00000'1111111) == 0b00011'00'00000'00000'010'00000'0101111) &&
            ReadRegister(inst.rd) != 0)
        {
            processor->get_mmu()->yield_load_reservation();
        }
        
        // WFI is currently a nop.
        if (instSIM == 0x10500073)
        {
            processor->get_state()->pc += 4;
            processor->get_state()->minstret->bump(1);
        }
        else
        {
            processor->step(1);
        }
        

        // TODO: Use this for adjusting WARL behaviour
        auto writes = processor->get_state()->log_reg_write;
        bool gprWritten = false;
        for (auto write : writes)
        {

        }

        bool mem_pass_thru = false;
        auto mem_reads = processor->get_state()->log_mem_read;
        for (auto read : mem_reads)
        {
            //try
            //{
            //    std::get<0>(read) = (uint32_t)processor->get_mmu()->translate(std::get<0>(read), 1, LOAD, 0);
            //} catch(mem_trap_t) {}

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
            case 0x11100000:
                mem_pass_thru = true;
                break; 
            }
        }
        
        bool writeValid = true;
        for (auto write : processor->get_state()->log_mem_write)
        {

        }

        if ((mem_pass_thru || is_pass_thru_inst(inst)) && inst.rd != 0 && inst.flags < 6)
        {
            processor->get_state()->XPR.write(inst.rd, inst.result);
        }

        if (inst.interrupt == Inst::IR_KEEP)
        {
            take_trap(true, inst.interruptCause, processor->get_state()->pc, inst.interruptDelegate);
        }

        bool instrEqual = ((instSIM & 3) == 3) ? instSIM == inst.inst : (instSIM & 0xFFFF) == (inst.inst & 0xFFFF);
        if (!instrEqual)
            return -1;
        if (inst.pc != initialSpikePC)
            return -2;
        if (!writeValid)
            return -3;
        if (!compare_state())
            return -4;
        return 0;
    }

    const std::map<size_t, processor_t*>& get_harts() const override
    {
        return harts;
    }

    void dump_state(FILE* stream, uint32_t ppc) const
    {
        fprintf(stderr,
                "mstatus=%.8lx mepc=%.8lx mcause=%.8lx mtvec=%.8lx mideleg=%.8lx medeleg=%.8lx mie=%.8lx mip=%.8lx\n",
                processor->get_csr(CSR_MSTATUS), processor->get_csr(CSR_MEPC), processor->get_csr(CSR_MCAUSE),
                processor->get_csr(CSR_MTVEC), processor->get_csr(CSR_MIDELEG), processor->get_csr(CSR_MEDELEG),
                processor->get_csr(CSR_MIE), processor->get_csr(CSR_MIP));
        fprintf(stream, "ir=%.8lx ppc=%.8x pc=%.8x priv=%lx\n", processor->get_state()->minstret->read() - 1, ppc, get_pc(), processor->get_state()->last_inst_priv);
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

    void take_trap(bool interrupt, reg_t cause, reg_t epc, bool delegate)
    {
        // taken from spike riscv/processor.cc: take_trap (which is private ...)
        auto& state = *processor->get_state();
        if (delegate)
        {
            processor->set_virt(false);
            reg_t vector = (state.stvec->read() & 1) && interrupt ? 4 * cause : 0;
            state.pc = (state.stvec->read() & ~(reg_t)1) + vector;
            state.scause->write(cause | (interrupt ? 0x80000000 : 0));
            state.sepc->write(epc);
            state.stval->write(0);
            //state.htval->write(t.get_tval2());
            //state.htinst->write(t.get_tinst());

            reg_t s = state.sstatus->read();
            s = set_field(s, MSTATUS_SPIE, get_field(s, MSTATUS_SIE));
            s = set_field(s, MSTATUS_SPP, state.prv);
            s = set_field(s, MSTATUS_SIE, 0);
            state.sstatus->write(s);
            /*if (extension_enabled('H')) {
            s = state.hstatus->read();
            if (curr_virt)
                s = set_field(s, HSTATUS_SPVP, state.prv);
            s = set_field(s, HSTATUS_SPV, curr_virt);
            s = set_field(s, HSTATUS_GVA, t.has_gva());
            state.hstatus->write(s);
            }*/
            processor->set_privilege(PRV_S);
        }
        else
        {
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
            if (state.mstatush) state.mstatush->write(s >> 32); // log mstatush change
            processor->set_privilege(PRV_M);
        }
    }

    std::string disasm (uint32_t instr)
    {
        return processor->get_disassembler()->disassemble(instr);
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
    auto core = top->Top->core;

    uint8_t comTag = regTagOverride[rid];
    if (comTag == 0xff) comTag = (core->rn->rt->rat[rid] >> 7) & 127;

    if (comTag & 64)
        return ((int32_t)(comTag & 63) << (32 - 6)) >> (32 - 6);
    else
        return core->rf->mem[comTag];
}

SpikeSimif simif;

void DumpState(FILE* stream, uint32_t pc, uint32_t inst)
{
    auto core = top->Top->core;
    fprintf(stderr, "time=%lu\n", main_time);
    fprintf(stream, "ir=%.8lx ppc=%.8x inst=%.8x sqn=%.2x\n", core->csr->minstret, pc, inst, lastComSqN);
    for (size_t j = 0; j < 4; j++)
    {
        for (size_t k = 0; k < 8; k++)
            fprintf(stream, "x%.2zu=%.8x ", j * 8 + k, ReadRegister(j * 8 + k));
        fprintf(stream, "\n");
    }
    fprintf(stream, "\n");
}

FILE* konataFile;

void Exit (int code)
{
#ifdef KONATA
    fflush(konataFile);
#endif
#ifdef TRACE
    tfp->flush();
#endif
    fflush(stdout);
    fflush(stderr);
    exit(code);
}

void LogCommit(Inst& inst)
{
    if (inst.interrupt == Inst::IR_SQUASH)
    {
#ifdef COSIM
        // printf("INTERRUPT %.8x\n", inst.pc);
        simif.take_trap(true, inst.interruptCause, inst.pc, inst.interruptDelegate);
#endif
    }
    else
    {
        if (inst.rd != 0 && inst.flags < 6) regTagOverride[inst.rd] = inst.tag;

#ifdef COSIM
        uint32_t startPC = simif.get_pc();
        if (int err = simif.cosim_instr(inst))
        {
            fprintf(stdout, "ERROR %u\n", -err);
            DumpState(stdout, inst.pc, inst.inst);

            fprintf(stdout, "\nSHOULD BE\n");
            simif.dump_state(stdout, startPC);
#ifdef KONATA
            fprintf(konataFile, "L\t%u\t%u\t COSIM ERROR \n", inst.id, 0);
            fflush(konataFile);
#endif
            Exit(-1);
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
    fprintf(konataFile, "I\t%u\t%u\t%u\n", inst.id, inst.fetchID, 0);
    fprintf(konataFile, "L\t%u\t%u\t%.8x: %s\n", inst.id, 0, inst.pc, simif.disasm(inst.inst).c_str());
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
    if (!(inst.tag & 0x40)) fprintf(konataFile, "L\t%u\t%u\tres=%.8x\n", inst.id, 1, inst.result);
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
    auto core = top->Top->core;

    bool brTaken = core->branch[0] & 1;
    int brSqN = ExtractField(core->branch, 74 - 32 - 7, 7);

    // Issue
    for (size_t i = 0; i < 4; i++)
    {
        if (!core->stall[i] && core->RV_uopValid[i])
        {
            uint32_t sqn = ExtractField<4>(core->RV_uop[i], 103 - (32 + 1 + 7 + 1 + 7 + 1 + 7 + 7), 7);
            LogIssue(insts[sqn]);
        }
    }

    // Execute
    for (size_t i = 0; i < 4; i++)
    {
        // EX valid
        if ((core->LD_uop[i][0] & 1) && !core->stall[i])
        {
            uint32_t sqn = ExtractField(core->LD_uop[i], 226 - 32 * 5 - 6 - 7 - 7, 7);
            insts[sqn].srcA = ExtractField(core->LD_uop[i], 226 - 32, 32);
            insts[sqn].srcB = ExtractField(core->LD_uop[i], 226 - 32 - 32, 32);
            insts[sqn].srcC = ExtractField(core->LD_uop[i], 226 - 32 - 32 - 32, 32);
            insts[sqn].imm = ExtractField(core->LD_uop[i], 226 - 32 - 32 - 32 - 32 - 32, 32);
            LogExec(insts[sqn]);
        }
    }

    // Memory Access
    for (auto& uop : {core->AGU_LD_uop, core->AGU_ST_uop})
        if (uop[0] & 1)
        {
            uint32_t sqn = ExtractField(uop, 156 - 32*2 - 4 - 1 - 2 - 1 - 32 - 7 - 7, 7);
            insts[sqn].memAddr =  ExtractField(uop, 156 - 32, 32);
            insts[sqn].memData =  ExtractField(uop, 156 - 32*2, 32);
        }

    // Result
    for (size_t i = 0; i < 4; i++)
    {
        // WB valid
        if (core->wbUOp[i] & 1)
        {
            uint32_t sqn = (core->wbUOp[i] >> 6) & 127;
            uint32_t result = (core->wbUOp[i] >> (6+7+7)) & 0xffff'ffff;
            insts[sqn].result = result;
            insts[sqn].flags = (core->wbUOp[i] >> 2) & 0xF;

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
            if ((core->comUOps[i] & 1) && !core->mispredFlush)
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
                    isXRETinterrupt =
                        (trapSQN == sqn) && ((flags == 5 || flags == 14) && core->rob->IN_interruptPending);
                }
                insts[sqn].interrupt = isInterrupt ? Inst::IR_SQUASH : Inst::IR_NONE;
                if (isXRETinterrupt) insts[sqn].interrupt = Inst::IR_KEEP;
                insts[sqn].interruptCause = (core->CSR_trapControl[0] >> 1) & 15;
                insts[sqn].interruptDelegate = core->CSR_trapControl[0] & 1;
                
                lastComSqN = curComSqN;
                LogCommit(insts[sqn]);
                mostRecentPC = insts[sqn].pc;
                insts[sqn].valid = false;
            }
        }
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
        if (core->IQS_ready)
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
        if (core->frontendEn && !core->RN_stall)
        {
            for (size_t i = 0; i < 4; i++)
                if (top->Top->core->DE_uop[i].at(0) & (1 << 0))
                {
                    de[i] = pd[i];
                    de[i].rd = ExtractField(core->DE_uop[i], 68 - 32 - 5 - 5 - 1 - 5, 5);
                    LogDecode(de[i]);
                }
                else
                {
                    if (pd[i].valid) LogFlush(pd[i]);
                    de[i].valid = false;
                }
        }
        // Predec
        if (!core->RN_stall && core->frontendEn)
        {
            for (size_t i = 0; i < 4; i++)
                if (core->PD_instrs[i].at(0) & 1)
                {
                    pd[i].valid = true;
                    pd[i].flags = 0;
                    pd[i].id = id++;
                    pd[i].pc = ExtractField(top->Top->core->PD_instrs[i], 119 - 31 - 32, 31) << 1;
                    pd[i].inst = ExtractField(top->Top->core->PD_instrs[i], 119 - 32, 32);
                    pd[i].fetchID = ExtractField(top->Top->core->PD_instrs[i], 4, 5);
                    if ((pd[i].inst & 3) != 3) pd[i].inst &= 0xffff;

                    LogPredec(pd[i]);
                }
                else
                    pd[i].valid = false;
        }
    }
    LogCycle();
}

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

        if (numInstrBytes & 3) numInstrBytes = (numInstrBytes & ~3) + 4;
        printf("Read %zu bytes of instructions\n", numInstrBytes);

        f = fopen("data.bin", "rb");
        numInstrBytes += fread(&pramBytes[numInstrBytes], sizeof(uint8_t), sizeof(pram) - numInstrBytes, f);

        fclose(f);
    }

    for (size_t i = 0; i < (1 << 24); i++)
        top->Top->extMem->mem[i] = pram[i];

#ifdef KONATA
    konataFile = fopen("trace_konata.txt", "w");
    fprintf(konataFile, "Kanata	0004\n");
#endif

#ifdef TRACE
    tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("Decode_tb.vcd");
#endif
    
#ifdef DUMP_FLAT
    {
        FILE* f = fopen("binary_flat.bin", "w");
        fwrite(&pram[0], sizeof(uint32_t), 1<<20, f); // 4 MiB
        fclose(f);
    }
#endif

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
    
    
    auto core = top->Top->core;
    uint64_t lastMInstret = core->csr->minstret;

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

#ifdef TRACE
        tfp->dump(main_time);
#endif

        if (top->clk == 1) 
        {
            LogInstructions();
        }
        
        // Hang Detection
        if ((main_time & (0xfff)) == 0)
        {
            uint64_t minstret = core->csr->minstret;
            if (minstret == lastMInstret)
            {
                fprintf(stderr, "ERROR: Hang detected\n");
                fprintf(stderr, "ROB_curSqN=%x\n", core->ROB_curSqN);
                DumpState(stderr, mostRecentPC, -1);
                Exit(-1);
            }
            lastMInstret = minstret;
        }
        main_time++;
    }

    // Run a few more cycles ...
    for (int i = 0; i < 3200; i = i + 1)
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
