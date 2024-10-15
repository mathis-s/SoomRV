#pragma once
#include <cstdlib>
#include <memory>
#include <stddef.h>
#include <stdint.h>
#include <vector>

struct Instr
{
    uint32_t data;
    int get_size() const
    {
        return (data & 3) == 3 ? 32 : 16;
    }
};

struct TestCase
{
    std::vector<Instr> prog;
    bool unpack(uint8_t* dst, size_t max_size) const
    {
        uint8_t* end = dst + max_size;
        for (auto& instr : prog)
        {
            switch (instr.get_size())
            {
                case 32:
                    if ((end - dst) < 4)
                        return false;
                    dst[3] = (instr.data >> 24) & 0xff;
                    dst[2] = (instr.data >> 16) & 0xff;
                case 16:
                    if ((end - dst) < 2)
                        return false;
                    dst[1] = (instr.data >> 8) & 0xff;
                    dst[0] = (instr.data >> 0) & 0xff;
                default: break;
            }

            dst += instr.get_size() / 8;
        }
        return true;
    }
    bool load(const uint8_t* src, size_t size)
    {
        prog.clear();
        size_t i = 0;
        while (2 * i < size - 1)
        {
            Instr instr;
            instr.data = ((uint16_t*)src)[i++];
            if (instr.get_size() == 32)
            {
                if (2 * i >= size - 1)
                    return false;
                instr.data = instr.data | (((uint16_t*)src)[i++]) << 16;
            }
            prog.push_back(instr);
        }
        return true;
    }
};

class Tactic
{
  public:
    virtual bool mutate(TestCase& test_case) = 0;
};

class RandomBitflipTactic : public Tactic
{
  public:
    virtual bool mutate(TestCase& test_case)
    {
        size_t idx = rand() % test_case.prog.size();
        auto& instr = test_case.prog[idx];
        size_t bit = rand() % instr.get_size();
        instr.data ^= (1UL << bit);
        return true;
    }
};

// strategy is a collection of tactics, selects tactic(s) to execute
class Strategy : public Tactic
{
  public:
    std::vector<std::unique_ptr<Tactic>> tactics;
    Strategy(std::vector<std::unique_ptr<Tactic>> tactics) : tactics(std::move(tactics))
    {
    }
    virtual bool mutate(TestCase& test_case)
    {
        auto& tactic = *tactics[rand() % tactics.size()];
        return tactic.mutate(test_case);
    }
};

enum class RunResultFlags
{
    FINISHED,
    TIMEOUT,
    ERROR
};

struct RunResults
{
    float coverage;
    RunResultFlags flags;
};

class Fuzzer
{
  public:
    std::unique_ptr<Tactic> strategy;

    virtual RunResults run(TestCase const& test_case) = 0;
    virtual void report(TestCase const& test_case, RunResults const& results) = 0;

    void fuzz(size_t iters, uint seed, TestCase test_case)
    {
        srand(seed);
        for (size_t i = 0; i < iters; i++)
        {
            auto results = run(test_case);
            switch (results.flags)
            {
                case RunResultFlags::ERROR: report(test_case, results);
                case RunResultFlags::TIMEOUT:
                case RunResultFlags::FINISHED: break;
            }
            strategy->mutate(test_case);
        }
    }
};
