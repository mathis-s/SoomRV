#pragma once
#include "model_headers.h"
#include <stdint.h>

class Registers
{
  public:
    VTop* top;
    std::array<uint8_t, 32> regTagOverride;

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

    void WriteRegister(uint32_t rid, uint32_t val)
    {
        // ONLY use this for initialization!
        // If there is a previously allocated
        // physical register, it is not freed.
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

    void Cycle()
    {
        memset(regTagOverride.data(), 0xFF, sizeof(regTagOverride));
    }

    Registers(VTop* top) : top(top) { Cycle(); }
};
