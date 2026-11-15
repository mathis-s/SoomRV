#pragma once

#include "Debug.hpp"
#include "hw/SimTop.h"
#include <memory>
#include <utility>

#ifdef TRACE
#include "verilated_fst_c.h"
#endif

template <typename Top> class TopWrapper {
public:
  TopWrapper(dyno::Context &ctx, const char* wavesFile = nullptr)
      : top(std::make_unique<SimulationTop<Top>>(ctx, wavesFile)),
        core(&top->top->soc->core), csr(&core->intPortsGen_0_.genblk7.csr) {}
  std::unique_ptr<SimulationTop<Top>> top;
#ifdef TRACE
  std::unique_ptr<VerilatedFstC> tfp = std::make_unique<VerilatedFstC>();
#endif
  uint64_t main_time = 0;
  using core_t = decltype(std::declval<Top>().soc.core);
  using csr_t =
      decltype(std::declval<Top>().soc.core.intPortsGen_0_.genblk7.csr);
  core_t *core;
  csr_t *csr;

  void HalfCycle() {
    top->top->clk = !top->top->clk;
    top->eval();
#ifdef TRACE
    if (main_time > DEBUG_TIME)
      tfp->dump(main_time);
#endif
    top->forwardTime(1);
    main_time++;
  }

  void Reset() {
    // Reset
    top->top->rst = 1;
    for (size_t j = 0; j < 4; j++) {
      HalfCycle();
      top->top->rst = (j < 2);
    }
  }

  void save_model(std::string fileName) {
#ifdef SAVEABLE
    VerilatedSave os;
    os.open(fileName.c_str());
    os << main_time; // user code must save the timestamp
    os << *top;
#endif
  }

  void restore_model(std::string fileName) {
#ifdef SAVEABLE
    VerilatedRestore os;
    os.open(fileName.c_str());
    os >> main_time;
    os >> *top;
#else
    abort();
#endif
  }

  void Initial() {
#ifdef TRACE
    top->trace(tfp.get(), 99);
    tfp->open("Top_tb.fst");
#endif
  }

  void Final() {
    // top->final();
#ifdef TRACE
    tfp->flush();
    tfp->close();
    tfp.reset();
#endif
#ifdef COVERAGE
    Verilated::threadContextp()->coveragep()->write("coverage.dat");
#endif
  }
};

template <typename... T> class TopWrappers {
  std::tuple<T *...> refs;

public:
  void HalfCycle() {
    std::apply([](T *...refs) { (refs->HalfCycle(), ...); }, refs);
  }
  void Reset() {
    std::apply([](T *...refs) { (refs->Reset(), ...); }, refs);
  }
  void Initial() {
    std::apply([](T *...refs) { (refs->Initial(), ...); }, refs);
  }
  void Final() {
    std::apply([](T *...refs) { (refs->Final(), ...); }, refs);
  }

  void with_core(auto &&func) {
    std::apply([&](T *...refs) { (func(refs->core), ...); }, refs);
  }
  void with_csr(auto &&func) {
    std::apply([&](T *...refs) { (func(refs->core), ...); }, refs);
  }
  void with_top(auto &&func) {
    std::apply([&](T *...refs) { (func(refs->top->top.get()), ...); }, refs);
  }

  TopWrappers(T *...ts) : refs(ts...) {}
};
