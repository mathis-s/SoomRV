// #define TRACE
#define KONATA
#define COSIM
#define TOOLCHAIN "riscv32-unknown-linux-gnu-"

#ifdef TRACE
#define DEBUG_TIME -1
#else
#define DEBUG_TIME -1
#endif

#include "VTop.h"
#include "VTop_BranchPredictor__N3.h"
#include "VTop_CSR.h"
#include "VTop_Core.h"
#include "VTop_ExternalAXISim.h"
#include "VTop_ICacheTable.h"
#include "VTop_IF_Cache.h"
#include "VTop_IFetch.h"
#include "VTop_MemRTL__W54_N40_WB15.h"
#include "VTop_RegFile__A1.h"
#include "VTop_ROB.h"
#include "VTop_Rename.h"
#include "VTop_RenameTable.h"
#include "VTop_ReturnStack.h"
#include "VTop_SoC.h"
#include "VTop_StoreQueue.h"
#include "VTop_TagBuffer.h"
#include "VTop_Top.h"
#include <cstdio>
#include <iostream> // Need std::cout
#include <unistd.h>
#ifdef TRACE
#include "verilated_vcd_c.h"
#endif
#include <array>
#include <asm-generic/ioctls.h>
#include <cstring>
#include <exception>
#include <getopt.h>
#include <map>
#include <memory>
#include <sys/ioctl.h>

#include "riscv/cfg.h"
#include "riscv/csrs.h"
#include "riscv/decode.h"
#include "riscv/devices.h"
#include "riscv/disasm.h"
#include "riscv/log_file.h"
#include "riscv/memtracer.h"
#include "riscv/mmu.h"
#include "riscv/processor.h"
#include "riscv/simif.h"
#include "riscv/trap.h"

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
    uint8_t retIdx;
    bool incMinstret;
    bool interruptDelegate;
    enum InterruptType
    {
        IR_NONE,
        IR_SQUASH,
        IR_KEEP
    } interrupt;
    bool valid;
};

struct FetchPacket
{
    uint32_t returnAddr[4];
    uint64_t fetchTime;
    uint64_t pdTime;
};

struct Store
{
    uint32_t addr;
    uint32_t data;
    uint8_t size;
    uint64_t time;
};

struct
{
    uint32_t lastComSqN;
    uint32_t id = 0;
    uint32_t nextSqN;

    uint64_t committed = 0;
    Inst pd[4];
    Inst de[4];
    Inst insts[128];
    FetchPacket fetches[32];
    FetchPacket fetch0;
    FetchPacket fetch1;
} state;
int curCycInstRet = 0;
std::array<uint8_t, 32> regTagOverride;
std::vector<Store> inFlightStores;

VTop* top; // Instantiation of model
#ifdef TRACE
VerilatedVcdC* tfp;
#endif
uint32_t pram[1 << 26];
uint64_t main_time = 0;

double sc_time_stamp()
{
    return main_time;
}

uint32_t ReadRegister(uint32_t rid);

class SpikeSimif : public simif_t
{
  public:
    bool doRestore = false;

  private:
    std::unique_ptr<isa_parser_t> isa_parser;
    std::unique_ptr<processor_t> processor;
    bus_t bus;
    std::vector<std::unique_ptr<mem_t>> mems;
    std::vector<std::string> errors;
    cfg_t* cfg;
    std::map<size_t, processor_t*> harts;

    bool compare_state()
    {
        for (size_t i = 0; i < 32; i++)
            if ((uint32_t)processor->get_state()->XPR[i] != ReadRegister(i))
            {
                printf("mismatch x%zu\n", i);
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
            switch ((i.inst >> 12) & 0b111)
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

                        // TODO: these two only differ in warl behaviour,
                        // adjust on write instead of read.
                        case CSR_MCOUNTINHIBIT:
                        case CSR_SATP:

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

    std::shared_ptr<basic_csr_t> timeCSR;
    std::shared_ptr<basic_csr_t> timehCSR;

  public:
    SpikeSimif()
    {

        cfg = new cfg_t(std::make_pair(0, 0), "", "rv32i", "M", DEFAULT_VARCH, false, endianness_little, 0,
                        {mem_cfg_t(0x80000000, 1 << 26)}, {0}, false, 0);
        isa_parser = std::make_unique<isa_parser_t>("rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei_zcb", "MSU");
        processor = std::make_unique<processor_t>(isa_parser.get(), cfg, this, 0, false, stderr, std::cerr);
        harts[0] = processor.get();

        processor->set_pmp_num(0);

        processor->get_state()->pc = 0x80000000;
        processor->set_mmu_capability(IMPL_MMU_SV32);
        processor->set_debug(false);
        processor->get_state()->XPR.reset();
        processor->set_privilege(3, false);
        processor->enable_log_commits();

        std::array csrs_to_reset = {CSR_MSTATUS,    CSR_MSTATUSH, CSR_MCOUNTEREN, CSR_MCOUNTINHIBIT, CSR_MTVEC,
                                    CSR_MEPC,       CSR_MCAUSE,   CSR_MTVAL,      CSR_MIDELEG,       CSR_MIDELEGH,
                                    CSR_MEDELEG,    CSR_MIP,      CSR_MIPH,       CSR_MIE,           CSR_MIEH,
                                    CSR_SCOUNTEREN, CSR_SEPC,     CSR_SCAUSE,     CSR_STVEC,         CSR_STVAL,
                                    CSR_SATP,       CSR_SENVCFG,  CSR_MENVCFG,    CSR_MSCRATCH,      CSR_SSCRATCH};

        timeCSR = std::make_shared<basic_csr_t>(processor.get(), CSR_TIME, 0);
        timehCSR = std::make_shared<basic_csr_t>(processor.get(), CSR_TIMEH, 0);
        processor->get_state()->csrmap[CSR_TIME] = timeCSR;
        processor->get_state()->csrmap[CSR_TIMEH] = timehCSR;

        for (auto csr : csrs_to_reset)
            processor->put_csr(csr, 0);
    }

    virtual char* addr_to_mem(reg_t addr) override
    {
        if (addr >= 0x80000000 && addr < (0x80000000 + sizeof(pram)))
            return (char*)pram + (addr - 0x80000000);
        return nullptr;
    }
    virtual bool reservable(reg_t addr) override
    {
        return true;
    }
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

    uint32_t get_phy_addr(uint32_t addr, access_type type)
    {
        try
        {
            return (uint32_t)processor->get_mmu()->translate(
                processor->get_mmu()->generate_access_info(addr, type, (xlate_flags_t){}), 1);
        }
        catch (mem_trap_t)
        {
        }
        return addr;
    }

    void write_reg(int i, uint32_t data)
    {
        // this NEEDS to be sign-extended!
        processor->get_state()->XPR.write(i, (int32_t)data);
    }

    virtual int cosim_instr(const Inst& inst)
    {
        if (main_time > DEBUG_TIME)
            processor->set_debug(true);
        uint32_t initialSpikePC = get_pc();
        uint32_t instSIM;

        try
        {
            instSIM = processor->get_mmu()->load_insn(initialSpikePC).insn.bits();
        }
        catch (mem_trap_t)
        {
            instSIM = 0;
        }

        // failed sc.w
        if (((instSIM & 0b11111'00'00000'00000'111'00000'1111111) == 0b00011'00'00000'00000'010'00000'0101111) &&
            ReadRegister(inst.rd) != 0)
        {
            processor->get_mmu()->yield_load_reservation();
        }

        processor->step(1);

        // interrupts are handled by SoomRV
        processor->clear_waiting_for_interrupt();

        // TODO: Use this for adjusting WARL behavior
        auto writes = processor->get_state()->log_reg_write;
        bool gprWritten = false;
        for (auto write : writes) {}

        bool mem_pass_thru = false;
        auto mem_reads = processor->get_state()->log_mem_read;
        for (auto read : mem_reads)
        {
            uint32_t phy = get_phy_addr(std::get<0>(read), LOAD);
            //if (phy == 0x83ff5c00) printf("[%lu] load sqn = %x\n", main_time, inst.sqn);
            
            if (processor->debug) fprintf(stderr, "%.8x -> %.8x\n", (uint32_t)std::get<0>(read), phy);

            
            phy &= ~3;
            // MMIO is passed through
            if (phy >= 0x10000000 && phy < 0x12000000)
                mem_pass_thru = true;
        }

        bool writeValid = true;
        for (auto write : processor->get_state()->log_mem_write)
        {
            uint32_t phy = get_phy_addr(std::get<0>(write), STORE);
            if (processor->debug) fprintf(stderr, "%.8x -> %.8x\n", (uint32_t)std::get<0>(write), phy);
            //if (phy >= 0x80000000)
            //    inFlightStores.push_back((Store){
            //        .addr = phy, .data = (uint32_t)std::get<1>(write), .size = std::get<2>(write), .time = main_time});
        }

        if ((mem_pass_thru || is_pass_thru_inst(inst)) && inst.rd != 0 && inst.flags < 6)
        {
            write_reg(inst.rd, inst.result);
        }

        if (inst.interrupt == Inst::IR_KEEP)
        {
            take_trap(true, inst.interruptCause, processor->get_state()->pc, inst.interruptDelegate);
        }

        bool instrEqual = ((instSIM & 3) == 3) ? instSIM == inst.inst : (instSIM & 0xFFFF) == (inst.inst & 0xFFFF);
        if (inst.pc != initialSpikePC)
            return -1;
        if (!instrEqual)
            return -2;
        if (!writeValid)
            return -3;
        if (!compare_state())
            return -4;
        // if (processor->get_state()->minstret->read() != (top->Top->soc->core->csr->minstret + curCycInstRet))
        //     return -5;
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
        fprintf(stream, "ir=%.8lx ppc=%.8x pc=%.8x priv=%lx\n", processor->get_state()->minstret->read() - 1, ppc,
                get_pc(), processor->get_state()->last_inst_priv);
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
        class soomrv_trap_t : public trap_t
        {
          public:
            bool has_tval() override
            {
                return true;
            }
            reg_t get_tval() override
            {
                return 0;
            }
            soomrv_trap_t(reg_t which) : trap_t(which)
            {
            }
        };

        soomrv_trap_t trap(cause | (interrupt ? 0x80000000 : 0));
        processor->take_trap(trap, epc);
    }

    std::string disasm(uint32_t instr)
    {
        return processor->get_disassembler()->disassemble(instr);
    }

    void restore_from_top(Inst& inst)
    {
        doRestore = false;
        processor->get_state()->pc = inst.pc;

        for (size_t i = 0; i < 32; i++)
            write_reg(i, ReadRegister(i));

        auto csr = top->Top->soc->core->csr;
        // If ENABLE_FP is defined in Config.sv, these should be uncommented too
        // processor->put_csr(CSR_FFLAGS, csr->__PVT__fflags);
        // processor->put_csr(CSR_FRM, csr->__PVT__frm);

        processor->put_csr(CSR_INSTRET, csr->minstret & 0xFFFFFFFF);
        processor->put_csr(CSR_INSTRETH, csr->minstret >> 32);

        processor->put_csr(CSR_MSTATUS, csr->__PVT__mstatus);
        processor->put_csr(CSR_MCOUNTEREN, csr->__PVT__mcounteren);
        processor->put_csr(CSR_MCOUNTINHIBIT, csr->__PVT__mcountinhibit);
        processor->put_csr(CSR_MTVEC, csr->__PVT__mtvec);
        processor->put_csr(CSR_MEDELEG, csr->__PVT__medeleg);
        processor->put_csr(CSR_MIDELEG, csr->__PVT__mideleg);

        processor->put_csr(CSR_MIP, csr->__PVT__mip);
        processor->put_csr(CSR_MIE, csr->__PVT__mie);
        processor->put_csr(CSR_MSCRATCH, csr->__PVT__mscratch);
        processor->put_csr(CSR_MEPC, csr->__PVT__mepc);
        processor->put_csr(CSR_MCAUSE, csr->__PVT__mcause);
        processor->put_csr(CSR_MTVAL, csr->__PVT__mtval);
        processor->put_csr(CSR_MENVCFG, csr->__PVT__menvcfg);
        processor->put_csr(CSR_SCOUNTEREN, csr->__PVT__scounteren);
        processor->put_csr(CSR_SEPC, csr->__PVT__sepc);
        processor->put_csr(CSR_SSCRATCH, csr->__PVT__sscratch);
        processor->put_csr(CSR_STVAL, csr->__PVT__stval);
        processor->put_csr(CSR_STVEC, csr->__PVT__stvec);
        processor->put_csr(CSR_SATP, csr->__PVT__satp);
        processor->put_csr(CSR_SENVCFG, csr->__PVT__senvcfg);
        processor->put_csr(CSR_SCAUSE, csr->__PVT__scause);

        processor->set_privilege(csr->__PVT__priv, false);
    }
};

SpikeSimif simif;

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

uint32_t ReadRegister(uint32_t rid)
{
    auto core = top->Top->soc->core;

    uint8_t comTag = regTagOverride[rid];
    if (comTag == 0xff)
        comTag = (core->rn->rt->comTag[rid]);

    if (comTag & 64)
        return ((int32_t)(comTag & 63) << (32 - 6)) >> (32 - 6);
    else
        return core->rf->mem[comTag];
}

// ONLY use this for initialization!
// If there is a previously allocated
// physical register, it is not freed.
void WriteRegister(uint32_t rid, uint32_t val)
{
    #ifdef COSIM
    simif.write_reg(rid, val);
#endif
    auto core = top->Top->soc->core;

    int i = 0;
    while (true)
    {
        if ((core->rn->tb->free & (1UL << i)) && (core->rn->tb->freeCom & (1UL << i)))
        {
            core->rn->tb->free &= ~(1UL << i);
            core->rn->tb->freeCom &= ~(1UL << i);
            core->rn->rt->comTag[rid] = (i);
            core->rn->rt->specTag[rid] = (i);
            core->rn->rt->tagAvail |= (1 << i);
            core->rf->mem[i] = val;
            break;
        }
        i++;
        if (i == 64)
            abort();
    }
}

static bool kbhit()
{
    int buffered;
    ioctl(0, FIONREAD, &buffered);
    if (buffered == 0 && write(fileno(stdin), 0, 0) != 0)
        return 0;
    return buffered != 0;
}

static void HandleInput()
{
    auto emem = top->Top->extMem;
    if (!emem->inputAvail && kbhit())
    {
        emem->inputAvail = 1;
        emem->inputByte = getchar();
    }
}

void DumpState(FILE* stream, uint32_t pc, uint32_t inst)
{
    auto core = top->Top->soc->core;
    fprintf(stderr, "time=%lu\n", main_time);
    fprintf(stream, "ir=%.8lx ppc=%.8x inst=%.8x sqn=%.2x\n", core->csr->minstret, pc, inst, state.lastComSqN);
    for (size_t j = 0; j < 4; j++)
    {
        for (size_t k = 0; k < 8; k++)
            fprintf(stream, "x%.2zu=%.8x ", j * 8 + k, ReadRegister(j * 8 + k));
        fprintf(stream, "\n");
    }
    fprintf(stream, "\n");
}

FILE* konataFile;

void Exit(int code)
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

// Check writes to cache, 
// (reverse) translate the address via CT lookup,
// delete in-flight store entry on match
struct CacheWrite
{
    bool we;
    uint32_t addr;
    uint8_t wassoc;
    std::array<uint8_t, 16> wdata;
    uint16_t wmask;
};

std::array<CacheWrite, 3> GetCurrentWrites()
{
    // Regular write to cache
    std::array<CacheWrite, 3> ports = {};
    auto ifCache = top->Top->soc->__PVT__IF_cache;
    for (int i = 0; i < 2; i++)
    {
        ports[i].we = !((ifCache->__PVT__we >> i) & 1) && !((ifCache->__PVT__busy >> i) & 1);
        ports[i].addr = (ifCache->__PVT__addr >> i * 12) & 4095 & (~0xf);
        ports[i].wassoc = (ifCache->__PVT__wassoc >> i * 2) & 3;
        
        ports[i].wmask = (ifCache->__PVT__wmask >> i * 16) & 0xffff;

        for (int j = 0; j < 16; j++)
            ports[i].wdata[j] = ExtractField(ifCache->__PVT__wdata, 128 * i + 8 * j, 8);
    }
    // translate
    auto ict = top->Top->soc->dctable->mem;
    for (auto& port : ports)
    {
        if (!port.we)
            continue;
        int idx = port.addr / 64; // 64 byte cache lines
        uint32_t entry = ExtractField(ict[idx], 21 * port.wassoc, 21);
        if (!(entry & 1))
        {
            fprintf(stderr, "[%lu] invalid cache write\n", main_time);
            Exit(1);
        }
        port.addr = ((entry >> 1) << 12) | (port.addr & -16);
        // printf("[%.8x] = %x\n", port.addr, port.wdata);
    }
    
    // Writes fused into cache line load request
    auto memcReq = top->Top->soc->MemC_ctrl[1];
    auto memcStat = top->Top->soc->MemC_stat;
    
    auto cmd = ExtractField(memcReq, 0, 4);
    
    static bool allow = 1;
    if (allow && (cmd == 1 /*MEMC_REPLACE*/ || cmd == 3 /*MEMC_CP_EXT_TO_CACHE*/))
    {
        allow = 0;
        auto addr = ExtractField(memcReq, 5 + 32, 32) & ~0xf;
        auto mask = ExtractField(memcReq, 5 + 32 + 32 + 12 + 128, 16);
        std::array<uint8_t, 16> data;
        for (int i = 0; i < 16; i++)
            data[i] = ExtractField(memcReq, 5 + 32 + 32 + 12 + 8 * i, 8);

        if (mask != 0)
        {
            ports[2] = (CacheWrite){.we = 1,
                .addr = addr,
                                    .wassoc = 0, // unused
                .wdata = data,
                                    .wmask = (uint16_t)mask};
        }
    }
    
    // Allow memc extract in next cycle if not stalled
    allow = (cmd == 0) || !ExtractField(memcStat, 2, 1);
    return ports;
}

#if 0
void CheckStoreConsistency2()
{
    inFlightStores.clear();
    return;
    auto writes = GetCurrentWrites();
    auto core = top->Top->soc->core;

    auto it = inFlightStores.rbegin();
    int sqIter = 0;

    if (main_time > DEBUG_TIME)
    {
    fprintf(stderr, "---\n");
        for (int i = 0; i < 32; i = i + 1)
    {
            int idx = (((31 - i) + core->sq->baseIndex) % 32);
        if ((core->sq->entryReady_r & (1UL << idx)) && (core->sq->entries[idx][0] & 2))
        {
            uint32_t addr = ExtractField(core->sq->entries[idx], 13, 30) << 2;
            uint8_t mask = ExtractField(core->sq->entries[idx], 9, 4);

            fprintf(stderr, "sq: [%.8x] @ %.1x\n", addr, mask);
        }
    }

    for (auto& st : inFlightStores)
        printf("if: [%.8x] = %.8x << %d [%lu]\n", st.addr & ~3, st.data, st.addr & 3, st.time);
    }

    for (; it != inFlightStores.rend(); it++)
    {
        Store& store = *it;
        uint8_t storeMask = ((1 << store.size) - 1) << (store.addr & 3);

        // SQ entries
        // Youngest stores will still be in SQ
        for (; sqIter < 32; sqIter++)
        {
            int idx = (((31 - sqIter) + core->sq->baseIndex) % 32);
            if ((core->sq->entryReady_r & (1UL << idx)) && (core->sq->entries[idx][0] & 2))
            {
                uint32_t addr = ExtractField(core->sq->entries[idx], 13, 30) << 2;
                uint8_t mask = ExtractField(core->sq->entries[idx], 9, 4);

                if (addr == (store.addr & ~3) && mask == storeMask)
                {
                    sqIter++;
                    goto next_store;
                }
            }
        }

        // Just dequeued entry
        if ((core->sq->entryOut[0] & 1))
        {
            uint32_t addr = ExtractField(core->sq->entryOut, 13, 30) << 2;
            uint8_t mask = ExtractField(core->sq->entryOut, 9, 4);
            if (addr == (store.addr & -4) && mask == storeMask)
                it++;
        }
        break;
        next_store:;
    }

    // All stores beyond this point are flattened into the evicted queue.
    struct EQStore
    {
        uint16_t mask;
        std::array<uint8_t, 16> data = {};
        std::vector<Store> srcs;
    };
    std::unordered_map<uint32_t, EQStore> storesFlat = {};
    for (; it != inFlightStores.rend(); it++)
    {
        Store store = *it;
        auto& eqStore = storesFlat[store.addr & ~0xF];

        int offs = store.addr & 15;

        for (int i = 0; i < store.size; i++)
            if (!(eqStore.mask & (1 << (i + offs))))
                eqStore.data[i + offs] = (store.data >> (i * 8)) & 0xFF;
        
        eqStore.srcs.push_back(store);
        eqStore.mask |= ((1 << store.size) - 1) << offs;
    }
    
    std::array<bool, 4> evEntryUsed = {};
    
    if (main_time > DEBUG_TIME)
    for (int i = 0; i < 4; i++)
    {
        if (core->sq->evicted[i][0] & 1)
        {
            uint16_t wmask = ExtractField(core->sq->evicted[i], 5, 16);
            uint32_t addr = (ExtractField(core->sq->evicted[i], 21, 30) & ~3) << 2;
            std::array<uint8_t, 16> data;
            for (int j = 0; j < 16; j++)
                data[j] = ExtractField(core->sq->evicted[i], 51 + j * 8, 8);

            fprintf(stderr, "ev: [%.8x] =", addr);
            for (auto b = data.rbegin(); b != data.rend(); b++)
                fprintf(stderr, " %.2x", *b);
            fprintf(stderr, " (%.4x)\n", wmask);
        }
    }

    for (auto const& store : storesFlat)
    {
        auto& eqStore = store.second;

        for (int i = 0; i < 4; i++)
        {
            if (!evEntryUsed[i] && core->sq->evicted[i][0] & 1)
            {
                uint16_t wmask = ExtractField(core->sq->evicted[i], 5, 16);
                uint32_t addr = (ExtractField(core->sq->evicted[i], 21, 30) & ~3) << 2;
                std::array<uint8_t, 16> data;
                for (int j = 0; j < 16; j++)
                    data[j] = ExtractField(core->sq->evicted[i], 51 + j * 8, 8);
                
                bool dataMatch = 1;
                for (int j = 0; j < 16; j++)
                    if ((eqStore.mask & (1 << j)) && eqStore.data[j] != data[j])
                        dataMatch = 0;

                if (store.first == addr && wmask >= eqStore.mask && dataMatch)
                {
                    evEntryUsed[i] = 1;
                    goto store_found;
                }
            }
        }

        fprintf(stderr, "[%lu] could not find in EQ [%.8x] =", main_time, store.first);
        for (auto b = eqStore.data.rbegin(); b != eqStore.data.rend(); b++)
            fprintf(stderr, " %.2x", *b);
        fprintf(stderr, " (%.4x)\n", eqStore.mask);
        Exit(1);

        store_found:;
        
        // check if store is being executed
        for (size_t i = 0; i < writes.size(); i++)
        {
            auto& write = writes[i];
            if (write.we)
            {
                if (write.addr == store.first && write.wmask >= store.second.mask)
                {
                    /*if (main_time > DEBUG_TIME)
                    {
                        fprintf(stderr, "[%lu] MEM[%.8x] =", main_time, write.addr);
                        for (auto b = write.wdata.rbegin(); b != write.wdata.rend(); b++)
                            fprintf(stderr, " %.2x", *b);
                        fprintf(stderr, " (%.4x) write %zu\n", write.wmask, i);
                    }*/

                    for (auto itA = inFlightStores.begin(); itA != inFlightStores.end();)
                    {
                        for (auto itB = store.second.srcs.begin(); itB != store.second.srcs.end(); itB++)
                        {
                            if (itA->time == itB->time && itA->addr == itB->addr && itA->data == itB->data &&
                                itA->size == itB->size)
                            {
                                itA = inFlightStores.erase(itA);
                                goto found;
                            }
                        }
                        itA++;
                        found:;
                    }
                }
            }
        }
    }

    for (size_t i = 0; i < writes.size(); i++)
    {
        auto& write = writes[i];
        if (write.we && main_time > DEBUG_TIME)
        {
            fprintf(stderr, "[%lu] MEM[%.8x] =", main_time, write.addr);
            for (auto b = write.wdata.rbegin(); b != write.wdata.rend(); b++)
                fprintf(stderr, " %.2x", *b);
            fprintf(stderr, " (%.4x) write %zu\n", write.wmask, i);
        }
    }
}
    
// every store that hasn't yet been written to cache must be in the StoreQueue
void CheckStoreConsistency()
{
    std::array<bool, 32> entryUsedSQ = {};
    std::array<bool, 4> entryUsedEQ = {};
    bool entryOutUsed = 0;

    auto writes = GetCurrentWrites();

    auto core = top->Top->soc->core;
    for (auto it = inFlightStores.begin(); it != inFlightStores.end();)
    {
        Store& store = *it;
        uint8_t storeMask = ((1 << store.size) - 1) << (store.addr & 3);

        // check if we can find store in SQ entries or SQ evicted
        
        bool isEvicted = 0;

        // SQ evicted
        for (int i = 0; i < 4; i++)
        {
            if (!entryUsedEQ[i] && (core->sq->evicted[i][0] & 1))
            {
                uint32_t addr = (ExtractField(core->sq->evicted[i], 20, 30) << 2) & ~0xf;
                uint32_t mask = ExtractField(core->sq->evicted[i], 4, 16);
                int offs = __builtin_ctz(mask) / 4;
                addr += offs * 4;
                mask = (mask >> (offs * 4)) & 0xf;

                // fprintf(stderr, "ev: [%.8x] @ %.4x\n", addr, mask);
                if (addr == (store.addr & -4) && mask == storeMask)
                {
                    entryUsedEQ[i] = 1;
                    isEvicted = 1;
                    goto found_entry;
                }
            }
        }
        
        // Just dequeued entry
        if (!entryOutUsed && (core->sq->entryOut[0] & 1))
        {
            uint32_t addr = ExtractField(core->sq->entryOut, 13, 30) << 2;
            uint8_t mask = ExtractField(core->sq->entryOut, 9, 4);
            if (addr == (store.addr & -4) && mask == storeMask)
            {
                entryOutUsed = 1;
                goto found_entry;
            }
        }

        // SQ entries
        for (int i = 0; i < 32; i++)
        {
            int idx = 32 - 1 - ((i + core->sq->baseIndex) % 32);
            if (!entryUsedSQ[idx] && (core->sq->entryReady_r & (1UL << idx)) && (core->sq->entries[idx][0] & 2))
            {
                uint32_t addr = ExtractField(core->sq->entries[idx], 13, 30) << 2;
                uint8_t mask = ExtractField(core->sq->entries[idx], 9, 4);
                if (addr == (store.addr & -4) && mask == storeMask)
                {
                    entryUsedSQ[idx] = 1;
                    goto found_entry;
                }
            }
        }

        fprintf(stderr, "[%lu] cannot find store in SQ/EQ: MEM%d[%.8x] = %x %.1x (commit time %lu)\n", main_time,
                store.size * 8, store.addr, store.data, storeMask, store.time);
        DumpState(stderr, -1, -1);
        Exit(1);
        found_entry:

        // check if store is being executed
        auto writeIt = std::find_if(writes.begin(), writes.end(),
                                    [&](CacheWrite const& w)
                                    { return w.we && (w.addr & -4) == (store.addr & -4) && w.wmask == storeMask; });
        if (writeIt != writes.end())
        {
            writeIt->we = 0;
            if (!isEvicted)
            {
                fprintf(stderr, "[%lu] inconsistent cache write\n", main_time);
                Exit(1);
            }
            if (main_time > DEBUG_TIME)
                fprintf(stderr, "[%lu] MEM%d[%.8x] = %x (%zu, commit time %lu)\n", main_time, store.size * 8,
                        store.addr, store.data, writeIt - writes.begin(), store.time);
            it = inFlightStores.erase(it);
            continue;
        }
        it++;
    }
    
    for (size_t i = 0; i < writes.size(); i++)
    {
        auto& write = writes[i];
        if (write.we)
        {
            fprintf(stderr, "[%lu] MEM[%.8x] = %x (%x) write %zu unaccounted for\n", main_time, write.addr, write.wdata,
                    write.wmask, i);
            Exit(1);
        }
    }
}
#endif

void LogFlush(Inst& inst);

void LogCommit(Inst& inst)
{
#ifdef COSIM
    if (simif.doRestore)
        simif.restore_from_top(inst);
#endif
    if (inst.interrupt == Inst::IR_SQUASH)
    {
#ifdef COSIM
        // printf("INTERRUPT %.8x\n", inst.pc);
        simif.take_trap(true, inst.interruptCause, inst.pc, inst.interruptDelegate);
#endif
#ifdef KONATA
        // This is a fake interrupt instruction,
        // show it as flushed in Konata
        LogFlush(inst);
#endif
    }
    else
    {
        if (inst.incMinstret)
            curCycInstRet++;

        if (inst.rd != 0 && inst.flags < 6)
            regTagOverride[inst.rd] = inst.tag;

#ifdef COSIM
        uint32_t startPC = simif.get_pc();
        if (int err = simif.cosim_instr(inst))
        {
            fprintf(stdout, "ERROR %u (sqN=%.2x)\n", -err, inst.sqn);
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

static uint64_t hpm4offset = 0;
void LogPredec(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "I\t%u\t%u\t%u\n", inst.id, inst.fetchID, 0);
    // For return stack debugging
    /*fprintf(konataFile, "L\t%u\t%u\t (%.5ld) %d %.3x %.3x %.3x %.3x| \n", inst.id, 0, main_time, inst.retIdx,
        state.fetches[inst.fetchID].returnAddr[0] * 2 & 0xfff,
        state.fetches[inst.fetchID].returnAddr[1] * 2 & 0xfff,
        state.fetches[inst.fetchID].returnAddr[2] * 2 & 0xfff,
        state.fetches[inst.fetchID].returnAddr[3] * 2 & 0xfff);*/

    fprintf(konataFile, "L\t%u\t%u\t%.8x (%.8x): %s\n", inst.id, 0, inst.pc, inst.inst,
            simif.disasm(inst.inst).c_str());

    fprintf(konataFile, "C\t-%lu\n",
        (main_time-state.fetches[inst.fetchID].fetchTime)/2);
    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "IF");
    if ((state.fetches[inst.fetchID].pdTime < state.fetches[inst.fetchID].fetchTime))
    {
        printf("%li %li\n", state.fetches[inst.fetchID].fetchTime, state.fetches[inst.fetchID].pdTime);
        Exit(1);
    }
    fprintf(konataFile, "C\t%lu\n",
        (state.fetches[inst.fetchID].pdTime - state.fetches[inst.fetchID].fetchTime)/2);

    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "PD");
    fprintf(konataFile, "C\t%lu\n",
        (main_time - state.fetches[inst.fetchID].pdTime)/2);

    
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
    curCycInstRet = 0;
    memset(regTagOverride.data(), 0xFF, sizeof(regTagOverride));
#ifdef KONATA
    fprintf(konataFile, "C\t1\n");
#endif
}

uint32_t mostRecentPC;
void LogInstructions()
{
#ifdef COSIM
    //CheckStoreConsistency2();
#endif

    auto core = top->Top->soc->core;

    bool brTaken = core->branch[0] & 1;
    int brSqN = ExtractField(core->branch, 1 + 5 + 1 + 7 + 7, 8);

    // Issue
    for (size_t i = 0; i < 4; i++)
    {
        if (!core->stall[i] && core->IS_uop[i][0] & 1)
        {
            uint32_t sqn = ExtractField<4>(core->IS_uop[i], 116 - (32 + 12 + 1 + 7 + 1 + 7 + 1 + 7 + 7), 7);
            LogIssue(state.insts[sqn]);
        }
    }

    // Execute
    for (size_t i = 0; i < 4; i++)
    {
        // EX valid
        if ((core->LD_uop[i][0] & 1) && !core->stall[i])
        {
            uint32_t sqn = ExtractField(core->LD_uop[i], 1 + 1 + 4 + 7 + 7 + 2 + 5, 7);
            state.insts[sqn].srcA = ExtractField(core->LD_uop[i], 184 - 32, 32);
            state.insts[sqn].srcB = ExtractField(core->LD_uop[i], 184 - 32 - 32, 32);
            state.insts[sqn].imm = ExtractField(core->LD_uop[i], 184 - 32 - 32 - 32 - 3 - 3 - 32, 32);
            LogExec(state.insts[sqn]);
        }
    }

    // Memory Access
    /*for (auto& uop : {core->AGU_LD_uop, core->AGU_ST_uop})
        if (uop[0] & 1)
        {
            uint32_t sqn = ExtractField(uop, 156 - 32 * 2 - 4 - 1 - 2 - 1 - 32 - 7 - 7, 7);
            state.insts[sqn].memAddr = ExtractField(uop, 156 - 32 - 32, 32);
            state.insts[sqn].memData = 0; // ExtractField(uop, 156 - 32 * 2, 32);
        }*/

    // Result
    for (size_t i = 0; i < 6; i++)
    {
        uint32_t sqn = (core->wbUOp[i] >> 6) & 127;
        // WB valid
        if ((core->wbUOp[i] & 1) && !(core->wbUOp[i] & 2))
        {
            uint32_t result = (core->wbUOp[i] >> (6 + 7 + 7)) & 0xffff'ffff;
            state.insts[sqn].result = result;
            state.insts[sqn].flags = (core->wbUOp[i] >> 2) & 0xF;

            // FP ops use a different flag encoding. These are not traps, so ignore them.
            if ((state.insts[sqn].fu == 5 || state.insts[sqn].fu == 6 || state.insts[sqn].fu == 7) &&
                state.insts[sqn].flags >= 8 && state.insts[sqn].flags <= 13)
                state.insts[sqn].flags = 0;

            LogResult(state.insts[sqn]);
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

                // assert(state.insts[sqn].valid);
                // assert(state.insts[sqn].sqn == (uint32_t)sqn);

                bool isInterrupt = false;
                bool isXRETinterrupt = false;
                if (core->ROB_trapUOp & 1)
                {
                    int trapSQN = (core->ROB_trapUOp >> (15 + 14)) & 127;
                    int flags = (core->ROB_trapUOp >> (29 + 14)) & 15;
                    int rd = (core->ROB_trapUOp >> 10) & 31;
                    isInterrupt = (trapSQN == sqn) && flags == 7 && rd == 16;
                    isXRETinterrupt =
                        (trapSQN == sqn) && ((flags == 5 || flags == 14) && core->rob->IN_interruptPending);
                }
                state.insts[sqn].interrupt = isInterrupt ? Inst::IR_SQUASH : Inst::IR_NONE;
                if (isXRETinterrupt)
                    state.insts[sqn].interrupt = Inst::IR_KEEP;
                state.insts[sqn].interruptCause = (core->CSR_trapControl[0] >> 1) & 15;
                state.insts[sqn].interruptDelegate = core->CSR_trapControl[0] & 1;
                state.insts[sqn].incMinstret = (core->ROB_perfcInfo & (1 << i));

                state.lastComSqN = curComSqN;
                LogCommit(state.insts[sqn]);
                mostRecentPC = state.insts[sqn].pc;
                state.insts[sqn].valid = false;
            }
        }
    }

    // Branch Taken
    if (brTaken)
    {
        uint32_t i = (brSqN + 1) & 127;
        while (i != state.nextSqN)
        {
            if (state.insts[i].valid)
                LogFlush(state.insts[i]);
            i = (i + 1) & 127;
        }

        for (size_t i = 0; i < 4; i++)
        {
            if (state.de[i].valid)
                LogFlush(state.de[i]);
            if (state.pd[i].valid)
                LogFlush(state.pd[i]);
        }
    }
    else
    {
        // Rename
        for (size_t i = 0; i < 4; i++)
            if (core->RN_uop[i][0] & 1)
            {
                int sqn = ExtractField<4>(core->RN_uop[i], 46 + 6, 7);
                int fu = ExtractField<4>(core->RN_uop[i], 2 + 6, 4);
                uint8_t tagDst = ExtractField<4>(core->RN_uop[i], 46 + 6 - 7, 7);

                state.insts[sqn].valid = 1;
                state.insts[sqn] = state.de[i];
                state.insts[sqn].sqn = sqn;
                state.insts[sqn].fu = fu;
                state.insts[sqn].tag = tagDst;
                state.nextSqN = (sqn + 1) & 127;

                LogRename(state.insts[sqn]);
            }

        // Decode
        if (core->frontendEn && !core->RN_stall)
        {
            for (size_t i = 0; i < 4; i++)
                if (top->Top->soc->core->DE_uop[i].at(0) & (1 << 0))
                {
                    state.de[i] = state.pd[i];
                    state.de[i].rd = ExtractField(core->DE_uop[i], 80 - 32 - 12 - 5 - 5 - 1 - 5, 5);
                    LogDecode(state.de[i]);
                }
                else
                {
                    if (state.pd[i].valid)
                        LogFlush(state.pd[i]);
                    state.de[i].valid = false;
                }
        }
        // Predec
        if (!core->RN_stall && core->frontendEn)
        {
            for (size_t i = 0; i < 4; i++)
                if ((core->PD_instrs[i].at(0) & 1))
                {
                    state.pd[i].valid = true;
                    state.pd[i].flags = 0;
                    state.pd[i].id = state.id++;
                    state.pd[i].pc = ExtractField(top->Top->soc->core->PD_instrs[i], 124 - 12 - 31 - 32, 31) << 1;
                    state.pd[i].inst = ExtractField(top->Top->soc->core->PD_instrs[i], 124 - 12 - 32, 32);
                    state.pd[i].fetchID = ExtractField(top->Top->soc->core->PD_instrs[i], 4, 5);
                    //state.pd[i].retIdx =
                    //    ExtractField(top->Top->soc->core->PD_instrs[i], 120 - 32 - 31 - 31 - 1 - 12 - 2, 2);
                    if ((state.pd[i].inst & 3) != 3)
                        state.pd[i].inst &= 0xffff;

                    LogPredec(state.pd[i]);
                }
                else
                    state.pd[i].valid = false;
        }

        if (core->ifetch->ict->fetch0[0] & 1)
        {
            for (int i = 0; i < 4; i++)
                state.fetches[core->ifetch->ict->fetchID].returnAddr[i] = core->ifetch->bp->retStack->rstack[i];

            state.fetches[core->ifetch->ict->fetchID].fetchTime = main_time;
        }

        if ((core->IF_instrs[0] & 1))
        {
            int fetchID = ExtractField(core->ifetch->ict->packetRePred, 1 + 128 + 2 + 31 + 1 + 3 + 3 + 3 + 2, 5);
            state.fetches[fetchID].pdTime = main_time + 2;
        }
    }
    LogCycle();
}
void save_model(std::string fileName)
{
    VerilatedSave os;
    os.open(fileName.c_str());
    os << main_time; // user code must save the timestamp
    os << *top;

#if defined(COSIM) | defined(KONATA)
    FILE* f = fopen((fileName + "_cosim").c_str(), "wb");
    if (fwrite(pram, sizeof(uint8_t), sizeof(pram), f) != sizeof(pram))
        abort();
    if (fwrite(&state, sizeof(state), 1, f) != 1)
        abort();
    fclose(f);
#endif
}
void restore_model(std::string fileName)
{
    VerilatedRestore os;
    os.open(fileName.c_str());
    os >> main_time;
    os >> *top;

#if defined(COSIM) | defined(KONATA)
    FILE* f = fopen((fileName + "_cosim").c_str(), "rb");
    if (fread(pram, sizeof(uint8_t), sizeof(pram), f) != sizeof(pram))
        abort();
    if (fread(&state, sizeof(state), 1, f) != 1)
        abort();
    fclose(f);

    long offset = state.insts[state.lastComSqN].id;
    for (size_t i = 0; i < 128; i++)
        state.insts[i].id -= offset;
    for (size_t i = 0; i < 4; i++)
    {
        state.pd[i].id -= offset;
        state.de[i].id -= offset;
    }
    state.id -= offset;
#endif
}

struct Args
{
    std::string progFile;
    std::string deviceTreeFile;
    std::string backupFile;
    std::string memDumpFile;
    bool restoreSave = 0;
    uint32_t deviceTreeAddr = 0;
    bool logPerformance = 0;
};

static void ParseArgs(int argc, char** argv, Args& args)
{
    static struct option long_options[] = {
        {"device-tree", required_argument, 0, 'd'},
        {"backup-file", required_argument, 0, 'b'},
        {"dump-mem", required_argument, 0, 'o'},
        {"perfc", no_argument, 0, 'p'},
    };
    int idx;
    int c;
    while ((c = getopt_long(argc, argv, "d:b:o:p", long_options, &idx)) != -1)
    {
        switch (c)
        {
            case 'd': args.deviceTreeFile = std::string(optarg); break;
            case 'b': args.backupFile = std::string(optarg); break;
            case 'o': args.memDumpFile = std::string(optarg); break;
            case 'p': args.logPerformance = 1; break;
            default: break;
        }
    }

    if (optind < argc && argv[optind][0] != '+')
        args.progFile = std::string(argv[optind]);

    if (args.progFile.empty())
    {
        fprintf(stderr,
                "usage: %s [options] <ELF BINARY>.elf|<BACKUP FILE>.backup|<ASSEMBLY FILE>\n"
                "Options:\n"
                "\t"
                "--device-tree, -d: Load device tree binary, store address in a1 at boot.\n"
                "\t"
                "--backup-file, -b: Periodically save state in specified file. Reload by specifying backup file as "
                "program.\n"
                "\t"
                "--dump-mem, -o:    Dump memory into output file after loading binary.\n"
                "\t"
                "--perfc, p:        Periodically dump performance counter stats.\n",
                argv[0]);
        // clang-format on
        exit(-1);
    }
}

void Initialize(int argc, char** argv, Args& args)
{
    ParseArgs(argc, argv, args);

    if (args.progFile.find(".backup", args.progFile.size() - 7) != std::string::npos)
        args.restoreSave = true;
    else if (args.progFile.find(".elf", args.progFile.size() - 4) == std::string::npos &&
             args.progFile.find(".out", args.progFile.size() - 4) == std::string::npos)
    {
        if (system((std::string(TOOLCHAIN
                                "as -mabi=ilp32 -march=rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei -o temp.o ") +
                    args.progFile)
                       .c_str()) != 0)
            abort();
        if (system(TOOLCHAIN "ld --no-warn-rwx-segments -Tlinker.ld test_programs/entry.o temp.o") != 0)
            abort();
        args.progFile = "a.out";
    }

    if (!args.restoreSave)
    {
        if (system(std::string(TOOLCHAIN "objcopy -I elf32-little -j .text -O binary " + args.progFile + " text.bin")
                       .c_str()) != 0)
            abort();
        if (system(std::string(TOOLCHAIN "objcopy -I elf32-little -j .data -O binary " + args.progFile + " data.bin")
                       .c_str()) != 0)
            abort();

        size_t numProgBytes = 0;
        {
            uint8_t* pramBytes = (uint8_t*)pram;

            FILE* f = fopen("text.bin", "rb");
            if (!f)
                abort();
            numProgBytes = fread(pramBytes, sizeof(uint8_t), sizeof(pram), f);
            fclose(f);

            if (numProgBytes & 3)
                numProgBytes = (numProgBytes & ~3) + 4;

            f = fopen("data.bin", "rb");
            if (!f)
                abort();
            numProgBytes += fread(&pramBytes[numProgBytes], sizeof(uint8_t), sizeof(pram) - numProgBytes, f);
            fclose(f);
        }

        if (!args.memDumpFile.empty())
        {
            FILE* f = fopen(args.memDumpFile.c_str(), "w");
            fwrite(&pram[0], sizeof(uint32_t), numProgBytes, f);
            fclose(f);
        }

        // Device Tree
        args.deviceTreeAddr = 0;
        if (!args.deviceTreeFile.empty())
        {
            args.deviceTreeAddr = 0x80000000 + 0x4000000 - 1024 * 1024;
            FILE* dtbFile = fopen(args.deviceTreeFile.c_str(), "rb");
            if (!dtbFile)
                abort();
            fread((char*)pram + args.deviceTreeAddr - 0x80000000, sizeof(uint8_t),
                  sizeof(pram) - (args.deviceTreeAddr - 0x80000000), dtbFile);
            fclose(dtbFile);
        }
    }
}

void LogPerf(VTop_Core* core)
{
    std::array<uint64_t, 16> counters = {
        core->csr->mcycle,       core->csr->minstret,     core->csr->mhpmcounter[3],
        core->csr->mhpmcounter[4], core->csr->mhpmcounter[5],

        core->csr->mhpmcounter[6], core->csr->mhpmcounter[7],
        core->csr->mhpmcounter[8], core->csr->mhpmcounter[9],
        core->csr->mhpmcounter[10], core->csr->mhpmcounter[11],

        core->csr->mhpmcounter[12], core->csr->mhpmcounter[13],
        core->csr->mhpmcounter[14], core->csr->mhpmcounter[15],
        core->csr->mhpmcounter[16], 
        
    };
    static std::array<uint64_t, 16> lastCounters;

    std::array<uint64_t, 16> current;
    for (size_t i = 0; i < counters.size(); i++)
        current[i] = counters[i] - lastCounters[i];

    double ipc = (double)current[1] / current[0];
    double mpki = (double)current[4] / (current[1] / 1000.0);
    double bmrate = ((double)current[3] / current[2]) * 100.0;

    fprintf(stderr, "cycles:             %lu\n", current[0]);
    fprintf(stderr, "instret:            %lu # %f IPC \n", current[1], ipc);
    fprintf(stderr, "mispredicts:        %lu # %f MPKI \n", current[4], mpki);
    fprintf(stderr, "branch mispredicts: %lu # %f%%\n", current[3], bmrate);
    fprintf(stderr, "branches:           %lu\n", current[2]);
    fprintf(stderr, "frontend stalled:   %lu # %f%%\n", current[12-1], 100.*current[12-1]/(4*current[0]));
    fprintf(stderr, "backend stalled:    %lu # %f%%\n", current[13-1], 100.*current[13-1]/(4*current[0]));
    fprintf(stderr, "store stalled:      %lu # %f%%\n", current[14-1], 100.*current[14-1]/(4*current[0]));
    fprintf(stderr, "load stalled:       %lu # %f%%\n", current[15-1], 100.*current[15-1]/(4*current[0]));
    fprintf(stderr, "ROB stalled:        %lu # %f%%\n", current[16-1], 100.*current[16-1]/(4*current[0]));

    fprintf(stderr, 
        "%7lu # %2.0f ORD | %7lu # %2.0f BTK | %7lu # %2.0f BNT\n"
        "%7lu # %2.0f RET | %7lu # %2.0f IBR | %7lu # %2.0f MEM\n",
        current[5], 100.*current[5] / current[4],
        current[6], 100.*current[6] / current[4],
        current[7], 100.*current[7] / current[4],
        current[8], 100.*current[8] / current[4],
        current[9], 100.*current[9] / current[4],
        current[10], 100.*current[10] / current[4]);

    lastCounters = counters;
}

int main(int argc, char** argv)
{
    memset(regTagOverride.data(), 0xFF, sizeof(regTagOverride));

    Verilated::commandArgs(argc, argv); // Remember args
#ifdef TRACE
    Verilated::traceEverOn(true);
#endif

    Args args;
    Initialize(argc, argv, args);

    top = new VTop;
    top->clk = 0;

#ifdef KONATA
    konataFile = fopen("trace_konata.txt", "w");
    fprintf(konataFile, "Kanata	0004\n");
#endif

#ifdef TRACE
    tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("Top_tb.vcd");
#endif

    auto core = top->Top->soc->core;

    if (args.restoreSave)
    {
        restore_model(args.progFile);
        simif.doRestore = true;
    }
    else
    {
        for (size_t i = 0; i < (1 << 24); i++)
            top->Top->extMem->mem[i >> 2][i & 3] = pram[i];

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
    }

    if (args.deviceTreeAddr != 0)
        WriteRegister(11, args.deviceTreeAddr);

    const uint64_t perfInterval = 1024 * 1024 * 8;
    uint64_t lastMInstret = core->csr->minstret;
    uint64_t nextMinstretPerf = core->csr->minstret + perfInterval;

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
        if (main_time > DEBUG_TIME)
            tfp->dump(main_time);
#endif

        if (top->clk == 1)
            LogInstructions();

        // Input
        if ((main_time & 0xff) == 0)
            HandleInput();

        // Hang Detection
        if ((main_time & (0x3fff)) == 0 && !args.restoreSave && !core->ifetch->waitForInterrupt)
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
        if (core->csr->minstret >= nextMinstretPerf)
        {
            if (args.logPerformance)
                LogPerf(core);
            nextMinstretPerf = core->csr->minstret + perfInterval;
        }
        if ((main_time & 0xffffff) == 0)
        {
            if (!args.backupFile.empty())
                save_model(args.backupFile);
        }
        args.restoreSave = 0;
        main_time++;
    }

    // Run a few more cycles ...
    for (int i = 0; i < 128; i = i + 1)
    {
        top->clk = !top->clk;
        top->eval(); // Evaluate model
#ifdef TRACE
        tfp->dump(main_time);
#endif
        main_time++; // Time passes...
    }

    LogPerf(core);

    printf("%lu cycles\n", main_time / 2);

    top->final(); // Done simulating
#ifdef TRACE
    tfp->flush();
    tfp->close();
    delete tfp;
#endif
    delete top;
}
