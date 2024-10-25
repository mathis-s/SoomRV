#pragma once
#include "Model.hpp"
#include <stdint.h>
#include <stddef.h>

class ReturnStack : public Model
{
  public:
    static const size_t RET_STACK_SIZE = 32;
    uint32_t returnStack[RET_STACK_SIZE] = {};
    int returnIdx;

    std::optional<uint32_t> get_expected_pred(uint32_t instSIM, uint32_t pc)
    {
        uint32_t nextPC = ((instSIM & 3) == 3) ? pc + 4 : pc + 2;
        if ((instSIM & 0b1111111111111111) == 0b1000000010000010)
            return returnStack[(returnIdx--)%RET_STACK_SIZE];
        if ((instSIM & 0b1111000001111111) == 0b1001000000000010)
            returnStack[(++returnIdx)%RET_STACK_SIZE] = nextPC;
        if ((instSIM & 0b1110000000000011) == 0b0010000000000001)
            returnStack[(++returnIdx)%RET_STACK_SIZE] = nextPC;

        if ((instSIM & 0b1111111) == 0b1101111)
        {
            int rd = (instSIM >> 7) & 31;
            if (rd == 1 || rd == 5)
                returnStack[(++returnIdx)%RET_STACK_SIZE] = nextPC;
        }

        if ((instSIM & 0b111'00000'1111111) == 0b000'00000'1100111)
        {
            int rd = (instSIM >> 7) & 31;
            int rs1 = (instSIM >> 15) & 31;
            if (((rd == 1 || rd == 5) && !(rs1 == 1 || rs1 == 5)) || ((rd == 1 || rd == 5) && rd == rs1))
                returnStack[(++returnIdx)%RET_STACK_SIZE] = nextPC;
            if (!(rd == 1 || rd == 5) && (rs1 == 1 || rs1 == 5))
                return returnStack[(returnIdx--)%RET_STACK_SIZE];
        }
        return std::optional<uint32_t>{};
    }

    bool check_return_stack(uint32_t instSIM, uint32_t pc, uint32_t predTarget)
    {
        auto expected = get_expected_pred(instSIM, pc);
        if (expected && expected != predTarget)
        {
            fprintf(stderr, "invalid return address; expected %.8x, actual %.8x\n", expected.value(), predTarget);
            return false;
        }
        return true;
    }

    bool PreInst(const Inst& inst)
    {
        return check_return_stack(inst.inst, processor->get_state()->pc, inst.predTarget);
    }

    void Save(FILE* f)
    {
        if (fwrite(returnStack, sizeof(returnStack), 1, f) != 1) abort();
        if (fwrite(&returnIdx, sizeof(returnIdx), 1, f) != 1) abort();
    }

    void Restore(FILE* f)
    {
        if (fread(returnStack, sizeof(returnStack), 1, f) != 1) abort();
        if (fread(&returnIdx, sizeof(returnIdx), 1, f) != 1) abort();
    }

    ReturnStack(VTop* top, processor_t* processor) : Model(top, processor) {}
};
