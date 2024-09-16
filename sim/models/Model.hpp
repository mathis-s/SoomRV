#pragma once
#include "../model_headers.h"
#include "../Inst.hpp"
#include "riscv/processor.h"

class Model
{
  public:
    VTop* top;
    processor_t* processor;

    virtual bool PreInst(Inst const&) { return true; }
    virtual bool PostInst(Inst const&) { return true; }
    virtual void Save(FILE*) { }
    virtual void Restore(FILE*) { }
    Model(VTop* top, processor_t* processor) : top(top), processor(processor) {}
    virtual ~Model() {}
};
