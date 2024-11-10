#pragma once
#include <stdint.h>
#include <stddef.h>
#include "../Utils.hpp"

#include "Model.hpp"

#include "../model_headers.h"
#include "riscv/processor.h"
#include "../sc_stub.hpp"
#include "../slang/slang.hpp"


class BranchHistory : public Model
{
  public:
    uint64_t bhist = 0;
    bool historyEqual;
    uint64_t ReadBrHistory(uint8_t fetchID, uint8_t fetchOffs)
    {
#ifdef COSIM
        auto core = top->Top->soc->core;
        auto bpFile = core->ifetch->bp->bpFile->mem;

        BPBackup backup{sc_bv<BPBackup::_size>{(char*)bpFile[fetchID].data()}};

        if (backup.pred && backup.isRegularBranch && fetchOffs > backup.predOffs)
            return (backup.history << 1) | backup.predTaken;
        return backup.history;
#else
        return 0;
#endif
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
