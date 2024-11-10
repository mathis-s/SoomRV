#pragma once
#include <cassert>
#include <cstdlib>
#include <cstdint>
#include <array>
#include <cstring>
#include <string>

// Quick and dirty stub reimplementation of sc_bv for SoomRV simulation. Together with the slang-reflect generated
// header file, this is used to unpack structs from raw verilator model data.

template <size_t LEN>
struct sc_bv;

struct range_t
{
    uint64_t* data;
    const size_t low;
    const size_t len;

    range_t(uint64_t* data, size_t low, size_t len) : data(data), low(low), len(len) {}

    uint64_t to_uint64() const
    {
        assert(len <= 64);

        size_t lowI = low / 64;
        size_t lowO = low % 64;

        size_t acc = data[lowI] >> lowO;
        uint64_t mask = len == 64 ? ~0UL : ((1UL << len) - 1);

        if (lowO + len > 64)
            return (acc | (data[lowI+1] << (64 - lowO))) & mask;
        return acc & mask;
    }

    range_t& operator=(uint64_t right)
    {
        assert(len <= 64);

        size_t lowI = low / 64;
        size_t lowO = low % 64;

        uint64_t lowMask = (1UL << lowO) - 1;

        data[lowI] = (data[lowI] & lowMask) | ((right << lowO) & ~lowMask);
        if (lowO + len > 64)
            data[lowI+1] = (data[lowI+1] & ~lowMask) | ((right >> (64 - lowO)) & lowMask);

        return *this;
    }

    range_t range(size_t hi, size_t low)
    {
        return range_t{data, this->low + low, hi-low+1};
    }

    const range_t range(size_t hi, size_t low) const
    {
        return range_t{data, this->low + low, hi-low+1};
    }

    template <int LEN>
    range_t& operator=(sc_bv<LEN> const& right)
    {
        assert(LEN == this->len);
        size_t cnt = 0;
        while (cnt < LEN)
        {
            (*this).range(std::min(cnt+63, len-1), cnt) = right.range(std::min(cnt+63, (size_t)LEN-1), cnt).to_uint64();
            cnt += 64;
        }
        return *this;
    }

    range_t& operator=(range_t const& rhs)
    {
        assert(rhs.len == this->len);
        size_t cnt = 0;
        while (cnt < rhs.len)
        {
            (*this).range(std::min(cnt+63, len-1), cnt) = rhs.range(std::min(cnt+63, (size_t)rhs.len-1), cnt).to_uint64();
            cnt += 64;
        }
        return *this;
    }

    template<size_t LEN>
    operator sc_bv<LEN>() const
    {
        return sc_bv<LEN>((char*)data, low);
    }
};


template <size_t LEN>
struct sc_bv {
    std::array<uint64_t, (LEN+63)/64> data = {};

    sc_bv(const char* init, size_t start_bit = 0)
    {
        init += start_bit / 8;
        start_bit %= 8;
        std::memcpy(data.data(), init, (LEN+7+start_bit)/8);
        if (start_bit != 0)
        {
            for (size_t i = 0; i < data.size(); i++)
                data[i] = (data[i] >> start_bit) | ((i == data.size() - 1) ? 0 : data[i+1] << (64 - start_bit));
        }
    }

    sc_bv() {}

    bool get_bit(size_t index) const
    {
        return !!(data[index/64] & (1UL << (index % 64)));
    }

    void set_bit(size_t index, bool bit)
    {
        data[index/64] = (data[index/64] & ~(1 << (index % 64))) | (bit << (index % 64));
    }

    range_t range(size_t hi, size_t low)
    {
        return range_t{data.data(), low, hi - low + 1};
    }

    const range_t range(size_t hi, size_t low) const
    {
        return range_t{(uint64_t*)data.data(), low, hi - low + 1};
    }

    std::string to_string() const
    {
        std::string s;
        for (size_t i = 0; i < LEN; i+=4)
        {
            uint64_t digit = this->range(std::min(i+3, LEN-1), i).to_uint64();

            if (digit >= 10) digit += 'a' - 10;
            else digit += '0';

            s.insert(s.begin(), (char)digit);
        }
        return s;
    }

    operator range_t() const
    {
        return (*this).range(LEN-1, 0);
    }
};
