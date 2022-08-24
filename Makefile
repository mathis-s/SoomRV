VERILATOR_FLAGS = --cc --trace-structs --build --trace --unroll-stmts 99999 -unroll-count 9999 --assert


decoder_tb:
	verilator $(VERILATOR_FLAGS) --exe Decode_tb.cpp --top-module Core src/Include.sv src/InstrDecoder.sv src/Rename.sv src/Core.sv src/ReservationStation.sv src/IntALU.sv src/ProgramCounter.sv src/RF.sv src/Load.sv src/ROB.sv src/LSU.sv

clean:
	rm -r obj_dirs
