#pragma once

#include "Inst.hpp"
#include "Registers.hpp"
#include "TopWrapper.hpp"
#include "models/Model.hpp"

#include "VTop_CSR.h"
#include "riscv/cfg.h"
#include "riscv/csrs.h"
#include "riscv/decode.h"
#include "riscv/devices.h"
#include "riscv/disasm.h"
#include "riscv/memtracer.h"
#include "riscv/mmu.h"
#include "riscv/processor.h"
#include "riscv/simif.h"
#include "riscv/trap.h"

class SpikeSimif : public simif_t
{
  public:
    bool doRestore = false;
    std::vector<Model*> models;
    std::vector<uint32_t>& pram;
    uint64_t& main_time;
    Registers& registers;

    std::unique_ptr<isa_parser_t> isa_parser;
    std::unique_ptr<processor_t> processor;
    bus_t bus;
    std::vector<std::unique_ptr<mem_t>> mems;
    std::vector<std::string> errors;
    cfg_t* cfg;
    std::map<size_t, processor_t*> harts;

    bool compare_state();

    static bool is_pass_thru_inst(const Inst& i);

    std::shared_ptr<basic_csr_t> timeCSR;
    std::shared_ptr<basic_csr_t> timehCSR;

  public:
    SpikeSimif(std::vector<uint32_t>& pram, Registers& registers, uint64_t& main_time);

    virtual char* addr_to_mem(reg_t addr) override;
    virtual bool reservable(reg_t addr) override
    {
        return true;
    }
    virtual bool mmio_load(reg_t addr, size_t len, uint8_t* bytes) override;
    virtual bool mmio_store(reg_t addr, size_t len, const uint8_t* bytes) override;
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

    uint32_t get_phy_addr(uint32_t addr, access_type type);

    void write_reg(int i, uint32_t data);

    virtual int cosim_instr(const Inst& inst);

    const std::map<size_t, processor_t*>& get_harts() const override
    {
        return harts;
    }

    void dump_state(FILE* stream, uint32_t ppc) const;

    uint32_t get_pc() const
    {
        return processor->get_state()->pc;
    }

    void take_trap(bool interrupt, reg_t cause, reg_t epc, bool delegate);

    std::string disasm(uint32_t instr)
    {
        return processor->get_disassembler()->disassemble(instr);
    }

    void restore_from_top(TopWrapper& wrap, Inst& inst);
};
