.text
.main:
    addi a1, zero, 128
.loop:
	addi a0, a0, 1
    #addi sp, sp, 2
    blt a0, a1, .loop
    addi a1, a1, 1
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

