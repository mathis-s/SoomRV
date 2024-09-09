#pragma once
#include <stdint.h>
#include <stddef.h>
#include "../Utils.hpp"

#include "Model.hpp"

#include "VTop.h"
#include "VTop_SoC.h"
#include "VTop_Top.h"
#include "VTop_Core.h"
#include "VTop_IFetch.h"
#include "VTop_BranchPredictor__N3.h"
#include "VTop_RegFile__W50_S20_N1_NB1.h"
#include "riscv/processor.h"


class BranchHistory : public Model
{
  public:
    uint64_t bhist = 0;
    bool historyEqual;

    uint64_t ReadBrHistory(uint8_t fetchID, uint8_t fetchOffs)
    {
        auto core = top->Top->soc->core;
        auto bpFile = core->ifetch->bp->bpFile->mem;
        bool pred = ExtractField(bpFile[fetchID], 0, 1);
        uint8_t predOffs = ExtractField(bpFile[fetchID], 1, 3);
        bool predTaken = ExtractField(bpFile[fetchID], 4, 1);
        bool isRegularBranch = ExtractField(bpFile[fetchID], 5, 1);
        uint64_t history = ExtractField(bpFile[fetchID], 11, 32) |
            ((uint64_t)ExtractField(bpFile[fetchID], 11+32, 32) << 32);

        if (pred && isRegularBranch && fetchOffs > predOffs)
            return (history << 1) | predTaken;
        return history;
    }

    bool compare_history (const Inst& i)
    {
        auto fetchOffset = (((i.pc & 15) >> 1) + (((i.inst & 3) == 3) ? 1 : 0)) & 7;
        auto coreHist = ReadBrHistory(i.fetchID, fetchOffset);
        return coreHist == bhist;
    }

    std::pair<bool, bool> is_branch_taken (uint32_t instSIM)
    {
        bool taken = false;
        bool branch = false;
        auto X = processor->get_state()->XPR;
        if ((instSIM & 0b1110000000000011) == 0b1100000000000001)
        {
            branch = true;
            taken = (uint32_t)(X[((instSIM >> 7) & 7) + 8]) == 0;
        }
        if ((instSIM & 0b1110000000000011) == 0b1110000000000001)
        {
            branch = true;
            taken = (uint32_t)(X[((instSIM >> 7) & 7) + 8]) != 0;
        }
        if ((instSIM & 0b1111111) == 0b1100011)
        {
            uint32_t rs1 = X[(instSIM >> 15) & 31];
            uint32_t rs2 = X[(instSIM >> 20) & 31];

            switch ((instSIM >> 12) & 7)
            {
                case 0: {branch = true; taken = rs1 == rs2;  break;}
                case 1: {branch = true; taken = rs1 != rs2;  break;}
                case 4: {branch = true; taken = (int32_t)rs1 < (int32_t)rs2;  break;}
                case 5: {branch = true; taken = (int32_t)rs1 >= (int32_t)rs2;  break;}
                case 6: {branch = true; taken = rs1 < rs2;  break;}
                case 7: {branch = true; taken = rs1 >= rs2;  break;}
                default: ;
            }
        }
        return std::make_pair(branch, taken);
    }

    bool PreInst(const Inst& inst)
    {
        historyEqual = compare_history(inst);
        if (!historyEqual)
        {
            fprintf(stderr, "branch history not equal\n");
            return false;
        }
        return true;
    }

    bool PostInst(const Inst& inst)
    {
        auto [branch, taken] = is_branch_taken(inst.inst);
        if (branch && historyEqual)
        {
            bhist = (bhist << 1) | (taken ? 1 : 0);
            if (processor->debug)
                PrintBin(stderr, bhist);
        }
        return true;
    }

    void Save(FILE* f)
    {
        if (fwrite(&bhist, sizeof(bhist), 1, f) != 1) abort();
    }

    void Restore(FILE* f)
    {
        if (fread(&bhist, sizeof(bhist), 1, f) != 1) abort();
    }

    BranchHistory(VTop* top, processor_t* processor) : Model(top, processor) {}
};
