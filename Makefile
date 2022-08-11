VERILATOR_FLAGS = --cc --trace-structs -Wno-WIDTH --build --trace


decoder_tb:
	verilator $(VERILATOR_FLAGS) --exe Decode_tb.cpp --top-module Decode src/InstrDecoder.sv src/RAT.sv src/Decode.sv

clean:
	rm -r obj_dir