

all: hello_world

hello_world.o: hello_world.s
	$(AS) -march=rv32imac_zba_zbb -o $@ $^

hello_world: hello_world.o
	$(LD) -o $@ $^

.PHONY: disasm
disasm: hello_world
	objdump -d hello_world
