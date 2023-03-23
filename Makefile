VERILATOR_FLAGS = --cc --trace-structs --build --trace --unroll-stmts 999999 -unroll-count 999999 --assert -Wall -Wno-BLKSEQ -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME --public --trace-max-width 128 --trace-max-array 512 --x-assign unique --x-initial unique -O3 -CFLAGS -O2 -MAKEFLAGS -j16


decoder_tb:
	verilator $(VERILATOR_FLAGS) --exe Decode_tb.cpp --top-module Top -Ihardfloat \
	src/Include.sv  \
	src/InstrDecoder.sv  \
	src/Rename.sv  \
	src/Core.sv  \
	src/IssueQueue.sv  \
	src/IntALU.sv  \
	src/ProgramCounter.sv \
	src/RF.sv \
	src/Load.sv \
	src/ROB.sv \
	src/AGU.sv \
	src/BranchPredictor.sv \
	src/IndirectBranchPredictor.sv \
	src/LoadBuffer.sv \
	src/StoreQueue.sv \
	src/MultiplySmall.sv \
	src/Multiply.sv \
	src/Divide.sv \
	src/ControlRegs.sv \
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
	hardfloat/addRecFN.v \
	hardfloat/compareRecFN.v \
	hardfloat/fNToRecFN.v \
	hardfloat/HardFloat_primitives.v \
	hardfloat/HardFloat_specialize.v \
	hardfloat/recFNToIN.v \
	hardfloat/recFNToFN.v \
	hardfloat/mulRecFN.v \
	hardfloat/HardFloat_rawFN.v

clean:
	rm -r obj_dir
