#pragma once
#include "model_headers.h"
#include "sc_stub.hpp"
#include "slang/slang.hpp"
#include <stdint.h>

class Registers
{
  public:
    VTop* top;
    std::array<uint16_t, 32> regTagOverride;

    uint32_t ReadRegister(uint32_t rid)
    {
        auto core = top->Top->soc->core;
        constexpr size_t TagImmSize = R_UOp::tagA_w - 1;
        constexpr size_t TagSelBit = 1 << TagImmSize;
        constexpr size_t TagImmMask = (1 << TagImmSize) - 1;

        uint16_t comTag = regTagOverride[rid];
        if (comTag == 0xffff)
            comTag = (core->rn->rt->comTag[rid]);

        if (comTag & TagSelBit)
            return ((int32_t)(comTag & TagImmMask) << (32 - TagImmSize)) >> (32 - TagImmSize);
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
            auto free = sc_bv<sizeof(core->rn->tb->free)*8>{(char*)&core->rn->tb->free};
            auto freeCom = sc_bv<sizeof(core->rn->tb->free)*8>{(char*)&core->rn->tb->freeCom};

            if (free.get_bit(i) && freeCom.get_bit(i))
            {
                auto tagAvail = sc_bv<sizeof(core->rn->rt->tagAvail)*8>{(char*)&core->rn->rt->tagAvail};

                free.set_bit(i, 0);
                freeCom.set_bit(i, 0);
                tagAvail.set_bit(i, 1);

                memcpy((void*)&core->rn->tb->free, free.data.data(), sizeof(core->rn->tb->free));
                memcpy((void*)&core->rn->tb->freeCom, freeCom.data.data(), sizeof(core->rn->tb->freeCom));
                memcpy((void*)&core->rn->rt->tagAvail, tagAvail.data.data(), sizeof(core->rn->rt->tagAvail));

                core->rn->rt->comTag[rid] = (i);
                core->rn->rt->specTag[rid] = (i);
                core->rf->mem[i] = val;
                break;
            }
            i++;
            if (i == sizeof(core->rn->tb->free) * 8)
                abort();
        }
    }

    void Cycle()
    {
        memset(regTagOverride.data(), 0xFF, sizeof(regTagOverride));
    }

    Registers(VTop* top) : top(top) { Cycle(); }
};
