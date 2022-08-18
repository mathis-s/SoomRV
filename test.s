.text
.main:
    li a1, 128
.loop:
	addi a0, a0, 1
    sw a0, 1023(zero)
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

