#pragma once

#include "VTop.h"
#include <memory>

#ifdef TRACE
#include "verilated_vcd_c.h"
#endif

class TopWrapper
{
  public:
    std::unique_ptr<VTop> top = std::make_unique<VTop>();
#ifdef TRACE
    std::unique_ptr<VerilatedVcdC> tfp = std::make_unique<VerilatedVcdC>();
#endif
    uint64_t main_time = 0;

    void HalfCycle()
    {
        top->clk = !top->clk;
        top->eval();
#ifdef TRACE
        if (main_time > DEBUG_TIME)
            tfp->dump(main_time);
#endif
        main_time++;
    }

    void Reset()
    {
        // Reset
        top->rst = 1;
        for (size_t j = 0; j < 4; j++)
        {
            HalfCycle();
            top->rst = (j < 2);
        }
    }

    void save_model(std::string fileName)
    {
        VerilatedSave os;
        os.open(fileName.c_str());
        os << main_time; // user code must save the timestamp
        os << *top;
    }

    void restore_model(std::string fileName)
    {
        VerilatedRestore os;
        os.open(fileName.c_str());
        os >> main_time;
        os >> *top;
    }

    void Initial()
    {
#ifdef TRACE
        top->trace(tfp.get(), 99);
        tfp->open("Top_tb.vcd");
#endif
    }

    void Final()
    {
        top->final();
#ifdef TRACE
        tfp->flush();
        tfp->close();
        tfp.reset();
#endif
    }
};
