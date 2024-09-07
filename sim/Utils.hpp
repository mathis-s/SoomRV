#pragma once
#include "verilated.h"
#include <stdint.h>
#include <stddef.h>

template <size_t N> uint32_t ExtractField(VlWide<N> wide, uint32_t startBit, uint32_t len)
{
    uint32_t wlen = (sizeof(EData) * 8);
    uint32_t endBit = startBit + len - 1;
    uint32_t startI = startBit / wlen;
    uint32_t endI = endBit / wlen;
    if (startI != endI)
    {
        uint32_t indexInFirst = startBit - startI * wlen;
        uint32_t indexInLast = endBit - endI * wlen;

        uint32_t maskLast = (1UL << (indexInLast + 1)) - 1;

        uint32_t maskFirst = ~((1UL << indexInFirst) - 1);

        return ((wide.at(startI) & maskFirst) >> indexInFirst) | ((wide.at(endI) & maskLast) << ((32 - startBit % 32)));
    }
    else
    {
        uint32_t indexInFirst = startBit - startI * wlen;
        uint32_t indexInLast = endBit - endI * wlen;

        uint32_t maskFirst = ~((1UL << indexInFirst) - 1);
        uint32_t maskLast = (1UL << (indexInLast + 1)) - 1;

        return ((wide.at(startI) & maskFirst & maskLast) >> indexInFirst);
    }
}

void PrintBin (FILE* stream, uint64_t n)
{
    for (int i = 63; i >= 0; i=i-1)
        putc((n & (1UL << i)) ? '1' : '0', stream);
    putc('\n', stream);
}
