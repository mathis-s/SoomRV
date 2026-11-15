#pragma once
#include "../model_headers.h"
#include "../Inst.hpp"
#include "TopWrapper.hpp"
#include "riscv/processor.h"

class Model
{
  public:
    ModInst____GTop* top;
    processor_t* processor;

    virtual bool PreInst(Inst const&) { return true; }
    virtual bool PostInst(Inst const&) { return true; }
    virtual void Save(FILE*) { }
    virtual void Restore(FILE*) { }
    Model(ModInst____GTop* top, processor_t* processor) : top(top), processor(processor) {}
    virtual ~Model() {}
};
