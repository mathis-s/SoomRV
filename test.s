.text
.main:
    li a1, 16
.loop:
    li a0, 0
    lw a0, 1023(x0)
	addi a0, a0, 1
    sw a0, 1023(x0)
    blt a0, a1, .loop
    addi a2, a2, 1
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

