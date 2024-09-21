VERILATOR_FLAGS = \
	--cc --build --threads 4 --unroll-stmts 999999 -unroll-count 999999 --assert -Wall -Wno-BLKSEQ -Wno-UNUSED \
	-Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-ENUMVALUE -Wno-GENUNNAMED --x-assign unique --x-initial unique -O3 -sv \
	$(VFLAGS) \
	-CFLAGS "-march=native" \
	-LDFLAGS "-ldl" \
	-MAKEFLAGS -j$(nproc) \
	-CFLAGS -DDEBUG_TIME=-1 \
	-CFLAGS -DNOKONATA \
	-CFLAGS -DCOSIM \

VERILATOR_CFG = --exe sim/Top_tb.cpp sim/Simif.cpp --savable ../riscv-isa-sim/libriscv.a ../riscv-isa-sim/libsoftfloat.a ../riscv-isa-sim/libdisasm.a -CFLAGS -I../riscv-isa-sim --top-module Top -Ihardfloat

VERILATOR_TRACE_FLAGS = --trace --trace-structs --trace-max-width 128 --trace-max-array 256 -CFLAGS -DTRACE

SRC_FILES = \
	src/Config.sv \
	src/Include.sv  \
	src/InstrDecoder.sv  \
	src/Rename.sv  \
	src/Core.sv  \
	src/IssueQueue.sv  \
	src/IntALU.sv  \
	src/IFetch.sv \
	src/Load.sv \
	src/ROB.sv \
	src/AGU.sv \
	src/BranchPredictor.sv \
	src/LoadBuffer.sv \
	src/StoreQueue.sv \
	src/Multiply.sv \
	src/Divide.sv \
	src/MMIO.sv \
	src/LZCnt.sv \
	src/PopCnt.sv \
	src/BranchSelector.sv \
	src/PreDecode.sv \
	src/MemRTL.sv \
	src/MemRTL2W.sv \
	src/Top.sv \
	src/MemoryController.sv \
	src/RenameTable.sv \
	src/TagBuffer.sv \
	src/FPU.sv \
	src/FMul.sv \
	src/FDiv.sv \
	src/BranchTargetBuffer.sv \
	src/BranchPredictionTable.sv \
	src/ReturnStack.sv \
	src/TageTable.sv \
	src/TagePredictor.sv \
	src/LoadStoreUnit.sv \
	src/IFetchPipeline.sv \
	src/CSR.sv \
	src/TrapHandler.sv \
	src/CacheInterface.sv \
	src/MemoryInterface.sv \
	src/Peripherals.sv \
	src/PageWalker.sv \
	src/LoadSelector.sv \
	src/LoadResultBuffer.sv \
	src/TLB.sv \
	src/BypassLSU.sv \
	src/TValSelect.sv \
	src/SoC.sv \
	src/TLBMissQueue.sv \
	src/ExternalAXISim.sv \
	src/CacheWriteInterface.sv \
	src/CacheReadInterface.sv \
	src/FIFO.sv \
	src/RegFileRTL.sv \
	src/BranchHandler.sv \
	src/PriorityEncoder.sv \
	src/StoreDataIQ.sv \
	src/StoreDataLoad.sv \
	src/StoreQueueBackend.sv \
	src/OHEncoder.sv \
	src/RangeMaskGen.sv \
	src/Scheduler.sv \
	hardfloat/addRecFN.v \
	hardfloat/compareRecFN.v \
	hardfloat/fNToRecFN.v \
	hardfloat/HardFloat_primitives.v \
	hardfloat/HardFloat_specialize.v \
	hardfloat/recFNToIN.v \
	hardfloat/recFNToFN.v \
	hardfloat/mulRecFN.v \
	hardfloat/HardFloat_rawFN.v

.PHONY: soomrv
soomrv:
	verilator $(VERILATOR_FLAGS) $(VERILATOR_CFG) $(SRC_FILES)

.PHONY: linux
linux: soomrv
	make -C test_programs/linux
	./obj_dir/VTop --device-tree=test_programs/linux/device_tree.dtb --backup-file=soomrv.backup test_programs/linux/linux_image.elf

.PHONY: trace
trace: VERILATOR_FLAGS += $(VERILATOR_TRACE_FLAGS)
trace: soomrv

.PHONY: setup
setup:
	git submodule update --init --recursive
	cd riscv-isa-sim && ./configure CFLAGS="-Os -g0" CXXFLAGS="-Os -g0" --with-boost=no --with-boost-asio=no --with-boost-regex=no
	make -j $(nproc) -C riscv-isa-sim

.PHONY: prepare_header
prepare_header:
	python scripts/prepare_header.py obj_dir/\*.h sim/model_headers.h

.PHONY: clean
clean:
	$(RM) -r obj_dir
