// .h
#pragma once

#include <ostream>
#include <cstddef>
#include <cstdint>
#include <string>
#include <sstream>


namespace  {
    struct FuncUnit {
        enum Type : uint8_t {
            FU_INT = 0,
            FU_BRANCH = 1,
            FU_BITMANIP = 2,
            FU_AGU = 3,
            FU_MUL = 4,
            FU_DIV = 5,
            FU_FPU = 6,
            FU_FMUL = 7,
            FU_FDIV = 8,
            FU_RN = 9,
            FU_ATOMIC = 10,
            FU_CSR = 11,
            FU_TRAP = 12
        };

        static constexpr size_t _size = 4;

        Type type;
        FuncUnit() = default;
        FuncUnit (uint8_t __data) {
            switch (__data) {
                case 0: type = Type::FU_INT; break;
                case 1: type = Type::FU_BRANCH; break;
                case 2: type = Type::FU_BITMANIP; break;
                case 3: type = Type::FU_AGU; break;
                case 4: type = Type::FU_MUL; break;
                case 5: type = Type::FU_DIV; break;
                case 6: type = Type::FU_FPU; break;
                case 7: type = Type::FU_FMUL; break;
                case 8: type = Type::FU_FDIV; break;
                case 9: type = Type::FU_RN; break;
                case 10: type = Type::FU_ATOMIC; break;
                case 11: type = Type::FU_CSR; break;
                case 12: type = Type::FU_TRAP; break;
                default: throw std::runtime_error("Can not create FuncUnit from provided value");
            }
        }

        FuncUnit (Type& type) { this->type = type; }
        friend std::ostream& operator<<(std::ostream& os, const FuncUnit& __data) {
            switch (__data.type) {
                case Type::FU_INT: os << "FU_INT"; break;
                case Type::FU_BRANCH: os << "FU_BRANCH"; break;
                case Type::FU_BITMANIP: os << "FU_BITMANIP"; break;
                case Type::FU_AGU: os << "FU_AGU"; break;
                case Type::FU_MUL: os << "FU_MUL"; break;
                case Type::FU_DIV: os << "FU_DIV"; break;
                case Type::FU_FPU: os << "FU_FPU"; break;
                case Type::FU_FMUL: os << "FU_FMUL"; break;
                case Type::FU_FDIV: os << "FU_FDIV"; break;
                case Type::FU_RN: os << "FU_RN"; break;
                case Type::FU_ATOMIC: os << "FU_ATOMIC"; break;
                case Type::FU_CSR: os << "FU_CSR"; break;
                case Type::FU_TRAP: os << "FU_TRAP"; break;
            }
            return os;
        }

        FuncUnit& operator=(const Type t) {
            this->type = t;
            return *this;
        }

        operator uint64_t() const {
            return static_cast<uint64_t>(type);
        }

        Type operator() () const {
            return type;
        }

    };

    struct Flags {
        enum Type : uint8_t {
            FLAGS_NONE = 0,
            FLAGS_BRANCH = 1,
            FLAGS_PRED_TAKEN = 2,
            FLAGS_PRED_NTAKEN = 3,
            FLAGS_FENCE = 4,
            FLAGS_ORDERING = 5,
            FLAGS_ILLEGAL_INSTR = 6,
            FLAGS_TRAP = 7,
            FLAGS_LD_MA = 8,
            FLAGS_LD_AF = 9,
            FLAGS_LD_PF = 10,
            FLAGS_ST_MA = 11,
            FLAGS_ST_AF = 12,
            FLAGS_ST_PF = 13,
            FLAGS_XRET = 14,
            FLAGS_NX = 15
        };

        static constexpr size_t _size = 4;

        Type type;
        Flags() = default;
        Flags (uint8_t __data) {
            switch (__data) {
                case 0: type = Type::FLAGS_NONE; break;
                case 1: type = Type::FLAGS_BRANCH; break;
                case 2: type = Type::FLAGS_PRED_TAKEN; break;
                case 3: type = Type::FLAGS_PRED_NTAKEN; break;
                case 4: type = Type::FLAGS_FENCE; break;
                case 5: type = Type::FLAGS_ORDERING; break;
                case 6: type = Type::FLAGS_ILLEGAL_INSTR; break;
                case 7: type = Type::FLAGS_TRAP; break;
                case 8: type = Type::FLAGS_LD_MA; break;
                case 9: type = Type::FLAGS_LD_AF; break;
                case 10: type = Type::FLAGS_LD_PF; break;
                case 11: type = Type::FLAGS_ST_MA; break;
                case 12: type = Type::FLAGS_ST_AF; break;
                case 13: type = Type::FLAGS_ST_PF; break;
                case 14: type = Type::FLAGS_XRET; break;
                case 15: type = Type::FLAGS_NX; break;
                default: throw std::runtime_error("Can not create Flags from provided value");
            }
        }

        Flags (Type& type) { this->type = type; }
        friend std::ostream& operator<<(std::ostream& os, const Flags& __data) {
            switch (__data.type) {
                case Type::FLAGS_NONE: os << "FLAGS_NONE"; break;
                case Type::FLAGS_BRANCH: os << "FLAGS_BRANCH"; break;
                case Type::FLAGS_PRED_TAKEN: os << "FLAGS_PRED_TAKEN"; break;
                case Type::FLAGS_PRED_NTAKEN: os << "FLAGS_PRED_NTAKEN"; break;
                case Type::FLAGS_FENCE: os << "FLAGS_FENCE"; break;
                case Type::FLAGS_ORDERING: os << "FLAGS_ORDERING"; break;
                case Type::FLAGS_ILLEGAL_INSTR: os << "FLAGS_ILLEGAL_INSTR"; break;
                case Type::FLAGS_TRAP: os << "FLAGS_TRAP"; break;
                case Type::FLAGS_LD_MA: os << "FLAGS_LD_MA"; break;
                case Type::FLAGS_LD_AF: os << "FLAGS_LD_AF"; break;
                case Type::FLAGS_LD_PF: os << "FLAGS_LD_PF"; break;
                case Type::FLAGS_ST_MA: os << "FLAGS_ST_MA"; break;
                case Type::FLAGS_ST_AF: os << "FLAGS_ST_AF"; break;
                case Type::FLAGS_ST_PF: os << "FLAGS_ST_PF"; break;
                case Type::FLAGS_XRET: os << "FLAGS_XRET"; break;
                case Type::FLAGS_NX: os << "FLAGS_NX"; break;
            }
            return os;
        }

        Flags& operator=(const Type t) {
            this->type = t;
            return *this;
        }

        operator uint64_t() const {
            return static_cast<uint64_t>(type);
        }

        Type operator() () const {
            return type;
        }

    };

    struct IFetchFault {
        enum Type : uint8_t {
            IF_FAULT_NONE = 0,
            IF_INTERRUPT = 1,
            IF_ACCESS_FAULT = 2,
            IF_PAGE_FAULT = 3
        };

        static constexpr size_t _size = 2;

        Type type;
        IFetchFault() = default;
        IFetchFault (uint8_t __data) {
            switch (__data) {
                case 0: type = Type::IF_FAULT_NONE; break;
                case 1: type = Type::IF_INTERRUPT; break;
                case 2: type = Type::IF_ACCESS_FAULT; break;
                case 3: type = Type::IF_PAGE_FAULT; break;
                default: throw std::runtime_error("Can not create IFetchFault from provided value");
            }
        }

        IFetchFault (Type& type) { this->type = type; }
        friend std::ostream& operator<<(std::ostream& os, const IFetchFault& __data) {
            switch (__data.type) {
                case Type::IF_FAULT_NONE: os << "IF_FAULT_NONE"; break;
                case Type::IF_INTERRUPT: os << "IF_INTERRUPT"; break;
                case Type::IF_ACCESS_FAULT: os << "IF_ACCESS_FAULT"; break;
                case Type::IF_PAGE_FAULT: os << "IF_PAGE_FAULT"; break;
            }
            return os;
        }

        IFetchFault& operator=(const Type t) {
            this->type = t;
            return *this;
        }

        operator uint64_t() const {
            return static_cast<uint64_t>(type);
        }

        Type operator() () const {
            return type;
        }

    };

    struct FlushCause {
        enum Type : uint8_t {
            FLUSH_ORDERING = 0,
            FLUSH_BRANCH_TK = 1,
            FLUSH_BRANCH_NT = 2,
            FLUSH_RETURN = 3,
            FLUSH_IBRANCH = 4,
            FLUSH_MEM_ORDER = 5
        };

        static constexpr size_t _size = 3;

        Type type;
        FlushCause() = default;
        FlushCause (uint8_t __data) {
            switch (__data) {
                case 0: type = Type::FLUSH_ORDERING; break;
                case 1: type = Type::FLUSH_BRANCH_TK; break;
                case 2: type = Type::FLUSH_BRANCH_NT; break;
                case 3: type = Type::FLUSH_RETURN; break;
                case 4: type = Type::FLUSH_IBRANCH; break;
                case 5: type = Type::FLUSH_MEM_ORDER; break;
                default: throw std::runtime_error("Can not create FlushCause from provided value");
            }
        }

        FlushCause (Type& type) { this->type = type; }
        friend std::ostream& operator<<(std::ostream& os, const FlushCause& __data) {
            switch (__data.type) {
                case Type::FLUSH_ORDERING: os << "FLUSH_ORDERING"; break;
                case Type::FLUSH_BRANCH_TK: os << "FLUSH_BRANCH_TK"; break;
                case Type::FLUSH_BRANCH_NT: os << "FLUSH_BRANCH_NT"; break;
                case Type::FLUSH_RETURN: os << "FLUSH_RETURN"; break;
                case Type::FLUSH_IBRANCH: os << "FLUSH_IBRANCH"; break;
                case Type::FLUSH_MEM_ORDER: os << "FLUSH_MEM_ORDER"; break;
            }
            return os;
        }

        FlushCause& operator=(const Type t) {
            this->type = t;
            return *this;
        }

        operator uint64_t() const {
            return static_cast<uint64_t>(type);
        }

        Type operator() () const {
            return type;
        }

    };

    struct BranchType {
        enum Type : uint8_t {
            BT_JUMP = 0,
            BT_CALL = 1,
            BT_BRANCH = 2,
            BT_RETURN = 3
        };

        static constexpr size_t _size = 2;

        Type type;
        BranchType() = default;
        BranchType (uint8_t __data) {
            switch (__data) {
                case 0: type = Type::BT_JUMP; break;
                case 1: type = Type::BT_CALL; break;
                case 2: type = Type::BT_BRANCH; break;
                case 3: type = Type::BT_RETURN; break;
                default: throw std::runtime_error("Can not create BranchType from provided value");
            }
        }

        BranchType (Type& type) { this->type = type; }
        friend std::ostream& operator<<(std::ostream& os, const BranchType& __data) {
            switch (__data.type) {
                case Type::BT_JUMP: os << "BT_JUMP"; break;
                case Type::BT_CALL: os << "BT_CALL"; break;
                case Type::BT_BRANCH: os << "BT_BRANCH"; break;
                case Type::BT_RETURN: os << "BT_RETURN"; break;
            }
            return os;
        }

        BranchType& operator=(const Type t) {
            this->type = t;
            return *this;
        }

        operator uint64_t() const {
            return static_cast<uint64_t>(type);
        }

        Type operator() () const {
            return type;
        }

    };

    struct PredBranch {
        bool valid;
        bool dirOnly;
        bool taken;
        bool multiple;
        BranchType btype;
        bool compr;
        uint32_t offs;
        uint32_t dst;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t dirOnly_s = 1;
        static constexpr size_t dirOnly_w = 1;
        static constexpr size_t taken_s = 2;
        static constexpr size_t taken_w = 1;
        static constexpr size_t multiple_s = 3;
        static constexpr size_t multiple_w = 1;
        static constexpr size_t btype_s = 4;
        static constexpr size_t btype_w = 2;
        static constexpr size_t compr_s = 6;
        static constexpr size_t compr_w = 1;
        static constexpr size_t offs_s = 7;
        static constexpr size_t offs_w = 3;
        static constexpr size_t dst_s = 10;
        static constexpr size_t dst_w = 31;
        static constexpr size_t _size = 41;

        PredBranch() = default;

        PredBranch(const uint64_t& __data) {
            valid = (__data >> valid_s) & (~0ULL >> (64 - 1));
            dirOnly = (__data >> dirOnly_s) & (~0ULL >> (64 - 1));
            taken = (__data >> taken_s) & (~0ULL >> (64 - 1));
            multiple = (__data >> multiple_s) & (~0ULL >> (64 - 1));
            btype = BranchType((__data >> btype_s) & (~0ULL >> (64 - 2)));
            compr = (__data >> compr_s) & (~0ULL >> (64 - 1));
            offs = (__data >> offs_s) & (~0ULL >> (64 - 3));
            dst = (__data >> dst_s) & (~0ULL >> (64 - 31));
        }

        PredBranch(const sc_bv<41>& __data) {
            valid = __data.get_bit(valid_s);
            dirOnly = __data.get_bit(dirOnly_s);
            taken = __data.get_bit(taken_s);
            multiple = __data.get_bit(multiple_s);
            btype = BranchType(__data.range(btype_s + btype_w - 1, btype_s).to_uint64());
            compr = __data.get_bit(compr_s);
            offs = __data.range(offs_s + offs_w - 1, offs_s).to_uint64();
            dst = __data.range(dst_s + dst_w - 1, dst_s).to_uint64();
        }

        operator uint64_t() const {
            uint64_t ret = 0;
            ret |= static_cast<uint64_t>(valid) << valid_s;
            ret |= static_cast<uint64_t>(dirOnly) << dirOnly_s;
            ret |= static_cast<uint64_t>(taken) << taken_s;
            ret |= static_cast<uint64_t>(multiple) << multiple_s;
            ret |= static_cast<uint64_t>(btype) << btype_s;
            ret |= static_cast<uint64_t>(compr) << compr_s;
            ret |= static_cast<uint64_t>(offs) << offs_s;
            ret |= static_cast<uint64_t>(dst) << dst_s;
            return ret;
        }

        operator sc_bv<41>() const {
            auto ret = sc_bv<41>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(dirOnly_s, dirOnly);
            ret.set_bit(taken_s, taken);
            ret.set_bit(multiple_s, multiple);
            ret.range(btype_s + btype_w - 1, btype_s) = btype;
            ret.set_bit(compr_s, compr);
            ret.range(offs_s + offs_w - 1, offs_s) = offs;
            ret.range(dst_s + dst_w - 1, dst_s) = dst;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " dirOnly" << " = " << dirOnly;
            ss << " taken" << " = " << taken;
            ss << " multiple" << " = " << multiple;
            ss << " btype" << " = " << btype;
            ss << " compr" << " = " << compr;
            ss << " offs" << " = " << offs;
            ss << " dst" << " = " << dst;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const PredBranch& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const uint64_t& __data) {
            return (__data >> valid_s) & (~0ULL >> (64 - 1));
        }
        static bool get_dirOnly (const uint64_t& __data) {
            return (__data >> dirOnly_s) & (~0ULL >> (64 - 1));
        }
        static bool get_taken (const uint64_t& __data) {
            return (__data >> taken_s) & (~0ULL >> (64 - 1));
        }
        static bool get_multiple (const uint64_t& __data) {
            return (__data >> multiple_s) & (~0ULL >> (64 - 1));
        }
        static BranchType get_btype (const uint64_t& __data) {
            return BranchType((__data >> btype_s) & (~0ULL >> (64 - 2)));
        }
        static bool get_compr (const uint64_t& __data) {
            return (__data >> compr_s) & (~0ULL >> (64 - 1));
        }
        static uint32_t get_offs (const uint64_t& __data) {
            return (__data >> offs_s) & (~0ULL >> (64 - 3));
        }
        static uint32_t get_dst (const uint64_t& __data) {
            return (__data >> dst_s) & (~0ULL >> (64 - 31));
        }
    };

    struct BranchPredInfo {
        bool taken;

        static constexpr size_t taken_s = 0;
        static constexpr size_t taken_w = 1;
        static constexpr size_t _size = 1;

        BranchPredInfo() = default;

        BranchPredInfo(const bool& __data) {
            taken = (__data >> taken_s) & (~0ULL >> (64 - 1));
        }

        BranchPredInfo(const sc_bv<1>& __data) {
            taken = __data.get_bit(taken_s);
        }

        operator bool() const {
            bool ret = 0;
            ret |= static_cast<bool>(taken) << taken_s;
            return ret;
        }

        operator sc_bv<1>() const {
            auto ret = sc_bv<1>();
            ret.set_bit(taken_s, taken);
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "taken" << " = " << taken;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const BranchPredInfo& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_taken (const bool& __data) {
            return (__data >> taken_s) & (~0ULL >> (64 - 1));
        }
    };

    struct RetStackAction {
        enum Type : uint8_t {
            RET_NONE = 0,
            RET_PUSH = 1,
            RET_POP = 2
        };

        static constexpr size_t _size = 2;

        Type type;
        RetStackAction() = default;
        RetStackAction (uint8_t __data) {
            switch (__data) {
                case 0: type = Type::RET_NONE; break;
                case 1: type = Type::RET_PUSH; break;
                case 2: type = Type::RET_POP; break;
                default: throw std::runtime_error("Can not create RetStackAction from provided value");
            }
        }

        RetStackAction (Type& type) { this->type = type; }
        friend std::ostream& operator<<(std::ostream& os, const RetStackAction& __data) {
            switch (__data.type) {
                case Type::RET_NONE: os << "RET_NONE"; break;
                case Type::RET_PUSH: os << "RET_PUSH"; break;
                case Type::RET_POP: os << "RET_POP"; break;
            }
            return os;
        }

        RetStackAction& operator=(const Type t) {
            this->type = t;
            return *this;
        }

        operator uint64_t() const {
            return static_cast<uint64_t>(type);
        }

        Type operator() () const {
            return type;
        }

    };

    struct HistoryAction {
        enum Type : uint8_t {
            HIST_NONE = 0,
            HIST_APPEND_0 = 1,
            HIST_APPEND_1 = 2,
            HIST_WRITE_0 = 3,
            HIST_WRITE_1 = 4
        };

        static constexpr size_t _size = 3;

        Type type;
        HistoryAction() = default;
        HistoryAction (uint8_t __data) {
            switch (__data) {
                case 0: type = Type::HIST_NONE; break;
                case 1: type = Type::HIST_APPEND_0; break;
                case 2: type = Type::HIST_APPEND_1; break;
                case 3: type = Type::HIST_WRITE_0; break;
                case 4: type = Type::HIST_WRITE_1; break;
                default: throw std::runtime_error("Can not create HistoryAction from provided value");
            }
        }

        HistoryAction (Type& type) { this->type = type; }
        friend std::ostream& operator<<(std::ostream& os, const HistoryAction& __data) {
            switch (__data.type) {
                case Type::HIST_NONE: os << "HIST_NONE"; break;
                case Type::HIST_APPEND_0: os << "HIST_APPEND_0"; break;
                case Type::HIST_APPEND_1: os << "HIST_APPEND_1"; break;
                case Type::HIST_WRITE_0: os << "HIST_WRITE_0"; break;
                case Type::HIST_WRITE_1: os << "HIST_WRITE_1"; break;
            }
            return os;
        }

        HistoryAction& operator=(const Type t) {
            this->type = t;
            return *this;
        }

        operator uint64_t() const {
            return static_cast<uint64_t>(type);
        }

        Type operator() () const {
            return type;
        }

    };

    struct BranchTargetSpec {
        enum Type : uint8_t {
            BR_TGT_MANUAL = 0,
            BR_TGT_NEXT = 1,
            BR_TGT_CUR16 = 2,
            BR_TGT_CUR32 = 3
        };

        static constexpr size_t _size = 2;

        Type type;
        BranchTargetSpec() = default;
        BranchTargetSpec (uint8_t __data) {
            switch (__data) {
                case 0: type = Type::BR_TGT_MANUAL; break;
                case 1: type = Type::BR_TGT_NEXT; break;
                case 2: type = Type::BR_TGT_CUR16; break;
                case 3: type = Type::BR_TGT_CUR32; break;
                default: throw std::runtime_error("Can not create BranchTargetSpec from provided value");
            }
        }

        BranchTargetSpec (Type& type) { this->type = type; }
        friend std::ostream& operator<<(std::ostream& os, const BranchTargetSpec& __data) {
            switch (__data.type) {
                case Type::BR_TGT_MANUAL: os << "BR_TGT_MANUAL"; break;
                case Type::BR_TGT_NEXT: os << "BR_TGT_NEXT"; break;
                case Type::BR_TGT_CUR16: os << "BR_TGT_CUR16"; break;
                case Type::BR_TGT_CUR32: os << "BR_TGT_CUR32"; break;
            }
            return os;
        }

        BranchTargetSpec& operator=(const Type t) {
            this->type = t;
            return *this;
        }

        operator uint64_t() const {
            return static_cast<uint64_t>(type);
        }

        Type operator() () const {
            return type;
        }

    };

    struct BranchProv {
        bool taken;
        uint32_t fetchID;
        bool flush;
        uint32_t loadSqN;
        uint32_t storeSqN;
        uint32_t sqN;
        uint32_t dstPC;
        HistoryAction histAct;
        RetStackAction retAct;
        uint32_t fetchOffs;
        bool isSCFail;
        BranchTargetSpec tgtSpec;
        FlushCause cause;

        static constexpr size_t taken_s = 0;
        static constexpr size_t taken_w = 1;
        static constexpr size_t fetchID_s = 1;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t flush_s = 7;
        static constexpr size_t flush_w = 1;
        static constexpr size_t loadSqN_s = 8;
        static constexpr size_t loadSqN_w = 7;
        static constexpr size_t storeSqN_s = 15;
        static constexpr size_t storeSqN_w = 7;
        static constexpr size_t sqN_s = 22;
        static constexpr size_t sqN_w = 7;
        static constexpr size_t dstPC_s = 29;
        static constexpr size_t dstPC_w = 32;
        static constexpr size_t histAct_s = 61;
        static constexpr size_t histAct_w = 3;
        static constexpr size_t retAct_s = 64;
        static constexpr size_t retAct_w = 2;
        static constexpr size_t fetchOffs_s = 66;
        static constexpr size_t fetchOffs_w = 3;
        static constexpr size_t isSCFail_s = 69;
        static constexpr size_t isSCFail_w = 1;
        static constexpr size_t tgtSpec_s = 70;
        static constexpr size_t tgtSpec_w = 2;
        static constexpr size_t cause_s = 72;
        static constexpr size_t cause_w = 3;
        static constexpr size_t _size = 75;

        BranchProv() = default;

        BranchProv(const sc_bv<75>& __data) {
            taken = __data.get_bit(taken_s);
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            flush = __data.get_bit(flush_s);
            loadSqN = __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
            storeSqN = __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
            sqN = __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
            dstPC = __data.range(dstPC_s + dstPC_w - 1, dstPC_s).to_uint64();
            histAct = HistoryAction(__data.range(histAct_s + histAct_w - 1, histAct_s).to_uint64());
            retAct = RetStackAction(__data.range(retAct_s + retAct_w - 1, retAct_s).to_uint64());
            fetchOffs = __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
            isSCFail = __data.get_bit(isSCFail_s);
            tgtSpec = BranchTargetSpec(__data.range(tgtSpec_s + tgtSpec_w - 1, tgtSpec_s).to_uint64());
            cause = FlushCause(__data.range(cause_s + cause_w - 1, cause_s).to_uint64());
        }

        operator sc_bv<75>() const {
            auto ret = sc_bv<75>();
            ret.set_bit(taken_s, taken);
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.set_bit(flush_s, flush);
            ret.range(loadSqN_s + loadSqN_w - 1, loadSqN_s) = loadSqN;
            ret.range(storeSqN_s + storeSqN_w - 1, storeSqN_s) = storeSqN;
            ret.range(sqN_s + sqN_w - 1, sqN_s) = sqN;
            ret.range(dstPC_s + dstPC_w - 1, dstPC_s) = dstPC;
            ret.range(histAct_s + histAct_w - 1, histAct_s) = histAct;
            ret.range(retAct_s + retAct_w - 1, retAct_s) = retAct;
            ret.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s) = fetchOffs;
            ret.set_bit(isSCFail_s, isSCFail);
            ret.range(tgtSpec_s + tgtSpec_w - 1, tgtSpec_s) = tgtSpec;
            ret.range(cause_s + cause_w - 1, cause_s) = cause;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "taken" << " = " << taken;
            ss << " fetchID" << " = " << fetchID;
            ss << " flush" << " = " << flush;
            ss << " loadSqN" << " = " << loadSqN;
            ss << " storeSqN" << " = " << storeSqN;
            ss << " sqN" << " = " << sqN;
            ss << " dstPC" << " = " << dstPC;
            ss << " histAct" << " = " << histAct;
            ss << " retAct" << " = " << retAct;
            ss << " fetchOffs" << " = " << fetchOffs;
            ss << " isSCFail" << " = " << isSCFail;
            ss << " tgtSpec" << " = " << tgtSpec;
            ss << " cause" << " = " << cause;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const BranchProv& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_taken (const sc_bv<75>& __data) {
            return __data.get_bit(taken_s);
        }
        static uint32_t get_fetchID (const sc_bv<75>& __data) {
            return __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
        }
        static bool get_flush (const sc_bv<75>& __data) {
            return __data.get_bit(flush_s);
        }
        static uint32_t get_loadSqN (const sc_bv<75>& __data) {
            return __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
        }
        static uint32_t get_storeSqN (const sc_bv<75>& __data) {
            return __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
        }
        static uint32_t get_sqN (const sc_bv<75>& __data) {
            return __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
        }
        static uint32_t get_dstPC (const sc_bv<75>& __data) {
            return __data.range(dstPC_s + dstPC_w - 1, dstPC_s).to_uint64();
        }
        static HistoryAction get_histAct (const sc_bv<75>& __data) {
            return HistoryAction(__data.range(histAct_s + histAct_w - 1, histAct_s).to_uint64());
        }
        static RetStackAction get_retAct (const sc_bv<75>& __data) {
            return RetStackAction(__data.range(retAct_s + retAct_w - 1, retAct_s).to_uint64());
        }
        static uint32_t get_fetchOffs (const sc_bv<75>& __data) {
            return __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
        }
        static bool get_isSCFail (const sc_bv<75>& __data) {
            return __data.get_bit(isSCFail_s);
        }
        static BranchTargetSpec get_tgtSpec (const sc_bv<75>& __data) {
            return BranchTargetSpec(__data.range(tgtSpec_s + tgtSpec_w - 1, tgtSpec_s).to_uint64());
        }
        static FlushCause get_cause (const sc_bv<75>& __data) {
            return FlushCause(__data.range(cause_s + cause_w - 1, cause_s).to_uint64());
        }
    };

    struct BPBackup {
        bool pred;
        uint32_t predOffs;
        bool predTaken;
        bool isRegularBranch;
        uint32_t rIdx;
        uint64_t history;
        bool altPred;
        uint32_t tageID;

        static constexpr size_t pred_s = 0;
        static constexpr size_t pred_w = 1;
        static constexpr size_t predOffs_s = 1;
        static constexpr size_t predOffs_w = 3;
        static constexpr size_t predTaken_s = 4;
        static constexpr size_t predTaken_w = 1;
        static constexpr size_t isRegularBranch_s = 5;
        static constexpr size_t isRegularBranch_w = 1;
        static constexpr size_t rIdx_s = 6;
        static constexpr size_t rIdx_w = 5;
        static constexpr size_t history_s = 11;
        static constexpr size_t history_w = 64;
        static constexpr size_t altPred_s = 75;
        static constexpr size_t altPred_w = 1;
        static constexpr size_t tageID_s = 76;
        static constexpr size_t tageID_w = 4;
        static constexpr size_t _size = 80;

        BPBackup() = default;

        BPBackup(const sc_bv<80>& __data) {
            pred = __data.get_bit(pred_s);
            predOffs = __data.range(predOffs_s + predOffs_w - 1, predOffs_s).to_uint64();
            predTaken = __data.get_bit(predTaken_s);
            isRegularBranch = __data.get_bit(isRegularBranch_s);
            rIdx = __data.range(rIdx_s + rIdx_w - 1, rIdx_s).to_uint64();
            history = __data.range(history_s + history_w - 1, history_s).to_uint64();
            altPred = __data.get_bit(altPred_s);
            tageID = __data.range(tageID_s + tageID_w - 1, tageID_s).to_uint64();
        }

        operator sc_bv<80>() const {
            auto ret = sc_bv<80>();
            ret.set_bit(pred_s, pred);
            ret.range(predOffs_s + predOffs_w - 1, predOffs_s) = predOffs;
            ret.set_bit(predTaken_s, predTaken);
            ret.set_bit(isRegularBranch_s, isRegularBranch);
            ret.range(rIdx_s + rIdx_w - 1, rIdx_s) = rIdx;
            ret.range(history_s + history_w - 1, history_s) = history;
            ret.set_bit(altPred_s, altPred);
            ret.range(tageID_s + tageID_w - 1, tageID_s) = tageID;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "pred" << " = " << pred;
            ss << " predOffs" << " = " << predOffs;
            ss << " predTaken" << " = " << predTaken;
            ss << " isRegularBranch" << " = " << isRegularBranch;
            ss << " rIdx" << " = " << rIdx;
            ss << " history" << " = " << history;
            ss << " altPred" << " = " << altPred;
            ss << " tageID" << " = " << tageID;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const BPBackup& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_pred (const sc_bv<80>& __data) {
            return __data.get_bit(pred_s);
        }
        static uint32_t get_predOffs (const sc_bv<80>& __data) {
            return __data.range(predOffs_s + predOffs_w - 1, predOffs_s).to_uint64();
        }
        static bool get_predTaken (const sc_bv<80>& __data) {
            return __data.get_bit(predTaken_s);
        }
        static bool get_isRegularBranch (const sc_bv<80>& __data) {
            return __data.get_bit(isRegularBranch_s);
        }
        static uint32_t get_rIdx (const sc_bv<80>& __data) {
            return __data.range(rIdx_s + rIdx_w - 1, rIdx_s).to_uint64();
        }
        static uint64_t get_history (const sc_bv<80>& __data) {
            return __data.range(history_s + history_w - 1, history_s).to_uint64();
        }
        static bool get_altPred (const sc_bv<80>& __data) {
            return __data.get_bit(altPred_s);
        }
        static uint32_t get_tageID (const sc_bv<80>& __data) {
            return __data.range(tageID_s + tageID_w - 1, tageID_s).to_uint64();
        }
    };

    struct IFetchOp {
        bool valid;
        uint32_t rIdx;
        uint32_t predRetAddr;
        PredBranch predBr;
        uint32_t lastValid;
        IFetchFault fetchFault;
        uint32_t fetchID;
        uint32_t pc;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t rIdx_s = 1;
        static constexpr size_t rIdx_w = 5;
        static constexpr size_t predRetAddr_s = 6;
        static constexpr size_t predRetAddr_w = 31;
        static constexpr size_t predBr_s = 37;
        static constexpr size_t predBr_w = 41;
        static constexpr size_t lastValid_s = 78;
        static constexpr size_t lastValid_w = 3;
        static constexpr size_t fetchFault_s = 81;
        static constexpr size_t fetchFault_w = 2;
        static constexpr size_t fetchID_s = 83;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t pc_s = 89;
        static constexpr size_t pc_w = 32;
        static constexpr size_t _size = 121;

        IFetchOp() = default;

        IFetchOp(const sc_bv<121>& __data) {
            valid = __data.get_bit(valid_s);
            rIdx = __data.range(rIdx_s + rIdx_w - 1, rIdx_s).to_uint64();
            predRetAddr = __data.range(predRetAddr_s + predRetAddr_w - 1, predRetAddr_s).to_uint64();
            predBr = PredBranch(__data.range(predBr_s + predBr_w - 1, predBr_s).to_uint64());
            lastValid = __data.range(lastValid_s + lastValid_w - 1, lastValid_s).to_uint64();
            fetchFault = IFetchFault(__data.range(fetchFault_s + fetchFault_w - 1, fetchFault_s).to_uint64());
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            pc = __data.range(pc_s + pc_w - 1, pc_s).to_uint64();
        }

        operator sc_bv<121>() const {
            auto ret = sc_bv<121>();
            ret.set_bit(valid_s, valid);
            ret.range(rIdx_s + rIdx_w - 1, rIdx_s) = rIdx;
            ret.range(predRetAddr_s + predRetAddr_w - 1, predRetAddr_s) = predRetAddr;
            ret.range(predBr_s + predBr_w - 1, predBr_s) = predBr;
            ret.range(lastValid_s + lastValid_w - 1, lastValid_s) = lastValid;
            ret.range(fetchFault_s + fetchFault_w - 1, fetchFault_s) = fetchFault;
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.range(pc_s + pc_w - 1, pc_s) = pc;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " rIdx" << " = " << rIdx;
            ss << " predRetAddr" << " = " << predRetAddr;
            ss << " predBr" << " = " << predBr.to_string();
            ss << " lastValid" << " = " << lastValid;
            ss << " fetchFault" << " = " << fetchFault;
            ss << " fetchID" << " = " << fetchID;
            ss << " pc" << " = " << pc;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const IFetchOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const sc_bv<121>& __data) {
            return __data.get_bit(valid_s);
        }
        static uint32_t get_rIdx (const sc_bv<121>& __data) {
            return __data.range(rIdx_s + rIdx_w - 1, rIdx_s).to_uint64();
        }
        static uint32_t get_predRetAddr (const sc_bv<121>& __data) {
            return __data.range(predRetAddr_s + predRetAddr_w - 1, predRetAddr_s).to_uint64();
        }
        static PredBranch get_predBr (const sc_bv<121>& __data) {
            return PredBranch(__data.range(predBr_s + predBr_w - 1, predBr_s).to_uint64());
        }
        static uint32_t get_lastValid (const sc_bv<121>& __data) {
            return __data.range(lastValid_s + lastValid_w - 1, lastValid_s).to_uint64();
        }
        static IFetchFault get_fetchFault (const sc_bv<121>& __data) {
            return IFetchFault(__data.range(fetchFault_s + fetchFault_w - 1, fetchFault_s).to_uint64());
        }
        static uint32_t get_fetchID (const sc_bv<121>& __data) {
            return __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
        }
        static uint32_t get_pc (const sc_bv<121>& __data) {
            return __data.range(pc_s + pc_w - 1, pc_s).to_uint64();
        }
    };

    struct IF_Instr {
        bool valid;
        sc_bv<128> instrs;
        uint32_t predTarget;
        bool predTaken;
        uint32_t predPos;
        uint32_t lastValid;
        uint32_t firstValid;
        IFetchFault fetchFault;
        uint32_t fetchID;
        uint32_t pc;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t instrs_s = 1;
        static constexpr size_t instrs_w = 128;
        static constexpr size_t predTarget_s = 129;
        static constexpr size_t predTarget_w = 31;
        static constexpr size_t predTaken_s = 160;
        static constexpr size_t predTaken_w = 1;
        static constexpr size_t predPos_s = 161;
        static constexpr size_t predPos_w = 3;
        static constexpr size_t lastValid_s = 164;
        static constexpr size_t lastValid_w = 3;
        static constexpr size_t firstValid_s = 167;
        static constexpr size_t firstValid_w = 3;
        static constexpr size_t fetchFault_s = 170;
        static constexpr size_t fetchFault_w = 2;
        static constexpr size_t fetchID_s = 172;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t pc_s = 178;
        static constexpr size_t pc_w = 28;
        static constexpr size_t _size = 206;

        IF_Instr() = default;

        IF_Instr(const sc_bv<206>& __data) {
            valid = __data.get_bit(valid_s);
            instrs = __data.range(instrs_s + instrs_w - 1, instrs_s);
            predTarget = __data.range(predTarget_s + predTarget_w - 1, predTarget_s).to_uint64();
            predTaken = __data.get_bit(predTaken_s);
            predPos = __data.range(predPos_s + predPos_w - 1, predPos_s).to_uint64();
            lastValid = __data.range(lastValid_s + lastValid_w - 1, lastValid_s).to_uint64();
            firstValid = __data.range(firstValid_s + firstValid_w - 1, firstValid_s).to_uint64();
            fetchFault = IFetchFault(__data.range(fetchFault_s + fetchFault_w - 1, fetchFault_s).to_uint64());
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            pc = __data.range(pc_s + pc_w - 1, pc_s).to_uint64();
        }

        operator sc_bv<206>() const {
            auto ret = sc_bv<206>();
            ret.set_bit(valid_s, valid);
            ret.range(instrs_s + instrs_w - 1, instrs_s) = instrs;
            ret.range(predTarget_s + predTarget_w - 1, predTarget_s) = predTarget;
            ret.set_bit(predTaken_s, predTaken);
            ret.range(predPos_s + predPos_w - 1, predPos_s) = predPos;
            ret.range(lastValid_s + lastValid_w - 1, lastValid_s) = lastValid;
            ret.range(firstValid_s + firstValid_w - 1, firstValid_s) = firstValid;
            ret.range(fetchFault_s + fetchFault_w - 1, fetchFault_s) = fetchFault;
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.range(pc_s + pc_w - 1, pc_s) = pc;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " instrs" << " = " << instrs.to_string();
            ss << " predTarget" << " = " << predTarget;
            ss << " predTaken" << " = " << predTaken;
            ss << " predPos" << " = " << predPos;
            ss << " lastValid" << " = " << lastValid;
            ss << " firstValid" << " = " << firstValid;
            ss << " fetchFault" << " = " << fetchFault;
            ss << " fetchID" << " = " << fetchID;
            ss << " pc" << " = " << pc;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const IF_Instr& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const sc_bv<206>& __data) {
            return __data.get_bit(valid_s);
        }
        static sc_bv<128> get_instrs (const sc_bv<206>& __data) {
            return __data.range(instrs_s + instrs_w - 1, instrs_s);
        }
        static uint32_t get_predTarget (const sc_bv<206>& __data) {
            return __data.range(predTarget_s + predTarget_w - 1, predTarget_s).to_uint64();
        }
        static bool get_predTaken (const sc_bv<206>& __data) {
            return __data.get_bit(predTaken_s);
        }
        static uint32_t get_predPos (const sc_bv<206>& __data) {
            return __data.range(predPos_s + predPos_w - 1, predPos_s).to_uint64();
        }
        static uint32_t get_lastValid (const sc_bv<206>& __data) {
            return __data.range(lastValid_s + lastValid_w - 1, lastValid_s).to_uint64();
        }
        static uint32_t get_firstValid (const sc_bv<206>& __data) {
            return __data.range(firstValid_s + firstValid_w - 1, firstValid_s).to_uint64();
        }
        static IFetchFault get_fetchFault (const sc_bv<206>& __data) {
            return IFetchFault(__data.range(fetchFault_s + fetchFault_w - 1, fetchFault_s).to_uint64());
        }
        static uint32_t get_fetchID (const sc_bv<206>& __data) {
            return __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
        }
        static uint32_t get_pc (const sc_bv<206>& __data) {
            return __data.range(pc_s + pc_w - 1, pc_s).to_uint64();
        }
    };

    struct PD_Instr {
        bool valid;
        bool is16bit;
        IFetchFault fetchFault;
        uint32_t fetchID;
        bool predInvalid;
        bool predTaken;
        bool targetIsRetAddr;
        uint32_t predTarget;
        uint32_t fetchPredOffs;
        uint32_t fetchStartOffs;
        uint32_t pc;
        uint32_t instr;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t is16bit_s = 1;
        static constexpr size_t is16bit_w = 1;
        static constexpr size_t fetchFault_s = 2;
        static constexpr size_t fetchFault_w = 2;
        static constexpr size_t fetchID_s = 4;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t predInvalid_s = 10;
        static constexpr size_t predInvalid_w = 1;
        static constexpr size_t predTaken_s = 11;
        static constexpr size_t predTaken_w = 1;
        static constexpr size_t targetIsRetAddr_s = 12;
        static constexpr size_t targetIsRetAddr_w = 1;
        static constexpr size_t predTarget_s = 13;
        static constexpr size_t predTarget_w = 31;
        static constexpr size_t fetchPredOffs_s = 44;
        static constexpr size_t fetchPredOffs_w = 3;
        static constexpr size_t fetchStartOffs_s = 47;
        static constexpr size_t fetchStartOffs_w = 3;
        static constexpr size_t pc_s = 50;
        static constexpr size_t pc_w = 31;
        static constexpr size_t instr_s = 81;
        static constexpr size_t instr_w = 32;
        static constexpr size_t _size = 113;

        PD_Instr() = default;

        PD_Instr(const sc_bv<113>& __data) {
            valid = __data.get_bit(valid_s);
            is16bit = __data.get_bit(is16bit_s);
            fetchFault = IFetchFault(__data.range(fetchFault_s + fetchFault_w - 1, fetchFault_s).to_uint64());
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            predInvalid = __data.get_bit(predInvalid_s);
            predTaken = __data.get_bit(predTaken_s);
            targetIsRetAddr = __data.get_bit(targetIsRetAddr_s);
            predTarget = __data.range(predTarget_s + predTarget_w - 1, predTarget_s).to_uint64();
            fetchPredOffs = __data.range(fetchPredOffs_s + fetchPredOffs_w - 1, fetchPredOffs_s).to_uint64();
            fetchStartOffs = __data.range(fetchStartOffs_s + fetchStartOffs_w - 1, fetchStartOffs_s).to_uint64();
            pc = __data.range(pc_s + pc_w - 1, pc_s).to_uint64();
            instr = __data.range(instr_s + instr_w - 1, instr_s).to_uint64();
        }

        operator sc_bv<113>() const {
            auto ret = sc_bv<113>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(is16bit_s, is16bit);
            ret.range(fetchFault_s + fetchFault_w - 1, fetchFault_s) = fetchFault;
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.set_bit(predInvalid_s, predInvalid);
            ret.set_bit(predTaken_s, predTaken);
            ret.set_bit(targetIsRetAddr_s, targetIsRetAddr);
            ret.range(predTarget_s + predTarget_w - 1, predTarget_s) = predTarget;
            ret.range(fetchPredOffs_s + fetchPredOffs_w - 1, fetchPredOffs_s) = fetchPredOffs;
            ret.range(fetchStartOffs_s + fetchStartOffs_w - 1, fetchStartOffs_s) = fetchStartOffs;
            ret.range(pc_s + pc_w - 1, pc_s) = pc;
            ret.range(instr_s + instr_w - 1, instr_s) = instr;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " is16bit" << " = " << is16bit;
            ss << " fetchFault" << " = " << fetchFault;
            ss << " fetchID" << " = " << fetchID;
            ss << " predInvalid" << " = " << predInvalid;
            ss << " predTaken" << " = " << predTaken;
            ss << " targetIsRetAddr" << " = " << targetIsRetAddr;
            ss << " predTarget" << " = " << predTarget;
            ss << " fetchPredOffs" << " = " << fetchPredOffs;
            ss << " fetchStartOffs" << " = " << fetchStartOffs;
            ss << " pc" << " = " << pc;
            ss << " instr" << " = " << instr;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const PD_Instr& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const sc_bv<113>& __data) {
            return __data.get_bit(valid_s);
        }
        static bool get_is16bit (const sc_bv<113>& __data) {
            return __data.get_bit(is16bit_s);
        }
        static IFetchFault get_fetchFault (const sc_bv<113>& __data) {
            return IFetchFault(__data.range(fetchFault_s + fetchFault_w - 1, fetchFault_s).to_uint64());
        }
        static uint32_t get_fetchID (const sc_bv<113>& __data) {
            return __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
        }
        static bool get_predInvalid (const sc_bv<113>& __data) {
            return __data.get_bit(predInvalid_s);
        }
        static bool get_predTaken (const sc_bv<113>& __data) {
            return __data.get_bit(predTaken_s);
        }
        static bool get_targetIsRetAddr (const sc_bv<113>& __data) {
            return __data.get_bit(targetIsRetAddr_s);
        }
        static uint32_t get_predTarget (const sc_bv<113>& __data) {
            return __data.range(predTarget_s + predTarget_w - 1, predTarget_s).to_uint64();
        }
        static uint32_t get_fetchPredOffs (const sc_bv<113>& __data) {
            return __data.range(fetchPredOffs_s + fetchPredOffs_w - 1, fetchPredOffs_s).to_uint64();
        }
        static uint32_t get_fetchStartOffs (const sc_bv<113>& __data) {
            return __data.range(fetchStartOffs_s + fetchStartOffs_w - 1, fetchStartOffs_s).to_uint64();
        }
        static uint32_t get_pc (const sc_bv<113>& __data) {
            return __data.range(pc_s + pc_w - 1, pc_s).to_uint64();
        }
        static uint32_t get_instr (const sc_bv<113>& __data) {
            return __data.range(instr_s + instr_w - 1, instr_s).to_uint64();
        }
    };

    struct D_UOp {
        bool valid;
        bool compressed;
        uint32_t fetchOffs;
        uint32_t fetchID;
        FuncUnit fu;
        uint32_t opcode;
        uint32_t rd;
        bool immB;
        uint32_t rs2;
        uint32_t rs1;
        uint32_t imm12;
        uint32_t imm;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t compressed_s = 1;
        static constexpr size_t compressed_w = 1;
        static constexpr size_t fetchOffs_s = 2;
        static constexpr size_t fetchOffs_w = 3;
        static constexpr size_t fetchID_s = 5;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t fu_s = 11;
        static constexpr size_t fu_w = 4;
        static constexpr size_t opcode_s = 15;
        static constexpr size_t opcode_w = 6;
        static constexpr size_t rd_s = 21;
        static constexpr size_t rd_w = 5;
        static constexpr size_t immB_s = 26;
        static constexpr size_t immB_w = 1;
        static constexpr size_t rs2_s = 27;
        static constexpr size_t rs2_w = 5;
        static constexpr size_t rs1_s = 32;
        static constexpr size_t rs1_w = 5;
        static constexpr size_t imm12_s = 37;
        static constexpr size_t imm12_w = 12;
        static constexpr size_t imm_s = 49;
        static constexpr size_t imm_w = 32;
        static constexpr size_t _size = 81;

        D_UOp() = default;

        D_UOp(const sc_bv<81>& __data) {
            valid = __data.get_bit(valid_s);
            compressed = __data.get_bit(compressed_s);
            fetchOffs = __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            fu = FuncUnit(__data.range(fu_s + fu_w - 1, fu_s).to_uint64());
            opcode = __data.range(opcode_s + opcode_w - 1, opcode_s).to_uint64();
            rd = __data.range(rd_s + rd_w - 1, rd_s).to_uint64();
            immB = __data.get_bit(immB_s);
            rs2 = __data.range(rs2_s + rs2_w - 1, rs2_s).to_uint64();
            rs1 = __data.range(rs1_s + rs1_w - 1, rs1_s).to_uint64();
            imm12 = __data.range(imm12_s + imm12_w - 1, imm12_s).to_uint64();
            imm = __data.range(imm_s + imm_w - 1, imm_s).to_uint64();
        }

        operator sc_bv<81>() const {
            auto ret = sc_bv<81>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(compressed_s, compressed);
            ret.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s) = fetchOffs;
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.range(fu_s + fu_w - 1, fu_s) = fu;
            ret.range(opcode_s + opcode_w - 1, opcode_s) = opcode;
            ret.range(rd_s + rd_w - 1, rd_s) = rd;
            ret.set_bit(immB_s, immB);
            ret.range(rs2_s + rs2_w - 1, rs2_s) = rs2;
            ret.range(rs1_s + rs1_w - 1, rs1_s) = rs1;
            ret.range(imm12_s + imm12_w - 1, imm12_s) = imm12;
            ret.range(imm_s + imm_w - 1, imm_s) = imm;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " compressed" << " = " << compressed;
            ss << " fetchOffs" << " = " << fetchOffs;
            ss << " fetchID" << " = " << fetchID;
            ss << " fu" << " = " << fu;
            ss << " opcode" << " = " << opcode;
            ss << " rd" << " = " << rd;
            ss << " immB" << " = " << immB;
            ss << " rs2" << " = " << rs2;
            ss << " rs1" << " = " << rs1;
            ss << " imm12" << " = " << imm12;
            ss << " imm" << " = " << imm;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const D_UOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const sc_bv<81>& __data) {
            return __data.get_bit(valid_s);
        }
        static bool get_compressed (const sc_bv<81>& __data) {
            return __data.get_bit(compressed_s);
        }
        static uint32_t get_fetchOffs (const sc_bv<81>& __data) {
            return __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
        }
        static uint32_t get_fetchID (const sc_bv<81>& __data) {
            return __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
        }
        static FuncUnit get_fu (const sc_bv<81>& __data) {
            return FuncUnit(__data.range(fu_s + fu_w - 1, fu_s).to_uint64());
        }
        static uint32_t get_opcode (const sc_bv<81>& __data) {
            return __data.range(opcode_s + opcode_w - 1, opcode_s).to_uint64();
        }
        static uint32_t get_rd (const sc_bv<81>& __data) {
            return __data.range(rd_s + rd_w - 1, rd_s).to_uint64();
        }
        static bool get_immB (const sc_bv<81>& __data) {
            return __data.get_bit(immB_s);
        }
        static uint32_t get_rs2 (const sc_bv<81>& __data) {
            return __data.range(rs2_s + rs2_w - 1, rs2_s).to_uint64();
        }
        static uint32_t get_rs1 (const sc_bv<81>& __data) {
            return __data.range(rs1_s + rs1_w - 1, rs1_s).to_uint64();
        }
        static uint32_t get_imm12 (const sc_bv<81>& __data) {
            return __data.range(imm12_s + imm12_w - 1, imm12_s).to_uint64();
        }
        static uint32_t get_imm (const sc_bv<81>& __data) {
            return __data.range(imm_s + imm_w - 1, imm_s).to_uint64();
        }
    };

    struct R_UOp {
        bool valid;
        uint32_t validIQ;
        bool compressed;
        FuncUnit fu;
        uint32_t loadSqN;
        uint32_t storeSqN;
        uint32_t fetchOffs;
        uint32_t fetchID;
        uint32_t opcode;
        uint32_t rd;
        uint32_t tagDst;
        uint32_t sqN;
        uint32_t tagC;
        bool availC;
        bool immB;
        uint32_t tagB;
        bool availB;
        uint32_t tagA;
        bool availA;
        uint32_t imm12;
        uint32_t imm;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t validIQ_s = 1;
        static constexpr size_t validIQ_w = 7;
        static constexpr size_t compressed_s = 8;
        static constexpr size_t compressed_w = 1;
        static constexpr size_t fu_s = 9;
        static constexpr size_t fu_w = 4;
        static constexpr size_t loadSqN_s = 13;
        static constexpr size_t loadSqN_w = 7;
        static constexpr size_t storeSqN_s = 20;
        static constexpr size_t storeSqN_w = 7;
        static constexpr size_t fetchOffs_s = 27;
        static constexpr size_t fetchOffs_w = 3;
        static constexpr size_t fetchID_s = 30;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t opcode_s = 36;
        static constexpr size_t opcode_w = 6;
        static constexpr size_t rd_s = 42;
        static constexpr size_t rd_w = 5;
        static constexpr size_t tagDst_s = 47;
        static constexpr size_t tagDst_w = 7;
        static constexpr size_t sqN_s = 54;
        static constexpr size_t sqN_w = 7;
        static constexpr size_t tagC_s = 61;
        static constexpr size_t tagC_w = 7;
        static constexpr size_t availC_s = 68;
        static constexpr size_t availC_w = 1;
        static constexpr size_t immB_s = 69;
        static constexpr size_t immB_w = 1;
        static constexpr size_t tagB_s = 70;
        static constexpr size_t tagB_w = 7;
        static constexpr size_t availB_s = 77;
        static constexpr size_t availB_w = 1;
        static constexpr size_t tagA_s = 78;
        static constexpr size_t tagA_w = 7;
        static constexpr size_t availA_s = 85;
        static constexpr size_t availA_w = 1;
        static constexpr size_t imm12_s = 86;
        static constexpr size_t imm12_w = 12;
        static constexpr size_t imm_s = 98;
        static constexpr size_t imm_w = 32;
        static constexpr size_t _size = 130;

        R_UOp() = default;

        R_UOp(const sc_bv<130>& __data) {
            valid = __data.get_bit(valid_s);
            validIQ = __data.range(validIQ_s + validIQ_w - 1, validIQ_s).to_uint64();
            compressed = __data.get_bit(compressed_s);
            fu = FuncUnit(__data.range(fu_s + fu_w - 1, fu_s).to_uint64());
            loadSqN = __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
            storeSqN = __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
            fetchOffs = __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            opcode = __data.range(opcode_s + opcode_w - 1, opcode_s).to_uint64();
            rd = __data.range(rd_s + rd_w - 1, rd_s).to_uint64();
            tagDst = __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
            sqN = __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
            tagC = __data.range(tagC_s + tagC_w - 1, tagC_s).to_uint64();
            availC = __data.get_bit(availC_s);
            immB = __data.get_bit(immB_s);
            tagB = __data.range(tagB_s + tagB_w - 1, tagB_s).to_uint64();
            availB = __data.get_bit(availB_s);
            tagA = __data.range(tagA_s + tagA_w - 1, tagA_s).to_uint64();
            availA = __data.get_bit(availA_s);
            imm12 = __data.range(imm12_s + imm12_w - 1, imm12_s).to_uint64();
            imm = __data.range(imm_s + imm_w - 1, imm_s).to_uint64();
        }

        operator sc_bv<130>() const {
            auto ret = sc_bv<130>();
            ret.set_bit(valid_s, valid);
            ret.range(validIQ_s + validIQ_w - 1, validIQ_s) = validIQ;
            ret.set_bit(compressed_s, compressed);
            ret.range(fu_s + fu_w - 1, fu_s) = fu;
            ret.range(loadSqN_s + loadSqN_w - 1, loadSqN_s) = loadSqN;
            ret.range(storeSqN_s + storeSqN_w - 1, storeSqN_s) = storeSqN;
            ret.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s) = fetchOffs;
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.range(opcode_s + opcode_w - 1, opcode_s) = opcode;
            ret.range(rd_s + rd_w - 1, rd_s) = rd;
            ret.range(tagDst_s + tagDst_w - 1, tagDst_s) = tagDst;
            ret.range(sqN_s + sqN_w - 1, sqN_s) = sqN;
            ret.range(tagC_s + tagC_w - 1, tagC_s) = tagC;
            ret.set_bit(availC_s, availC);
            ret.set_bit(immB_s, immB);
            ret.range(tagB_s + tagB_w - 1, tagB_s) = tagB;
            ret.set_bit(availB_s, availB);
            ret.range(tagA_s + tagA_w - 1, tagA_s) = tagA;
            ret.set_bit(availA_s, availA);
            ret.range(imm12_s + imm12_w - 1, imm12_s) = imm12;
            ret.range(imm_s + imm_w - 1, imm_s) = imm;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " validIQ" << " = " << validIQ;
            ss << " compressed" << " = " << compressed;
            ss << " fu" << " = " << fu;
            ss << " loadSqN" << " = " << loadSqN;
            ss << " storeSqN" << " = " << storeSqN;
            ss << " fetchOffs" << " = " << fetchOffs;
            ss << " fetchID" << " = " << fetchID;
            ss << " opcode" << " = " << opcode;
            ss << " rd" << " = " << rd;
            ss << " tagDst" << " = " << tagDst;
            ss << " sqN" << " = " << sqN;
            ss << " tagC" << " = " << tagC;
            ss << " availC" << " = " << availC;
            ss << " immB" << " = " << immB;
            ss << " tagB" << " = " << tagB;
            ss << " availB" << " = " << availB;
            ss << " tagA" << " = " << tagA;
            ss << " availA" << " = " << availA;
            ss << " imm12" << " = " << imm12;
            ss << " imm" << " = " << imm;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const R_UOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const sc_bv<130>& __data) {
            return __data.get_bit(valid_s);
        }
        static uint32_t get_validIQ (const sc_bv<130>& __data) {
            return __data.range(validIQ_s + validIQ_w - 1, validIQ_s).to_uint64();
        }
        static bool get_compressed (const sc_bv<130>& __data) {
            return __data.get_bit(compressed_s);
        }
        static FuncUnit get_fu (const sc_bv<130>& __data) {
            return FuncUnit(__data.range(fu_s + fu_w - 1, fu_s).to_uint64());
        }
        static uint32_t get_loadSqN (const sc_bv<130>& __data) {
            return __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
        }
        static uint32_t get_storeSqN (const sc_bv<130>& __data) {
            return __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
        }
        static uint32_t get_fetchOffs (const sc_bv<130>& __data) {
            return __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
        }
        static uint32_t get_fetchID (const sc_bv<130>& __data) {
            return __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
        }
        static uint32_t get_opcode (const sc_bv<130>& __data) {
            return __data.range(opcode_s + opcode_w - 1, opcode_s).to_uint64();
        }
        static uint32_t get_rd (const sc_bv<130>& __data) {
            return __data.range(rd_s + rd_w - 1, rd_s).to_uint64();
        }
        static uint32_t get_tagDst (const sc_bv<130>& __data) {
            return __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
        }
        static uint32_t get_sqN (const sc_bv<130>& __data) {
            return __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
        }
        static uint32_t get_tagC (const sc_bv<130>& __data) {
            return __data.range(tagC_s + tagC_w - 1, tagC_s).to_uint64();
        }
        static bool get_availC (const sc_bv<130>& __data) {
            return __data.get_bit(availC_s);
        }
        static bool get_immB (const sc_bv<130>& __data) {
            return __data.get_bit(immB_s);
        }
        static uint32_t get_tagB (const sc_bv<130>& __data) {
            return __data.range(tagB_s + tagB_w - 1, tagB_s).to_uint64();
        }
        static bool get_availB (const sc_bv<130>& __data) {
            return __data.get_bit(availB_s);
        }
        static uint32_t get_tagA (const sc_bv<130>& __data) {
            return __data.range(tagA_s + tagA_w - 1, tagA_s).to_uint64();
        }
        static bool get_availA (const sc_bv<130>& __data) {
            return __data.get_bit(availA_s);
        }
        static uint32_t get_imm12 (const sc_bv<130>& __data) {
            return __data.range(imm12_s + imm12_w - 1, imm12_s).to_uint64();
        }
        static uint32_t get_imm (const sc_bv<130>& __data) {
            return __data.range(imm_s + imm_w - 1, imm_s).to_uint64();
        }
    };

    struct IS_UOp {
        bool valid;
        bool compressed;
        FuncUnit fu;
        uint32_t loadSqN;
        uint32_t storeSqN;
        uint32_t fetchOffs;
        uint32_t fetchID;
        uint32_t opcode;
        uint32_t tagDst;
        uint32_t sqN;
        bool immB;
        uint32_t tagB;
        bool availB;
        uint32_t tagA;
        bool availA;
        uint32_t imm12;
        uint32_t imm;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t compressed_s = 1;
        static constexpr size_t compressed_w = 1;
        static constexpr size_t fu_s = 2;
        static constexpr size_t fu_w = 4;
        static constexpr size_t loadSqN_s = 6;
        static constexpr size_t loadSqN_w = 7;
        static constexpr size_t storeSqN_s = 13;
        static constexpr size_t storeSqN_w = 7;
        static constexpr size_t fetchOffs_s = 20;
        static constexpr size_t fetchOffs_w = 3;
        static constexpr size_t fetchID_s = 23;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t opcode_s = 29;
        static constexpr size_t opcode_w = 6;
        static constexpr size_t tagDst_s = 35;
        static constexpr size_t tagDst_w = 7;
        static constexpr size_t sqN_s = 42;
        static constexpr size_t sqN_w = 7;
        static constexpr size_t immB_s = 49;
        static constexpr size_t immB_w = 1;
        static constexpr size_t tagB_s = 50;
        static constexpr size_t tagB_w = 7;
        static constexpr size_t availB_s = 57;
        static constexpr size_t availB_w = 1;
        static constexpr size_t tagA_s = 58;
        static constexpr size_t tagA_w = 7;
        static constexpr size_t availA_s = 65;
        static constexpr size_t availA_w = 1;
        static constexpr size_t imm12_s = 66;
        static constexpr size_t imm12_w = 12;
        static constexpr size_t imm_s = 78;
        static constexpr size_t imm_w = 32;
        static constexpr size_t _size = 110;

        IS_UOp() = default;

        IS_UOp(const sc_bv<110>& __data) {
            valid = __data.get_bit(valid_s);
            compressed = __data.get_bit(compressed_s);
            fu = FuncUnit(__data.range(fu_s + fu_w - 1, fu_s).to_uint64());
            loadSqN = __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
            storeSqN = __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
            fetchOffs = __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            opcode = __data.range(opcode_s + opcode_w - 1, opcode_s).to_uint64();
            tagDst = __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
            sqN = __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
            immB = __data.get_bit(immB_s);
            tagB = __data.range(tagB_s + tagB_w - 1, tagB_s).to_uint64();
            availB = __data.get_bit(availB_s);
            tagA = __data.range(tagA_s + tagA_w - 1, tagA_s).to_uint64();
            availA = __data.get_bit(availA_s);
            imm12 = __data.range(imm12_s + imm12_w - 1, imm12_s).to_uint64();
            imm = __data.range(imm_s + imm_w - 1, imm_s).to_uint64();
        }

        operator sc_bv<110>() const {
            auto ret = sc_bv<110>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(compressed_s, compressed);
            ret.range(fu_s + fu_w - 1, fu_s) = fu;
            ret.range(loadSqN_s + loadSqN_w - 1, loadSqN_s) = loadSqN;
            ret.range(storeSqN_s + storeSqN_w - 1, storeSqN_s) = storeSqN;
            ret.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s) = fetchOffs;
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.range(opcode_s + opcode_w - 1, opcode_s) = opcode;
            ret.range(tagDst_s + tagDst_w - 1, tagDst_s) = tagDst;
            ret.range(sqN_s + sqN_w - 1, sqN_s) = sqN;
            ret.set_bit(immB_s, immB);
            ret.range(tagB_s + tagB_w - 1, tagB_s) = tagB;
            ret.set_bit(availB_s, availB);
            ret.range(tagA_s + tagA_w - 1, tagA_s) = tagA;
            ret.set_bit(availA_s, availA);
            ret.range(imm12_s + imm12_w - 1, imm12_s) = imm12;
            ret.range(imm_s + imm_w - 1, imm_s) = imm;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " compressed" << " = " << compressed;
            ss << " fu" << " = " << fu;
            ss << " loadSqN" << " = " << loadSqN;
            ss << " storeSqN" << " = " << storeSqN;
            ss << " fetchOffs" << " = " << fetchOffs;
            ss << " fetchID" << " = " << fetchID;
            ss << " opcode" << " = " << opcode;
            ss << " tagDst" << " = " << tagDst;
            ss << " sqN" << " = " << sqN;
            ss << " immB" << " = " << immB;
            ss << " tagB" << " = " << tagB;
            ss << " availB" << " = " << availB;
            ss << " tagA" << " = " << tagA;
            ss << " availA" << " = " << availA;
            ss << " imm12" << " = " << imm12;
            ss << " imm" << " = " << imm;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const IS_UOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const sc_bv<110>& __data) {
            return __data.get_bit(valid_s);
        }
        static bool get_compressed (const sc_bv<110>& __data) {
            return __data.get_bit(compressed_s);
        }
        static FuncUnit get_fu (const sc_bv<110>& __data) {
            return FuncUnit(__data.range(fu_s + fu_w - 1, fu_s).to_uint64());
        }
        static uint32_t get_loadSqN (const sc_bv<110>& __data) {
            return __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
        }
        static uint32_t get_storeSqN (const sc_bv<110>& __data) {
            return __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
        }
        static uint32_t get_fetchOffs (const sc_bv<110>& __data) {
            return __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
        }
        static uint32_t get_fetchID (const sc_bv<110>& __data) {
            return __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
        }
        static uint32_t get_opcode (const sc_bv<110>& __data) {
            return __data.range(opcode_s + opcode_w - 1, opcode_s).to_uint64();
        }
        static uint32_t get_tagDst (const sc_bv<110>& __data) {
            return __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
        }
        static uint32_t get_sqN (const sc_bv<110>& __data) {
            return __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
        }
        static bool get_immB (const sc_bv<110>& __data) {
            return __data.get_bit(immB_s);
        }
        static uint32_t get_tagB (const sc_bv<110>& __data) {
            return __data.range(tagB_s + tagB_w - 1, tagB_s).to_uint64();
        }
        static bool get_availB (const sc_bv<110>& __data) {
            return __data.get_bit(availB_s);
        }
        static uint32_t get_tagA (const sc_bv<110>& __data) {
            return __data.range(tagA_s + tagA_w - 1, tagA_s).to_uint64();
        }
        static bool get_availA (const sc_bv<110>& __data) {
            return __data.get_bit(availA_s);
        }
        static uint32_t get_imm12 (const sc_bv<110>& __data) {
            return __data.range(imm12_s + imm12_w - 1, imm12_s).to_uint64();
        }
        static uint32_t get_imm (const sc_bv<110>& __data) {
            return __data.range(imm_s + imm_w - 1, imm_s).to_uint64();
        }
    };

    struct EX_UOp {
        bool valid;
        bool compressed;
        FuncUnit fu;
        uint32_t loadSqN;
        uint32_t storeSqN;
        BranchPredInfo bpi;
        uint32_t fetchID;
        uint32_t sqN;
        uint32_t tagDst;
        uint32_t opcode;
        uint32_t imm;
        uint32_t fetchPredOffs;
        uint32_t fetchStartOffs;
        uint32_t fetchOffs;
        uint32_t pc;
        uint32_t srcB;
        uint32_t srcA;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t compressed_s = 1;
        static constexpr size_t compressed_w = 1;
        static constexpr size_t fu_s = 2;
        static constexpr size_t fu_w = 4;
        static constexpr size_t loadSqN_s = 6;
        static constexpr size_t loadSqN_w = 7;
        static constexpr size_t storeSqN_s = 13;
        static constexpr size_t storeSqN_w = 7;
        static constexpr size_t bpi_s = 20;
        static constexpr size_t bpi_w = 1;
        static constexpr size_t fetchID_s = 21;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t sqN_s = 27;
        static constexpr size_t sqN_w = 7;
        static constexpr size_t tagDst_s = 34;
        static constexpr size_t tagDst_w = 7;
        static constexpr size_t opcode_s = 41;
        static constexpr size_t opcode_w = 6;
        static constexpr size_t imm_s = 47;
        static constexpr size_t imm_w = 32;
        static constexpr size_t fetchPredOffs_s = 79;
        static constexpr size_t fetchPredOffs_w = 3;
        static constexpr size_t fetchStartOffs_s = 82;
        static constexpr size_t fetchStartOffs_w = 3;
        static constexpr size_t fetchOffs_s = 85;
        static constexpr size_t fetchOffs_w = 3;
        static constexpr size_t pc_s = 88;
        static constexpr size_t pc_w = 32;
        static constexpr size_t srcB_s = 120;
        static constexpr size_t srcB_w = 32;
        static constexpr size_t srcA_s = 152;
        static constexpr size_t srcA_w = 32;
        static constexpr size_t _size = 184;

        EX_UOp() = default;

        EX_UOp(const sc_bv<184>& __data) {
            valid = __data.get_bit(valid_s);
            compressed = __data.get_bit(compressed_s);
            fu = FuncUnit(__data.range(fu_s + fu_w - 1, fu_s).to_uint64());
            loadSqN = __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
            storeSqN = __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
            bpi = BranchPredInfo(__data.get_bit(bpi_s));
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            sqN = __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
            tagDst = __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
            opcode = __data.range(opcode_s + opcode_w - 1, opcode_s).to_uint64();
            imm = __data.range(imm_s + imm_w - 1, imm_s).to_uint64();
            fetchPredOffs = __data.range(fetchPredOffs_s + fetchPredOffs_w - 1, fetchPredOffs_s).to_uint64();
            fetchStartOffs = __data.range(fetchStartOffs_s + fetchStartOffs_w - 1, fetchStartOffs_s).to_uint64();
            fetchOffs = __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
            pc = __data.range(pc_s + pc_w - 1, pc_s).to_uint64();
            srcB = __data.range(srcB_s + srcB_w - 1, srcB_s).to_uint64();
            srcA = __data.range(srcA_s + srcA_w - 1, srcA_s).to_uint64();
        }

        operator sc_bv<184>() const {
            auto ret = sc_bv<184>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(compressed_s, compressed);
            ret.range(fu_s + fu_w - 1, fu_s) = fu;
            ret.range(loadSqN_s + loadSqN_w - 1, loadSqN_s) = loadSqN;
            ret.range(storeSqN_s + storeSqN_w - 1, storeSqN_s) = storeSqN;
            ret.range(bpi_s + bpi_w - 1, bpi_s) = bpi;
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.range(sqN_s + sqN_w - 1, sqN_s) = sqN;
            ret.range(tagDst_s + tagDst_w - 1, tagDst_s) = tagDst;
            ret.range(opcode_s + opcode_w - 1, opcode_s) = opcode;
            ret.range(imm_s + imm_w - 1, imm_s) = imm;
            ret.range(fetchPredOffs_s + fetchPredOffs_w - 1, fetchPredOffs_s) = fetchPredOffs;
            ret.range(fetchStartOffs_s + fetchStartOffs_w - 1, fetchStartOffs_s) = fetchStartOffs;
            ret.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s) = fetchOffs;
            ret.range(pc_s + pc_w - 1, pc_s) = pc;
            ret.range(srcB_s + srcB_w - 1, srcB_s) = srcB;
            ret.range(srcA_s + srcA_w - 1, srcA_s) = srcA;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " compressed" << " = " << compressed;
            ss << " fu" << " = " << fu;
            ss << " loadSqN" << " = " << loadSqN;
            ss << " storeSqN" << " = " << storeSqN;
            ss << " bpi" << " = " << bpi.to_string();
            ss << " fetchID" << " = " << fetchID;
            ss << " sqN" << " = " << sqN;
            ss << " tagDst" << " = " << tagDst;
            ss << " opcode" << " = " << opcode;
            ss << " imm" << " = " << imm;
            ss << " fetchPredOffs" << " = " << fetchPredOffs;
            ss << " fetchStartOffs" << " = " << fetchStartOffs;
            ss << " fetchOffs" << " = " << fetchOffs;
            ss << " pc" << " = " << pc;
            ss << " srcB" << " = " << srcB;
            ss << " srcA" << " = " << srcA;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const EX_UOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const sc_bv<184>& __data) {
            return __data.get_bit(valid_s);
        }
        static bool get_compressed (const sc_bv<184>& __data) {
            return __data.get_bit(compressed_s);
        }
        static FuncUnit get_fu (const sc_bv<184>& __data) {
            return FuncUnit(__data.range(fu_s + fu_w - 1, fu_s).to_uint64());
        }
        static uint32_t get_loadSqN (const sc_bv<184>& __data) {
            return __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
        }
        static uint32_t get_storeSqN (const sc_bv<184>& __data) {
            return __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
        }
        static BranchPredInfo get_bpi (const sc_bv<184>& __data) {
            return BranchPredInfo(__data.get_bit(bpi_s));
        }
        static uint32_t get_fetchID (const sc_bv<184>& __data) {
            return __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
        }
        static uint32_t get_sqN (const sc_bv<184>& __data) {
            return __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
        }
        static uint32_t get_tagDst (const sc_bv<184>& __data) {
            return __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
        }
        static uint32_t get_opcode (const sc_bv<184>& __data) {
            return __data.range(opcode_s + opcode_w - 1, opcode_s).to_uint64();
        }
        static uint32_t get_imm (const sc_bv<184>& __data) {
            return __data.range(imm_s + imm_w - 1, imm_s).to_uint64();
        }
        static uint32_t get_fetchPredOffs (const sc_bv<184>& __data) {
            return __data.range(fetchPredOffs_s + fetchPredOffs_w - 1, fetchPredOffs_s).to_uint64();
        }
        static uint32_t get_fetchStartOffs (const sc_bv<184>& __data) {
            return __data.range(fetchStartOffs_s + fetchStartOffs_w - 1, fetchStartOffs_s).to_uint64();
        }
        static uint32_t get_fetchOffs (const sc_bv<184>& __data) {
            return __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
        }
        static uint32_t get_pc (const sc_bv<184>& __data) {
            return __data.range(pc_s + pc_w - 1, pc_s).to_uint64();
        }
        static uint32_t get_srcB (const sc_bv<184>& __data) {
            return __data.range(srcB_s + srcB_w - 1, srcB_s).to_uint64();
        }
        static uint32_t get_srcA (const sc_bv<184>& __data) {
            return __data.range(srcA_s + srcA_w - 1, srcA_s).to_uint64();
        }
    };

    struct RES_UOp {
        bool valid;
        bool doNotCommit;
        Flags flags;
        uint32_t sqN;
        uint32_t tagDst;
        uint32_t result;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t doNotCommit_s = 1;
        static constexpr size_t doNotCommit_w = 1;
        static constexpr size_t flags_s = 2;
        static constexpr size_t flags_w = 4;
        static constexpr size_t sqN_s = 6;
        static constexpr size_t sqN_w = 7;
        static constexpr size_t tagDst_s = 13;
        static constexpr size_t tagDst_w = 7;
        static constexpr size_t result_s = 20;
        static constexpr size_t result_w = 32;
        static constexpr size_t _size = 52;

        RES_UOp() = default;

        RES_UOp(const uint64_t& __data) {
            valid = (__data >> valid_s) & (~0ULL >> (64 - 1));
            doNotCommit = (__data >> doNotCommit_s) & (~0ULL >> (64 - 1));
            flags = Flags((__data >> flags_s) & (~0ULL >> (64 - 4)));
            sqN = (__data >> sqN_s) & (~0ULL >> (64 - 7));
            tagDst = (__data >> tagDst_s) & (~0ULL >> (64 - 7));
            result = (__data >> result_s) & (~0ULL >> (64 - 32));
        }

        RES_UOp(const sc_bv<52>& __data) {
            valid = __data.get_bit(valid_s);
            doNotCommit = __data.get_bit(doNotCommit_s);
            flags = Flags(__data.range(flags_s + flags_w - 1, flags_s).to_uint64());
            sqN = __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
            tagDst = __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
            result = __data.range(result_s + result_w - 1, result_s).to_uint64();
        }

        operator uint64_t() const {
            uint64_t ret = 0;
            ret |= static_cast<uint64_t>(valid) << valid_s;
            ret |= static_cast<uint64_t>(doNotCommit) << doNotCommit_s;
            ret |= static_cast<uint64_t>(flags) << flags_s;
            ret |= static_cast<uint64_t>(sqN) << sqN_s;
            ret |= static_cast<uint64_t>(tagDst) << tagDst_s;
            ret |= static_cast<uint64_t>(result) << result_s;
            return ret;
        }

        operator sc_bv<52>() const {
            auto ret = sc_bv<52>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(doNotCommit_s, doNotCommit);
            ret.range(flags_s + flags_w - 1, flags_s) = flags;
            ret.range(sqN_s + sqN_w - 1, sqN_s) = sqN;
            ret.range(tagDst_s + tagDst_w - 1, tagDst_s) = tagDst;
            ret.range(result_s + result_w - 1, result_s) = result;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " doNotCommit" << " = " << doNotCommit;
            ss << " flags" << " = " << flags;
            ss << " sqN" << " = " << sqN;
            ss << " tagDst" << " = " << tagDst;
            ss << " result" << " = " << result;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const RES_UOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const uint64_t& __data) {
            return (__data >> valid_s) & (~0ULL >> (64 - 1));
        }
        static bool get_doNotCommit (const uint64_t& __data) {
            return (__data >> doNotCommit_s) & (~0ULL >> (64 - 1));
        }
        static Flags get_flags (const uint64_t& __data) {
            return Flags((__data >> flags_s) & (~0ULL >> (64 - 4)));
        }
        static uint32_t get_sqN (const uint64_t& __data) {
            return (__data >> sqN_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_tagDst (const uint64_t& __data) {
            return (__data >> tagDst_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_result (const uint64_t& __data) {
            return (__data >> result_s) & (~0ULL >> (64 - 32));
        }
    };

    struct FlagsUOp {
        bool valid;
        bool doNotCommit;
        Flags flags;
        uint32_t sqN;
        uint32_t tagDst;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t doNotCommit_s = 1;
        static constexpr size_t doNotCommit_w = 1;
        static constexpr size_t flags_s = 2;
        static constexpr size_t flags_w = 4;
        static constexpr size_t sqN_s = 6;
        static constexpr size_t sqN_w = 7;
        static constexpr size_t tagDst_s = 13;
        static constexpr size_t tagDst_w = 7;
        static constexpr size_t _size = 20;

        FlagsUOp() = default;

        FlagsUOp(const uint32_t& __data) {
            valid = (__data >> valid_s) & (~0ULL >> (64 - 1));
            doNotCommit = (__data >> doNotCommit_s) & (~0ULL >> (64 - 1));
            flags = Flags((__data >> flags_s) & (~0ULL >> (64 - 4)));
            sqN = (__data >> sqN_s) & (~0ULL >> (64 - 7));
            tagDst = (__data >> tagDst_s) & (~0ULL >> (64 - 7));
        }

        FlagsUOp(const sc_bv<20>& __data) {
            valid = __data.get_bit(valid_s);
            doNotCommit = __data.get_bit(doNotCommit_s);
            flags = Flags(__data.range(flags_s + flags_w - 1, flags_s).to_uint64());
            sqN = __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
            tagDst = __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
        }

        operator uint32_t() const {
            uint32_t ret = 0;
            ret |= static_cast<uint32_t>(valid) << valid_s;
            ret |= static_cast<uint32_t>(doNotCommit) << doNotCommit_s;
            ret |= static_cast<uint32_t>(flags) << flags_s;
            ret |= static_cast<uint32_t>(sqN) << sqN_s;
            ret |= static_cast<uint32_t>(tagDst) << tagDst_s;
            return ret;
        }

        operator sc_bv<20>() const {
            auto ret = sc_bv<20>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(doNotCommit_s, doNotCommit);
            ret.range(flags_s + flags_w - 1, flags_s) = flags;
            ret.range(sqN_s + sqN_w - 1, sqN_s) = sqN;
            ret.range(tagDst_s + tagDst_w - 1, tagDst_s) = tagDst;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " doNotCommit" << " = " << doNotCommit;
            ss << " flags" << " = " << flags;
            ss << " sqN" << " = " << sqN;
            ss << " tagDst" << " = " << tagDst;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const FlagsUOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const uint32_t& __data) {
            return (__data >> valid_s) & (~0ULL >> (64 - 1));
        }
        static bool get_doNotCommit (const uint32_t& __data) {
            return (__data >> doNotCommit_s) & (~0ULL >> (64 - 1));
        }
        static Flags get_flags (const uint32_t& __data) {
            return Flags((__data >> flags_s) & (~0ULL >> (64 - 4)));
        }
        static uint32_t get_sqN (const uint32_t& __data) {
            return (__data >> sqN_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_tagDst (const uint32_t& __data) {
            return (__data >> tagDst_s) & (~0ULL >> (64 - 7));
        }
    };

    struct ResultUOp {
        bool valid;
        bool doNotCommit;
        uint32_t tagDst;
        uint32_t result;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t doNotCommit_s = 1;
        static constexpr size_t doNotCommit_w = 1;
        static constexpr size_t tagDst_s = 2;
        static constexpr size_t tagDst_w = 7;
        static constexpr size_t result_s = 9;
        static constexpr size_t result_w = 32;
        static constexpr size_t _size = 41;

        ResultUOp() = default;

        ResultUOp(const uint64_t& __data) {
            valid = (__data >> valid_s) & (~0ULL >> (64 - 1));
            doNotCommit = (__data >> doNotCommit_s) & (~0ULL >> (64 - 1));
            tagDst = (__data >> tagDst_s) & (~0ULL >> (64 - 7));
            result = (__data >> result_s) & (~0ULL >> (64 - 32));
        }

        ResultUOp(const sc_bv<41>& __data) {
            valid = __data.get_bit(valid_s);
            doNotCommit = __data.get_bit(doNotCommit_s);
            tagDst = __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
            result = __data.range(result_s + result_w - 1, result_s).to_uint64();
        }

        operator uint64_t() const {
            uint64_t ret = 0;
            ret |= static_cast<uint64_t>(valid) << valid_s;
            ret |= static_cast<uint64_t>(doNotCommit) << doNotCommit_s;
            ret |= static_cast<uint64_t>(tagDst) << tagDst_s;
            ret |= static_cast<uint64_t>(result) << result_s;
            return ret;
        }

        operator sc_bv<41>() const {
            auto ret = sc_bv<41>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(doNotCommit_s, doNotCommit);
            ret.range(tagDst_s + tagDst_w - 1, tagDst_s) = tagDst;
            ret.range(result_s + result_w - 1, result_s) = result;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " doNotCommit" << " = " << doNotCommit;
            ss << " tagDst" << " = " << tagDst;
            ss << " result" << " = " << result;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const ResultUOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const uint64_t& __data) {
            return (__data >> valid_s) & (~0ULL >> (64 - 1));
        }
        static bool get_doNotCommit (const uint64_t& __data) {
            return (__data >> doNotCommit_s) & (~0ULL >> (64 - 1));
        }
        static uint32_t get_tagDst (const uint64_t& __data) {
            return (__data >> tagDst_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_result (const uint64_t& __data) {
            return (__data >> result_s) & (~0ULL >> (64 - 32));
        }
    };

    struct CommitUOp {
        bool valid;
        bool compressed;
        bool branchTaken;
        bool isBranch;
        uint32_t sqN;
        uint32_t tagDst;
        uint32_t rd;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t compressed_s = 1;
        static constexpr size_t compressed_w = 1;
        static constexpr size_t branchTaken_s = 2;
        static constexpr size_t branchTaken_w = 1;
        static constexpr size_t isBranch_s = 3;
        static constexpr size_t isBranch_w = 1;
        static constexpr size_t sqN_s = 4;
        static constexpr size_t sqN_w = 7;
        static constexpr size_t tagDst_s = 11;
        static constexpr size_t tagDst_w = 7;
        static constexpr size_t rd_s = 18;
        static constexpr size_t rd_w = 5;
        static constexpr size_t _size = 23;

        CommitUOp() = default;

        CommitUOp(const uint32_t& __data) {
            valid = (__data >> valid_s) & (~0ULL >> (64 - 1));
            compressed = (__data >> compressed_s) & (~0ULL >> (64 - 1));
            branchTaken = (__data >> branchTaken_s) & (~0ULL >> (64 - 1));
            isBranch = (__data >> isBranch_s) & (~0ULL >> (64 - 1));
            sqN = (__data >> sqN_s) & (~0ULL >> (64 - 7));
            tagDst = (__data >> tagDst_s) & (~0ULL >> (64 - 7));
            rd = (__data >> rd_s) & (~0ULL >> (64 - 5));
        }

        CommitUOp(const sc_bv<23>& __data) {
            valid = __data.get_bit(valid_s);
            compressed = __data.get_bit(compressed_s);
            branchTaken = __data.get_bit(branchTaken_s);
            isBranch = __data.get_bit(isBranch_s);
            sqN = __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
            tagDst = __data.range(tagDst_s + tagDst_w - 1, tagDst_s).to_uint64();
            rd = __data.range(rd_s + rd_w - 1, rd_s).to_uint64();
        }

        operator uint32_t() const {
            uint32_t ret = 0;
            ret |= static_cast<uint32_t>(valid) << valid_s;
            ret |= static_cast<uint32_t>(compressed) << compressed_s;
            ret |= static_cast<uint32_t>(branchTaken) << branchTaken_s;
            ret |= static_cast<uint32_t>(isBranch) << isBranch_s;
            ret |= static_cast<uint32_t>(sqN) << sqN_s;
            ret |= static_cast<uint32_t>(tagDst) << tagDst_s;
            ret |= static_cast<uint32_t>(rd) << rd_s;
            return ret;
        }

        operator sc_bv<23>() const {
            auto ret = sc_bv<23>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(compressed_s, compressed);
            ret.set_bit(branchTaken_s, branchTaken);
            ret.set_bit(isBranch_s, isBranch);
            ret.range(sqN_s + sqN_w - 1, sqN_s) = sqN;
            ret.range(tagDst_s + tagDst_w - 1, tagDst_s) = tagDst;
            ret.range(rd_s + rd_w - 1, rd_s) = rd;
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " compressed" << " = " << compressed;
            ss << " branchTaken" << " = " << branchTaken;
            ss << " isBranch" << " = " << isBranch;
            ss << " sqN" << " = " << sqN;
            ss << " tagDst" << " = " << tagDst;
            ss << " rd" << " = " << rd;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const CommitUOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const uint32_t& __data) {
            return (__data >> valid_s) & (~0ULL >> (64 - 1));
        }
        static bool get_compressed (const uint32_t& __data) {
            return (__data >> compressed_s) & (~0ULL >> (64 - 1));
        }
        static bool get_branchTaken (const uint32_t& __data) {
            return (__data >> branchTaken_s) & (~0ULL >> (64 - 1));
        }
        static bool get_isBranch (const uint32_t& __data) {
            return (__data >> isBranch_s) & (~0ULL >> (64 - 1));
        }
        static uint32_t get_sqN (const uint32_t& __data) {
            return (__data >> sqN_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_tagDst (const uint32_t& __data) {
            return (__data >> tagDst_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_rd (const uint32_t& __data) {
            return (__data >> rd_s) & (~0ULL >> (64 - 5));
        }
    };

    struct Trap_UOp {
        bool valid;
        bool compressed;
        uint32_t fetchID;
        uint32_t fetchOffs;
        uint32_t rd;
        uint32_t storeSqN;
        uint32_t loadSqN;
        uint32_t sqN;
        uint32_t tag;
        Flags flags;
        bool timeout;

        static constexpr size_t valid_s = 0;
        static constexpr size_t valid_w = 1;
        static constexpr size_t compressed_s = 1;
        static constexpr size_t compressed_w = 1;
        static constexpr size_t fetchID_s = 2;
        static constexpr size_t fetchID_w = 6;
        static constexpr size_t fetchOffs_s = 8;
        static constexpr size_t fetchOffs_w = 3;
        static constexpr size_t rd_s = 11;
        static constexpr size_t rd_w = 5;
        static constexpr size_t storeSqN_s = 16;
        static constexpr size_t storeSqN_w = 7;
        static constexpr size_t loadSqN_s = 23;
        static constexpr size_t loadSqN_w = 7;
        static constexpr size_t sqN_s = 30;
        static constexpr size_t sqN_w = 7;
        static constexpr size_t tag_s = 37;
        static constexpr size_t tag_w = 7;
        static constexpr size_t flags_s = 44;
        static constexpr size_t flags_w = 4;
        static constexpr size_t timeout_s = 48;
        static constexpr size_t timeout_w = 1;
        static constexpr size_t _size = 49;

        Trap_UOp() = default;

        Trap_UOp(const uint64_t& __data) {
            valid = (__data >> valid_s) & (~0ULL >> (64 - 1));
            compressed = (__data >> compressed_s) & (~0ULL >> (64 - 1));
            fetchID = (__data >> fetchID_s) & (~0ULL >> (64 - 6));
            fetchOffs = (__data >> fetchOffs_s) & (~0ULL >> (64 - 3));
            rd = (__data >> rd_s) & (~0ULL >> (64 - 5));
            storeSqN = (__data >> storeSqN_s) & (~0ULL >> (64 - 7));
            loadSqN = (__data >> loadSqN_s) & (~0ULL >> (64 - 7));
            sqN = (__data >> sqN_s) & (~0ULL >> (64 - 7));
            tag = (__data >> tag_s) & (~0ULL >> (64 - 7));
            flags = Flags((__data >> flags_s) & (~0ULL >> (64 - 4)));
            timeout = (__data >> timeout_s) & (~0ULL >> (64 - 1));
        }

        Trap_UOp(const sc_bv<49>& __data) {
            valid = __data.get_bit(valid_s);
            compressed = __data.get_bit(compressed_s);
            fetchID = __data.range(fetchID_s + fetchID_w - 1, fetchID_s).to_uint64();
            fetchOffs = __data.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s).to_uint64();
            rd = __data.range(rd_s + rd_w - 1, rd_s).to_uint64();
            storeSqN = __data.range(storeSqN_s + storeSqN_w - 1, storeSqN_s).to_uint64();
            loadSqN = __data.range(loadSqN_s + loadSqN_w - 1, loadSqN_s).to_uint64();
            sqN = __data.range(sqN_s + sqN_w - 1, sqN_s).to_uint64();
            tag = __data.range(tag_s + tag_w - 1, tag_s).to_uint64();
            flags = Flags(__data.range(flags_s + flags_w - 1, flags_s).to_uint64());
            timeout = __data.get_bit(timeout_s);
        }

        operator uint64_t() const {
            uint64_t ret = 0;
            ret |= static_cast<uint64_t>(valid) << valid_s;
            ret |= static_cast<uint64_t>(compressed) << compressed_s;
            ret |= static_cast<uint64_t>(fetchID) << fetchID_s;
            ret |= static_cast<uint64_t>(fetchOffs) << fetchOffs_s;
            ret |= static_cast<uint64_t>(rd) << rd_s;
            ret |= static_cast<uint64_t>(storeSqN) << storeSqN_s;
            ret |= static_cast<uint64_t>(loadSqN) << loadSqN_s;
            ret |= static_cast<uint64_t>(sqN) << sqN_s;
            ret |= static_cast<uint64_t>(tag) << tag_s;
            ret |= static_cast<uint64_t>(flags) << flags_s;
            ret |= static_cast<uint64_t>(timeout) << timeout_s;
            return ret;
        }

        operator sc_bv<49>() const {
            auto ret = sc_bv<49>();
            ret.set_bit(valid_s, valid);
            ret.set_bit(compressed_s, compressed);
            ret.range(fetchID_s + fetchID_w - 1, fetchID_s) = fetchID;
            ret.range(fetchOffs_s + fetchOffs_w - 1, fetchOffs_s) = fetchOffs;
            ret.range(rd_s + rd_w - 1, rd_s) = rd;
            ret.range(storeSqN_s + storeSqN_w - 1, storeSqN_s) = storeSqN;
            ret.range(loadSqN_s + loadSqN_w - 1, loadSqN_s) = loadSqN;
            ret.range(sqN_s + sqN_w - 1, sqN_s) = sqN;
            ret.range(tag_s + tag_w - 1, tag_s) = tag;
            ret.range(flags_s + flags_w - 1, flags_s) = flags;
            ret.set_bit(timeout_s, timeout);
            return ret;
        }

        std::string to_string() const {
            std::stringstream ss;
            ss << "valid" << " = " << valid;
            ss << " compressed" << " = " << compressed;
            ss << " fetchID" << " = " << fetchID;
            ss << " fetchOffs" << " = " << fetchOffs;
            ss << " rd" << " = " << rd;
            ss << " storeSqN" << " = " << storeSqN;
            ss << " loadSqN" << " = " << loadSqN;
            ss << " sqN" << " = " << sqN;
            ss << " tag" << " = " << tag;
            ss << " flags" << " = " << flags;
            ss << " timeout" << " = " << timeout;
            return std::move(ss.str());
        }

        friend std::ostream& operator<<(std::ostream& os, const Trap_UOp& __data) {
            os << __data.to_string();
            return os;
        }
        static bool get_valid (const uint64_t& __data) {
            return (__data >> valid_s) & (~0ULL >> (64 - 1));
        }
        static bool get_compressed (const uint64_t& __data) {
            return (__data >> compressed_s) & (~0ULL >> (64 - 1));
        }
        static uint32_t get_fetchID (const uint64_t& __data) {
            return (__data >> fetchID_s) & (~0ULL >> (64 - 6));
        }
        static uint32_t get_fetchOffs (const uint64_t& __data) {
            return (__data >> fetchOffs_s) & (~0ULL >> (64 - 3));
        }
        static uint32_t get_rd (const uint64_t& __data) {
            return (__data >> rd_s) & (~0ULL >> (64 - 5));
        }
        static uint32_t get_storeSqN (const uint64_t& __data) {
            return (__data >> storeSqN_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_loadSqN (const uint64_t& __data) {
            return (__data >> loadSqN_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_sqN (const uint64_t& __data) {
            return (__data >> sqN_s) & (~0ULL >> (64 - 7));
        }
        static uint32_t get_tag (const uint64_t& __data) {
            return (__data >> tag_s) & (~0ULL >> (64 - 7));
        }
        static Flags get_flags (const uint64_t& __data) {
            return Flags((__data >> flags_s) & (~0ULL >> (64 - 4)));
        }
        static bool get_timeout (const uint64_t& __data) {
            return (__data >> timeout_s) & (~0ULL >> (64 - 1));
        }
    };

}
