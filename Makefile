VERILATOR_FLAGS = \
	--cc --build --threads 4 --unroll-stmts 999999 -unroll-count 999999 --assert -Wall -Wno-BLKSEQ -Wno-UNUSED \
	-Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-MULTIDRIVEN --x-assign unique --x-initial unique -O3 -sv \
	-CFLAGS "-march=native -std=c++17" \
	-MAKEFLAGS -j16

VERILATOR_CFG = -CFLAGS -g --top-module Top -Ihardfloat

VERILATOR_TRACE_FLAGS = --trace --trace-structs --trace-max-width 128 --trace-max-array 64 -CFLAGS -DTRACE

SRC_FILES = \
	src/Config.sv \
	src/Include.sv  \
	src/InstrDecoder.sv  \
	src/Rename.sv  \
	src/Core.sv  \
	src/IssueQueue.sv  \
	src/IntALU.sv  \
	src/IFetch.sv \
	src/RF.sv \
	src/Load.sv \
	src/ROB.sv \
	src/AGU.sv \
	src/BranchPredictor.sv \
	src/IndirectBranchPredictor.sv \
	src/LoadBuffer.sv \
	src/StoreQueue.sv \
	src/Multiply.sv \
	src/Divide.sv \
	src/MMIO.sv \
	src/LZCnt.sv \
	src/PopCnt.sv \
	src/BranchSelector.sv \
	src/PreDecode.sv \
	src/CacheController.sv \
	src/MemRTL.sv \
	src/Top.sv \
	src/MemoryController.sv \
	src/ExternalMemorySim.sv \
	src/RenameTable.sv \
	src/TagBuffer.sv \
	src/FPU.sv \
	src/FMul.sv \
	src/FDiv.sv \
	src/BranchTargetBuffer.sv \
	src/BranchPredictionTable.sv \
	src/ReturnStack.sv \
	src/TageTable.sv \
	src/PCFile.sv \
	src/TagePredictor.sv \
	src/LoadStoreUnit.sv \
	src/ICacheTable.sv \
	src/CSR.sv \
	src/TrapHandler.sv \
	src/CacheInterface.sv \
	src/MemoryInterface.sv \
	src/Peripherals.sv \
	src/PageWalker.sv \
	src/LoadSelector.sv \
	src/LoadMissQueue.sv \
	hardfloat/addRecFN.v \
	hardfloat/compareRecFN.v \
	hardfloat/fNToRecFN.v \
	hardfloat/HardFloat_primitives.v \
	hardfloat/HardFloat_specialize.v \
	hardfloat/recFNToIN.v \
	hardfloat/recFNToFN.v \
	hardfloat/mulRecFN.v \
	hardfloat/HardFloat_rawFN.v

bench: top Top_tb.cpp
	$(CXX) -O2 -g -faligned-new -fcf-protection=none -std=c++17 -pthread -lpthread -latomic \
	Top_tb.cpp \
	-I obj_dir \
	-I riscv-isa-sim \
	-I/usr/share/verilator/include \
	-I/usr/share/verilator/include/vltstd \
	obj_dir/VTop__ALL.a \
	riscv-isa-sim/libriscv.a \
	riscv-isa-sim/libsoftfloat.a \
	riscv-isa-sim/libdisasm.a \
	obj_dir/verilated.o \
	obj_dir/verilated_dpi.o \
	obj_dir/verilated_threads.o \
	-o obj_dir/VTop

top:
	verilator $(VERILATOR_FLAGS) $(VERILATOR_CFG) $(SRC_FILES)

trace:
	verilator $(VERILATOR_FLAGS) $(VERILATOR_TRACE_FLAGS) $(VERILATOR_CFG) $(SRC_FILES)

clean:
	rm -r obj_dir
