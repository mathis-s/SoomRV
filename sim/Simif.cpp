#include "Simif.hpp"
#include "TopWrapper.hpp"
#include "Debug.hpp"

bool SpikeSimif::compare_state()
{
    for (size_t i = 0; i < 32; i++)
        if ((uint32_t)processor->get_state()->XPR[i] != registers.ReadRegister(i))
        {
            printf("mismatch x%zu\n", i);
            return false;
        }

    return true;
}
bool SpikeSimif::is_pass_thru_inst(const Inst& i)
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
                if (csrID >= CSR_MCYCLE && csrID <= CSR_MHPMCOUNTER31) return true;
                if (csrID >= CSR_MCYCLEH && csrID <= CSR_MHPMCOUNTER31H) return true;
                if (csrID >= CSR_CYCLE && csrID <= CSR_HPMCOUNTER31) return true;
                if (csrID >= CSR_CYCLEH && csrID <= CSR_HPMCOUNTER31H) return true;

                switch (csrID)
                {
                    case CSR_CYCLE:
                    case CSR_CYCLEH:
                    case CSR_MCYCLE:
                    case CSR_MCYCLEH:
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
SpikeSimif::SpikeSimif(std::vector<uint32_t>& pram, Registers& registers, uint64_t& main_time)
    : pram(pram), main_time(main_time), registers(registers)
{
    cfg = new cfg_t(std::make_pair(0, 0), "", "rv32i", "M", DEFAULT_VARCH, false, endianness_little, 0,
                    {mem_cfg_t(0x80000000, 1 << 26)}, {0}, false, 0);
    isa_parser = std::make_unique<isa_parser_t>("rv32imac_zicsr_zba_zbb_zbs_zicbom_zifencei_zcb_zihpm_zicntr", "MSU");
    processor = std::make_unique<processor_t>(isa_parser.get(), cfg, this, 0, false, stderr, std::cerr);
    harts[0] = processor.get();

    processor->set_pmp_num(0);

    processor->get_state()->pc = 0x80000000;
    processor->set_mmu_capability(IMPL_MMU_SV32);
    processor->set_debug(false);
    processor->get_state()->XPR.reset();
    processor->set_privilege(3, false);
    processor->enable_log_commits();

    std::array csrs_to_reset = {CSR_MSTATUS, CSR_MSTATUSH, CSR_MCOUNTEREN, CSR_MCOUNTINHIBIT, CSR_MEPC,    CSR_MCAUSE,
                                CSR_MTVAL,   CSR_MIDELEG,  CSR_MIDELEGH,   CSR_MEDELEG,       CSR_MIP,     CSR_MIPH,
                                CSR_MIE,     CSR_MIEH,     CSR_SCOUNTEREN, CSR_SEPC,          CSR_SCAUSE,  CSR_STVAL,
                                CSR_SATP,    CSR_SENVCFG,  CSR_MENVCFG,    CSR_MSCRATCH,      CSR_SSCRATCH};

    timeCSR = std::make_shared<basic_csr_t>(processor.get(), CSR_TIME, 0);
    timehCSR = std::make_shared<basic_csr_t>(processor.get(), CSR_TIMEH, 0);
    processor->get_state()->csrmap[CSR_TIME] = timeCSR;
    processor->get_state()->csrmap[CSR_TIMEH] = timehCSR;
    processor->get_state()->mtvec->write(0x80000000);
    processor->get_state()->stvec->write(0x80000000);

    for (auto csr : csrs_to_reset)
        processor->put_csr(csr, 0);
}
char* SpikeSimif::addr_to_mem(reg_t addr)
{
    if (addr >= 0x80000000 && addr < (0x80000000 + pram.size() * sizeof(uint32_t)))
        return (char*)pram.data() + (addr - 0x80000000);
    return nullptr;
}
bool SpikeSimif::mmio_load(reg_t addr, size_t len, uint8_t* bytes)
{
    if (addr >= 0x10000000 && addr < 0x12000000)
    {
        memset(bytes, 0, len);
        return true;
    }
    return false;
}
bool SpikeSimif::mmio_store(reg_t addr, size_t len, const uint8_t* bytes)
{
    if (addr >= 0x10000000 && addr < 0x12000000)
    {
        return true;
    }
    return false;
}
uint32_t SpikeSimif::get_phy_addr(uint32_t addr, access_type type)
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
void SpikeSimif::write_reg(int i, uint32_t data)
{
    // this NEEDS to be sign-extended!
    processor->get_state()->XPR.write(i, (int32_t)data);
}
int SpikeSimif::cosim_instr(const Inst& inst)
{
    if (main_time > DEBUG_TIME)
        processor->set_debug(true);
    uint32_t initialSpikePC = get_pc();
    uint32_t instSIM;
    bool fetchFault = 0;
    try
    {
        instSIM = processor->get_mmu()->load_insn(initialSpikePC).insn.bits();
    }
    catch (mem_trap_t)
    {
        instSIM = 0;
        fetchFault = 1;
    }

    // failed sc.w
    if (((instSIM & 0b11111'00'00000'00000'111'00000'1111111) == 0b00011'00'00000'00000'010'00000'0101111) &&
        registers.ReadRegister(inst.rd) != 0)
    {
        processor->get_mmu()->yield_load_reservation();
    }

    bool modelsPass = 1;
    for (auto& model : models)
        modelsPass &= model->PreInst(inst);

    processor->step(1);

    for (auto& model : models)
        modelsPass &= model->PostInst(inst);

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
        if (processor->debug)
            fprintf(stderr, "%.8x -> %.8x\n", (uint32_t)std::get<0>(read), phy);


        phy &= ~3;
        // MMIO is passed through
        if (phy >= 0x10000000 && phy < 0x12000000)
            mem_pass_thru = true;
    }

    bool writeValid = true;
    for (auto write : processor->get_state()->log_mem_write)
    {
        uint32_t phy = get_phy_addr(std::get<0>(write), STORE);
        if (processor->debug)
            fprintf(stderr, "%.8x -> %.8x\n", (uint32_t)std::get<0>(write), phy);

        if (riscvTestMode)
        {
            if (phy == 0x80001000 || phy == 0x80003000)
                riscvTestReturn = std::get<1>(write);
            else if ((phy == 0x80001004 || phy == 0x80003004) && (int)std::get<1>(write) == 0)
                return 1;
        }
        // if (phy >= 0x80000000)
        //     inFlightStores.push_back((Store){
        //         .addr = phy, .data = (uint32_t)std::get<1>(write), .size = std::get<2>(write), .time = main_time});
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
    if (!instrEqual && !fetchFault)
        return -2;
    if (!writeValid)
        return -3;
    if (!compare_state())
        return -4;
    if (!modelsPass)
        return -5;
    if  (inst.minstret != processor->get_state()->csrmap[CSR_MINSTRET]->read())
        return -6;

    return 0;
}
void SpikeSimif::dump_state(FILE* stream, uint32_t ppc) const
{
    fprintf(stderr,
            "mstatus=%.8lx mepc=%.8lx mcause=%.8lx mtvec=%.8lx mideleg=%.8lx medeleg=%.8lx mie=%.8lx mip=%.8lx\n",
            processor->get_csr(CSR_MSTATUS), processor->get_csr(CSR_MEPC), processor->get_csr(CSR_MCAUSE),
            processor->get_csr(CSR_MTVEC), processor->get_csr(CSR_MIDELEG), processor->get_csr(CSR_MEDELEG),
            processor->get_csr(CSR_MIE), processor->get_csr(CSR_MIP));
    fprintf(stream, "ir=%.8lx ppc=%.8x pc=%.8x priv=%lx\n", processor->get_state()->minstret->read() - 1, ppc, get_pc(),
            processor->get_state()->last_inst_priv);
    for (size_t j = 0; j < 4; j++)
    {
        for (size_t k = 0; k < 8; k++)
            fprintf(stream, "x%.2zu=%.8x ", j * 8 + k, (uint32_t)processor->get_state()->XPR[j * 8 + k]);
        fprintf(stream, "\n");
    }
}
void SpikeSimif::take_trap(bool interrupt, reg_t cause, reg_t epc, bool delegate)
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
void SpikeSimif::restore_from_top(TopWrapper& wrap, Inst& inst)
{
    doRestore = false;
    processor->get_state()->pc = inst.pc;

    for (size_t i = 0; i < 32; i++)
        write_reg(i, registers.ReadRegister(i));

    auto csr = wrap.csr;
    // If ENABLE_FP is defined in Config.sv, these should be uncommented too
    // processor->put_csr(CSR_FFLAGS, csr->__PVT__fflags);
    // processor->put_csr(CSR_FRM, csr->__PVT__frm);

    processor->put_csr(CSR_INSTRET, (csr->minstret + 1) & 0xFFFFFFFF);
    processor->put_csr(CSR_INSTRETH, (csr->minstret + 1) >> 32);

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
