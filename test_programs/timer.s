.text
.globl main


irq_handler:
	# print interrupt reason (with marker)
    mv a0, s0
    call printhex
    
    li a1, 0x2000
    blt s0, a1, .continue
        ebreak
    .continue:
    
    # get irq src
    li a1, 0xff000004
    lw a1, 0(a1)
    # continue
    jr a1

    
main:
    
    # set irq handler address
    lui a0, %hi(irq_handler)
    addi a0, a0, %lo(irq_handler)
    li a1, 0xff000000
    sw a0, 0(a1)
    
    # set timer irq every 2048 cycles.
    li a0, 2
    sh a0, 12(a1)
    
    # loop forever
    .loop:
        addi s0, s0, 1
        j .loop
    
    
