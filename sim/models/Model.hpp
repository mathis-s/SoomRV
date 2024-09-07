#pragma once
#include "VTop.h"
#include "../Inst.hpp"
#include "riscv/processor.h"

class Model
{
  public:
    VTop* top;
    processor_t* processor;

    virtual bool PreInst(Inst const&) { return true; }
    virtual bool PostInst(Inst const&) { return true; }
    Model(VTop* top, processor_t* processor) : top(top), processor(processor) {}
};
