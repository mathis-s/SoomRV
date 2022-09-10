.text
.globl main
main:
	# assume string is in memory at 4
    li t0, 0x4
    addi t2, t0, 1
    .loop:
        lb t1, 0(t0)
        addi t0, t0, 1
        bnez t1, .loop
    .end:
    sub a0, t0, t2
    
    #write back length at 4
    sw a0, 4(zero)
    
    ebreak
    
