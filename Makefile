VERILATOR_FLAGS = --cc --trace-structs --build --trace


decoder_tb:
	verilator $(VERILATOR_FLAGS) --exe Decode_tb.cpp --top-module Decode src/Include.sv src/InstrDecoder.sv src/RAT.sv src/Decode.sv

clean:
	rm -r obj_dir