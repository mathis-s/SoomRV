#include "TopWrapper.hpp"
#include "VTop_IFetchPipeline.h"
#include "VTop_ROB.h"
#include "VTop_ReturnStack.h"
#include "models/BranchHistory.hpp"
#include "models/ReturnStack.hpp"
#include <memory>
#define TOOLCHAIN "riscv32-unknown-linux-gnu-"

#include "VTop.h"
#include "VTop_CSR.h"
#include "VTop_Core.h"
#include "VTop_ExternalAXISim.h"
#include "VTop_IFetch.h"
#include "VTop_SoC.h"
#include "VTop_Top.h"
#include <cstdio>
#include <unistd.h>
#include <array>
#include <asm-generic/ioctls.h>
#include <cstring>
#include <getopt.h>
#include <sys/ioctl.h>

#include "Inst.hpp"
#include "Simif.hpp"
#include "Registers.hpp"
#include "Utils.hpp"

struct
{
    uint32_t lastComSqN;
    uint32_t id = 0;
    uint32_t nextSqN;

    uint64_t committed = 0;

    Inst pd[4];
    Inst de[4];
    Inst insts[128];
    FetchPacket fetches[32];
    FetchPacket fetch0;
    FetchPacket fetch1;
} state;
int curCycInstRet = 0;
std::vector<Store> inFlightStores;

std::unique_ptr<TopWrapper> wrap = std::make_unique<TopWrapper>();
std::vector<uint32_t> pram(1 << 26);

double sc_time_stamp()
{
    return wrap->main_time;
}

Registers registers(wrap->top.get());
SpikeSimif simif(pram, registers, wrap->main_time);

void WriteRegister(uint32_t rid, uint32_t val)
{
    #ifdef COSIM
    simif.write_reg(rid, val);
    #endif
    registers.WriteRegister(rid, val);
}

static bool kbhit()
{
    int buffered;
    ioctl(0, FIONREAD, &buffered);
    if (buffered == 0 && write(fileno(stdin), 0, 0) != 0)
        return 0;
    return buffered != 0;
}

static void HandleInput()
{
    auto emem = wrap->top->Top->extMem;
    if (!emem->inputAvail && kbhit())
    {
        emem->inputAvail = 1;
        emem->inputByte = getchar();
    }
}

void DumpState(FILE* stream, Inst inst)
{
    auto core = wrap->top->Top->soc->core;
    fprintf(stream, "time=%lu\n", wrap->main_time);
    fprintf(stream, "ir=%.8lx ppc=%.8x inst=%.8x sqn=%.2x\n", core->csr->minstret, inst.pc, inst.inst, state.lastComSqN);
    for (size_t j = 0; j < 4; j++)
    {
        for (size_t k = 0; k < 8; k++)
            fprintf(stream, "x%.2zu=%.8x ", j * 8 + k, registers.ReadRegister(j * 8 + k));
        fprintf(stream, "\n");
    }
    fprintf(stream, "\n");
}

FILE* konataFile;

void Exit(int code)
{
#ifdef KONATA
    fflush(konataFile);
#endif
    wrap->Final();
    fflush(stdout);
    fflush(stderr);
    exit(code);
}

void LogFlush(Inst& inst);

void LogCommit(Inst& inst)
{
#ifdef COSIM
    if (simif.doRestore)
        simif.restore_from_top(wrap->top.get(), inst);
#endif
    if (inst.interrupt == Inst::IR_SQUASH)
    {
#ifdef COSIM
        // printf("INTERRUPT %.8x\n", inst.pc);
        simif.take_trap(true, inst.interruptCause, inst.pc, inst.interruptDelegate);
#endif
#ifdef KONATA
        // This is a fake interrupt instruction,
        // show it as flushed in Konata
        LogFlush(inst);
#endif
    }
    else
    {
        if (inst.incMinstret)
            curCycInstRet++;

        if (inst.rd != 0 && inst.flags < 6)
            registers.regTagOverride[inst.rd] = inst.tag;

#ifdef COSIM
        uint32_t startPC = simif.get_pc();
        if (int err = simif.cosim_instr(inst))
        {
            fprintf(stdout, "ERROR %u (fetchID=%.2x, sqN=%.2x)\n", -err, inst.fetchID, inst.sqn);
            DumpState(stdout, inst);

            fprintf(stdout, "\nSHOULD BE\n");
            simif.dump_state(stdout, startPC);
#ifdef KONATA
            fprintf(konataFile, "L\t%u\t%u\t COSIM ERROR \n", inst.id, 0);
            fflush(konataFile);
#endif
            Exit(-1);
        }
#endif

#ifdef KONATA
        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "COM");
        fprintf(konataFile, "R\t%u\t%u\t0\n", inst.id, inst.sqn);
#else
            // DumpState(inst.pc);
#endif
    }
}

static uint64_t hpm4offset = 0;
void LogPredec(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "I\t%u\t%u\t%u\n", inst.id, inst.fetchID, 0);
    // For return stack debugging
    /*fprintf(konataFile, "L\t%u\t%u\t (%.5ld) %d %.3x %.3x %.3x %.3x| \n", inst.id, 0, main_time, inst.retIdx,
        state.fetches[inst.fetchID].returnAddr[0] * 2 & 0xfff,
        state.fetches[inst.fetchID].returnAddr[1] * 2 & 0xfff,
        state.fetches[inst.fetchID].returnAddr[2] * 2 & 0xfff,
        state.fetches[inst.fetchID].returnAddr[3] * 2 & 0xfff);*/
    if (wrap->main_time > DEBUG_TIME)
    {
        fprintf(konataFile, "L\t%u\t%u\t[%.5lu]%.8x (%.8x): %s\n", inst.id, 0, wrap->main_time, inst.pc, inst.inst,
                simif.disasm(inst.inst).c_str());

        fprintf(konataFile, "C\t-%lu\n",
            (wrap->main_time-state.fetches[inst.fetchID].fetchTime)/2);
        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "IF");
        fprintf(konataFile, "C\t%lu\n",
            (state.fetches[inst.fetchID].pdTime - state.fetches[inst.fetchID].fetchTime)/2);

        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "PD");
        fprintf(konataFile, "C\t%lu\n",
            (wrap->main_time - state.fetches[inst.fetchID].pdTime)/2);


        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "DEC");
    }
#endif
}

void LogDecode(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "RN");
#endif
}

void LogFlush(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "R\t%u\t0\t1\n", inst.id);
#endif
}

void LogRename(Inst& inst)
{
#ifdef KONATA
    if (wrap->main_time > DEBUG_TIME)
    {
        if (inst.fu == 8 || inst.fu == 11)
            fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "WFC");
        else
            fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "IS");
    }
#endif
}

void LogResult(Inst& inst)
{
#ifdef KONATA
    if (wrap->main_time > DEBUG_TIME)
    {
        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "WFC");
        if (!(inst.tag & 0x40))
            fprintf(konataFile, "L\t%u\t%u\tres=%.8x\n", inst.id, 1, inst.result);
    }
#endif
}

void LogExec(Inst& inst)
{
#ifdef KONATA
    if (wrap->main_time > DEBUG_TIME)
    {
        fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "EX");
        fprintf(konataFile, "L\t%u\t%u\topA=%.8x \n", inst.id, 1, inst.srcA);
        fprintf(konataFile, "L\t%u\t%u\topB=%.8x \n", inst.id, 1, inst.srcB);
        fprintf(konataFile, "L\t%u\t%u\timm=%.8x \n", inst.id, 1, inst.imm);
    }
#endif
}

void LogIssue(Inst& inst)
{
#ifdef KONATA
    fprintf(konataFile, "S\t%u\t0\t%s\n", inst.id, "LD");
#endif
}

void LogCycle()
{
    curCycInstRet = 0;
    registers.Cycle();
#ifdef KONATA
    fprintf(konataFile, "C\t1\n");
#endif
}

uint32_t mostRecentPC;
void LogInstructions()
{
#ifdef COSIM
    //CheckStoreConsistency2();
#endif

    auto core = wrap->top->Top->soc->core;

    bool brTaken = core->branch[0] & 1;
    int brSqN = ExtractField(core->branch, 1 + 5 + 1 + 7 + 7, 8);

    // Issue
    for (size_t i = 0; i < 4; i++)
    {
        if (!core->stall[i] && core->IS_uop[i][0] & 1)
        {
            uint32_t sqn = ExtractField<4>(core->IS_uop[i], 116 - (32 + 12 + 1 + 7 + 1 + 7 + 1 + 7 + 7), 7);
            LogIssue(state.insts[sqn]);
        }
    }

    // Execute
    for (size_t i = 0; i < 4; i++)
    {
        // EX valid
        if ((core->LD_uop[i][0] & 1) && !core->stall[i])
        {
            uint32_t sqn = ExtractField(core->LD_uop[i], 1 + 1 + 4 + 7 + 7 + 1 + 5, 7);
            state.insts[sqn].srcA = ExtractField(core->LD_uop[i], 183 - 32, 32);
            state.insts[sqn].srcB = ExtractField(core->LD_uop[i], 183 - 32 - 32, 32);
            state.insts[sqn].imm = ExtractField(core->LD_uop[i], 183 - 32 - 32 - 32 - 3 - 3 - 32, 32);
            LogExec(state.insts[sqn]);
        }
    }

    // Result
    for (size_t i = 0; i < 6; i++)
    {
        uint32_t sqn = (core->wbUOp[i] >> 6) & 127;
        // WB valid
        if ((core->wbUOp[i] & 1) && !(core->wbUOp[i] & 2))
        {
            uint32_t result = (core->wbUOp[i] >> (6 + 7 + 7)) & 0xffff'ffff;
            state.insts[sqn].result = result;
            state.insts[sqn].flags = (core->wbUOp[i] >> 2) & 0xF;

            // FP ops use a different flag encoding. These are not traps, so ignore them.
            if ((state.insts[sqn].fu == 5 || state.insts[sqn].fu == 6 || state.insts[sqn].fu == 7) &&
                state.insts[sqn].flags >= 8 && state.insts[sqn].flags <= 13)
                state.insts[sqn].flags = 0;

            LogResult(state.insts[sqn]);
        }
    }

    // Commit
    {
        uint32_t curComSqN = core->ROB_curSqN;
        for (size_t i = 0; i < 4; i++)
        {
            if ((core->comUOps[i] & 1) && !core->mispredFlush)
            {
                int sqn = (core->comUOps[i] >> 4) & 127;

                // assert(state.insts[sqn].valid);
                // assert(state.insts[sqn].sqn == (uint32_t)sqn);

                bool isInterrupt = false;
                bool isXRETinterrupt = false;
                if (core->ROB_trapUOp & 1)
                {
                    int trapSQN = (core->ROB_trapUOp >> (15 + 14)) & 127;
                    int flags = (core->ROB_trapUOp >> (29 + 14)) & 15;
                    int rd = (core->ROB_trapUOp >> 10) & 31;
                    isInterrupt = (trapSQN == sqn) && flags == 7 && rd == 16;
                    isXRETinterrupt =
                        (trapSQN == sqn) && ((flags == 5 || flags == 14) && core->rob->IN_interruptPending);
                }
                state.insts[sqn].interrupt = isInterrupt ? Inst::IR_SQUASH : Inst::IR_NONE;
                if (isXRETinterrupt)
                    state.insts[sqn].interrupt = Inst::IR_KEEP;
                state.insts[sqn].interruptCause = (core->CSR_trapControl[0] >> 1) & 15;
                state.insts[sqn].interruptDelegate = core->CSR_trapControl[0] & 1;
                state.insts[sqn].incMinstret = (core->ROB_perfcInfo & (1 << i));

                state.lastComSqN = curComSqN;
                LogCommit(state.insts[sqn]);
                mostRecentPC = state.insts[sqn].pc;
                state.insts[sqn].valid = false;
            }
        }
    }

    // Branch Taken
    if (brTaken)
    {
        uint32_t i = (brSqN + 1) & 127;
        while (i != state.nextSqN)
        {
            if (state.insts[i].valid)
                LogFlush(state.insts[i]);
            i = (i + 1) & 127;
        }

        for (size_t i = 0; i < 4; i++)
        {
            if (state.de[i].valid)
                LogFlush(state.de[i]);
            if (state.pd[i].valid)
                LogFlush(state.pd[i]);
        }
    }
    else
    {
        // Rename
        for (size_t i = 0; i < 4; i++)
            if (core->RN_uop[i][0] & 1)
            {
                int sqn = ExtractField<4>(core->RN_uop[i], 46 + 6, 7);
                int fu = ExtractField<4>(core->RN_uop[i], 2 + 6, 4);
                uint8_t tagDst = ExtractField<4>(core->RN_uop[i], 46 + 6 - 7, 7);

                state.insts[sqn].valid = 1;
                state.insts[sqn] = state.de[i];
                state.insts[sqn].sqn = sqn;
                state.insts[sqn].fu = fu;
                state.insts[sqn].tag = tagDst;
                state.nextSqN = (sqn + 1) & 127;

                LogRename(state.insts[sqn]);
            }

        // Decode
        if (core->frontendEn && !core->RN_stall)
        {
            for (size_t i = 0; i < 4; i++)
                if (wrap->top->Top->soc->core->DE_uop[i].at(0) & (1 << 0))
                {
                    state.de[i] = state.pd[i];
                    state.de[i].rd = ExtractField(core->DE_uop[i], 80 - 32 - 12 - 5 - 5 - 1 - 5, 5);
                    LogDecode(state.de[i]);
                }
                else
                {
                    if (state.pd[i].valid)
                        LogFlush(state.pd[i]);
                    state.de[i].valid = false;
                }
        }
        // Predec
        if (!core->RN_stall && core->frontendEn)
        {
            for (size_t i = 0; i < 4; i++)
                if ((core->PD_instrs[i].at(0) & 1))
                {
                    state.pd[i].valid = true;
                    state.pd[i].flags = 0;
                    state.pd[i].id = state.id++;
                    state.pd[i].pc = ExtractField(wrap->top->Top->soc->core->PD_instrs[i], 124 - 12 - 31 - 32, 31) << 1;
                    state.pd[i].inst = ExtractField(wrap->top->Top->soc->core->PD_instrs[i], 124 - 12 - 32, 32);
                    state.pd[i].fetchID = ExtractField(wrap->top->Top->soc->core->PD_instrs[i], 4, 5);
                    state.pd[i].predTarget = ExtractField(wrap->top->Top->soc->core->PD_instrs[i], 4+5+3, 31) << 1;
                    //state.pd[i].retIdx =
                    //    ExtractField(top->Top->soc->core->PD_instrs[i], 120 - 32 - 31 - 31 - 1 - 12 - 2, 2);
                    if ((state.pd[i].inst & 3) != 3)
                        state.pd[i].inst &= 0xffff;

                    LogPredec(state.pd[i]);
                }
                else
                    state.pd[i].valid = false;
        }

        if (core->ifetch->ifp->fetch0[0] & 1)
        {
            for (int i = 0; i < 4; i++)
                state.fetches[core->ifetch->ifp->fetchID].returnAddr[i] = core->ifetch->bp->retStack->rstack[i];

            state.fetches[core->ifetch->ifp->fetchID].fetchTime = wrap->main_time;
        }

        if ((core->IF_instrs[0] & 1))
        {
            int fetchID = ExtractField(core->ifetch->ifp->packetRePred, 1 + 128 + 31 + 1 + 3 + 3 + 3 + 2, 5);
            state.fetches[fetchID].pdTime = wrap->main_time + 2;
        }
    }
    LogCycle();
}

struct Args
{
    std::string progFile;
    std::string deviceTreeFile;
    std::string backupFile;
    std::string memDumpFile;
    bool restoreSave = 0;
    uint32_t deviceTreeAddr = 0;
    bool logPerformance = 0;
};

static void ParseArgs(int argc, char** argv, Args& args)
{
    static struct option long_options[] = {
        {"device-tree", required_argument, 0, 'd'},
        {"backup-file", required_argument, 0, 'b'},
        {"dump-mem", required_argument, 0, 'o'},
        {"perfc", no_argument, 0, 'p'},
    };
    int idx;
    int c;
    while ((c = getopt_long(argc, argv, "d:b:o:p", long_options, &idx)) != -1)
    {
        switch (c)
        {
            case 'd': args.deviceTreeFile = std::string(optarg); break;
            case 'b': args.backupFile = std::string(optarg); break;
            case 'o': args.memDumpFile = std::string(optarg); break;
            case 'p': args.logPerformance = 1; break;
            default: break;
        }
    }

    if (optind < argc && argv[optind][0] != '+')
        args.progFile = std::string(argv[optind]);

    if (args.progFile.empty())
    {
        fprintf(stderr,
                "usage: %s [options] <ELF BINARY>.elf|<BACKUP FILE>.backup|<ASSEMBLY FILE>\n"
                "Options:\n"
                "\t"
                "--device-tree, -d: Load device tree binary, store address in a1 at boot.\n"
                "\t"
                "--backup-file, -b: Periodically save state in specified file. Reload by specifying backup file as "
                "program.\n"
                "\t"
                "--dump-mem, -o:    Dump memory into output file after loading binary.\n"
                "\t"
                "--perfc, p:        Periodically dump performance counter stats.\n",
                argv[0]);
        // clang-format on
        exit(-1);
    }
}

void Initialize(int argc, char** argv, Args& args)
{
    ParseArgs(argc, argv, args);

    if (args.progFile.find(".backup", args.progFile.size() - 7) != std::string::npos)
        args.restoreSave = true;
    else if (args.progFile.find(".elf", args.progFile.size() - 4) == std::string::npos &&
             args.progFile.find(".out", args.progFile.size() - 4) == std::string::npos)
    {
        if (system((std::string(TOOLCHAIN
                                "as -mabi=ilp32 -march=rv32imac_zicsr_zfinx_zba_zbb_zicbom_zifencei -o temp.o ") +
                    args.progFile)
                       .c_str()) != 0)
            abort();
        if (system(TOOLCHAIN "ld --no-warn-rwx-segments --no-eh-frame-hdr -Tlinker.ld test_programs/entry.o temp.o") != 0)
            abort();
        args.progFile = "a.out";
    }

    if (!args.restoreSave)
    {
        if (system(std::string(TOOLCHAIN "objcopy -I elf32-little -j .text -O binary " + args.progFile + " text.bin")
                       .c_str()) != 0)
            abort();
        if (system(std::string(TOOLCHAIN "objcopy -I elf32-little -j .data -O binary " + args.progFile + " data.bin")
                       .c_str()) != 0)
            abort();

        size_t numProgBytes = 0;
        {
            uint8_t* pramBytes = (uint8_t*)pram.data();

            FILE* f = fopen("text.bin", "rb");
            if (!f)
                abort();
            numProgBytes = fread(pramBytes, sizeof(uint8_t), pram.size() * sizeof(uint32_t), f);
            fclose(f);

            if (numProgBytes & 3)
                numProgBytes = (numProgBytes & ~3) + 4;

            f = fopen("data.bin", "rb");
            if (!f)
                abort();
            numProgBytes += fread(&pramBytes[numProgBytes], sizeof(uint8_t), pram.size() * sizeof(uint32_t) - numProgBytes, f);
            fclose(f);
        }

        if (!args.memDumpFile.empty())
        {
            FILE* f = fopen(args.memDumpFile.c_str(), "w");
            fwrite(&pram[0], sizeof(uint32_t), numProgBytes, f);
            fclose(f);
        }

        // Device Tree
        args.deviceTreeAddr = 0;
        if (!args.deviceTreeFile.empty())
        {
            args.deviceTreeAddr = 0x80000000 + 0x4000000 - 1024 * 1024;
            FILE* dtbFile = fopen(args.deviceTreeFile.c_str(), "rb");
            if (!dtbFile)
                abort();
            fread((char*)pram.data() + args.deviceTreeAddr - 0x80000000, sizeof(uint8_t),
                  (pram.size() * sizeof(uint32_t)) - (args.deviceTreeAddr - 0x80000000), dtbFile);
            fclose(dtbFile);
        }
    }
}

void LogPerf(VTop_Core* core)
{
    std::array<uint64_t, 16> counters = {
        core->csr->mcycle,       core->csr->minstret,     core->csr->mhpmcounter[3],
        core->csr->mhpmcounter[4], core->csr->mhpmcounter[5],

        core->csr->mhpmcounter[6], core->csr->mhpmcounter[7],
        core->csr->mhpmcounter[8], core->csr->mhpmcounter[9],
        core->csr->mhpmcounter[10], core->csr->mhpmcounter[11],

        core->csr->mhpmcounter[12], core->csr->mhpmcounter[13],
        core->csr->mhpmcounter[14], core->csr->mhpmcounter[15],
        core->csr->mhpmcounter[16],

    };
    static std::array<uint64_t, 16> lastCounters;

    std::array<uint64_t, 16> current;
    for (size_t i = 0; i < counters.size(); i++)
        current[i] = counters[i] - lastCounters[i];

    double ipc = (double)current[1] / current[0];
    double mpki = (double)current[4] / (current[1] / 1000.0);
    double bmrate = ((double)current[3] / current[2]) * 100.0;

    fprintf(stderr, "cycles:             %lu\n", current[0]);
    fprintf(stderr, "instret:            %lu # %f IPC \n", current[1], ipc);
    fprintf(stderr, "mispredicts:        %lu # %f MPKI \n", current[4], mpki);
    fprintf(stderr, "branch mispredicts: %lu # %f%%\n", current[3], bmrate);
    fprintf(stderr, "branches:           %lu\n", current[2]);
    fprintf(stderr, "frontend stalled:   %lu # %f%%\n", current[12-1], 100.*current[12-1]/(4*current[0]));
    fprintf(stderr, "backend stalled:    %lu # %f%%\n", current[13-1], 100.*current[13-1]/(4*current[0]));
    fprintf(stderr, "store stalled:      %lu # %f%%\n", current[14-1], 100.*current[14-1]/(4*current[0]));
    fprintf(stderr, "load stalled:       %lu # %f%%\n", current[15-1], 100.*current[15-1]/(4*current[0]));
    fprintf(stderr, "ROB stalled:        %lu # %f%%\n", current[16-1], 100.*current[16-1]/(4*current[0]));

    fprintf(stderr,
        "%7lu # %2.0f ORD | %7lu # %2.0f BTK | %7lu # %2.0f BNT\n"
        "%7lu # %2.0f RET | %7lu # %2.0f IBR | %7lu # %2.0f MEM\n",
        current[5], 100.*current[5] / current[4],
        current[6], 100.*current[6] / current[4],
        current[7], 100.*current[7] / current[4],
        current[8], 100.*current[8] / current[4],
        current[9], 100.*current[9] / current[4],
        current[10], 100.*current[10] / current[4]);

    lastCounters = counters;
}

void Save(std::string fileName)
{
    wrap->save_model(fileName);
    #if defined(COSIM) | defined(KONATA)
        FILE* f = fopen((fileName + "_cosim").c_str(), "wb");
        if (fwrite(pram.data(), sizeof(uint32_t), pram.size(), f) != pram.size())
            abort();
        if (fwrite(&state, sizeof(state), 1, f) != 1)
            abort();

        for (auto* model : simif.models)
            model->Save(f);

        fclose(f);
    #endif
}

void Restore(std::string fileName)
{
    wrap->restore_model(fileName);
    #if defined(COSIM) | defined(KONATA)
        FILE* f = fopen((fileName + "_cosim").c_str(), "rb");
        if (fread(pram.data(), sizeof(uint32_t), pram.size(), f) != pram.size())
            abort();
        if (fread(&state, sizeof(state), 1, f) != 1)
            abort();

        for (auto* model : simif.models)
            model->Restore(f);

        fclose(f);

        long offset = state.insts[state.lastComSqN].id;
        for (size_t i = 0; i < 128; i++)
            state.insts[i].id -= offset;
        for (size_t i = 0; i < 4; i++)
        {
            state.pd[i].id -= offset;
            state.de[i].id -= offset;
        }
        state.id -= offset;
    #endif
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv); // Remember args
#ifdef TRACE
    Verilated::traceEverOn(true);
#endif

    Args args;
    Initialize(argc, argv, args);

    wrap->Initial();

    wrap->top->clk = 0;
    simif.models = {
        new ReturnStack(wrap->top.get(), simif.processor.get()),
        new BranchHistory(wrap->top.get(), simif.processor.get()),
    };

#ifdef KONATA
    konataFile = fopen("trace_konata.txt", "w");
    fprintf(konataFile, "Kanata	0004\n");
#endif

    auto core = wrap->top->Top->soc->core;

    if (args.restoreSave)
    {
        Restore(args.progFile);
        simif.doRestore = true;
    }
    else
    {
        for (size_t i = 0; i < (1 << 24); i++)
            wrap->top->Top->extMem->mem[i >> 2][i & 3] = pram[i];

        wrap->Reset();
    }

    if (args.deviceTreeAddr != 0)
        WriteRegister(11, args.deviceTreeAddr);

    const uint64_t perfInterval = 1024 * 1024 * 8;
    uint64_t lastMInstret = core->csr->minstret;
    uint64_t nextMinstretPerf = core->csr->minstret + perfInterval;

    // Run
    wrap->top->en = 1;
    while (!Verilated::gotFinish())
    {
        if (wrap->top->OUT_halt)
        {
            wrap->top->en = 0;
            break;
        }

        wrap->HalfCycle();

        if (wrap->top->clk == 1)
            LogInstructions();

        // Input
        if ((wrap->main_time & 0xff) == 0)
            HandleInput();

        // Hang Detection
        if ((wrap->main_time & (0x3fff)) == 0 && !args.restoreSave && !core->ifetch->waitForInterrupt)
        {
            uint64_t minstret = core->csr->minstret;
            if (minstret == lastMInstret)
            {
                fprintf(stderr, "ERROR: Hang detected\n");
                fprintf(stderr, "ROB_curSqN=%x\n", core->ROB_curSqN);
                DumpState(stderr, (Inst){});
                Exit(-1);
            }
            lastMInstret = minstret;
        }
        if (core->csr->minstret >= nextMinstretPerf)
        {
            if (args.logPerformance)
                LogPerf(core);
            nextMinstretPerf = core->csr->minstret + perfInterval;
        }
        if ((wrap->main_time & 0xffffff) == 0)
        {
            if (!args.backupFile.empty())
                Save(args.backupFile);
        }
        args.restoreSave = 0;
    }

    // Run a few more cycles ...
    for (int i = 0; i < 128; i = i + 1)
    {
        wrap->HalfCycle();
    }

    LogPerf(core);
    printf("%lu cycles\n", wrap->main_time / 2);
    wrap->Final();
}
