#pragma once
#include <stdint.h>

struct Inst
{
    uint32_t inst;
    uint32_t id;
    uint32_t pc;
    uint32_t srcA;
    uint32_t srcB;
    uint32_t srcC;
    uint32_t imm;
    uint32_t result;
    uint32_t memAddr;
    uint32_t memData;
    uint32_t predTarget;
    uint16_t fetchID;
    uint16_t sqn;
    uint8_t fu;
    uint8_t rd;
    uint16_t tag;
    uint8_t flags;
    uint8_t interruptCause;
    uint8_t retIdx;
    uint64_t minstret;
    bool incMinstret;
    bool interruptDelegate;
    enum InterruptType
    {
        IR_NONE,
        IR_SQUASH,
        IR_KEEP
    } interrupt;
    bool valid;
};

struct FetchPacket
{
    uint32_t returnAddr[4];
    uint64_t fetchTime;
    uint64_t pdTime;
};

struct Store
{
    uint32_t addr;
    uint32_t data;
    uint8_t size;
    uint64_t time;
};
