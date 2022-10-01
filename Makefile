VERILATOR_FLAGS = --cc --trace-structs --build --trace --unroll-stmts 99999 -unroll-count 9999 --assert -Wall -Wno-BLKSEQ -Wno-UNUSED -Wno-PINCONNECTEMPTY --public --trace-max-width 128 --trace-max-array 512 --x-assign unique --x-initial unique -MAKEFLAGS -j16


decoder_tb:
	verilator $(VERILATOR_FLAGS) --exe Decode_tb.cpp --top-module Top src/Include.sv src/InstrDecoder.sv src/Rename.sv src/Core.sv src/ReservationStation.sv src/IntALU.sv src/ProgramCounter.sv src/RF.sv src/Load.sv src/ROB.sv src/AGU.sv src/BranchPredictor.sv src/LoadBuffer.sv src/StoreQueue.sv src/MultiplySmall.sv src/Divide.sv src/ControlRegs.sv src/LZCnt.sv src/PopCnt.sv src/Fuse.sv src/BranchSelector.sv src/PreDecode.sv src/CacheController.sv src/MemRTL.sv src/Top.sv src/MemoryControllerSim.sv src/RenameTable.sv src/TagBuffer.sv

clean:
	rm -r obj_dir
