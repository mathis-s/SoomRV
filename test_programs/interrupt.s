.text
.globl main
	
irq_handler:
	# print interrupt reason (with marker)
    li a1, 0xff000008
    lw a1, 0(a1)
    ori a0, a1, 0x100
    call printhex
    # get irq src
    li a1, 0xff000004
    lw a1, 0(a1)
    # skip over exception
    # load first byte of instruction
    lb a2, 0(a1)
    # mask off length specifier
    andi a2, a2, 3
    
    
    sltiu a2, a2, 3
    xori a2, a2, 1
    add a2, a2, a2
    add a1, a1, a2
    
    jalr zero, a1, 2

    
main:
    
    # set irq handler address
    lui a0, %hi(irq_handler)
    addi a0, a0, %lo(irq_handler)
    li a1, 0xff000000
    sw a0, 0(a1)

    li a0, 32
    .wait:
        addi a0, a0, -1
        bnez a0, .wait
    
    li s0, 128
    .loop:
        lw a0, 0(x0)
        addi s0, s0, -1
        bnez s0, .loop
    
    li a0, 0
    call printhex
    
    ebreak
    
#main:
#    
#    # set irq handler address
#    lui a0, %hi(irq_handler)
#    addi a0, a0, %lo(irq_handler)
#    li a1, 0xff000000
#    sw a0, 0(a1)
#    
#    # print first 
#    li a0, 1
#    call printhex
#    
#    # not implemented, fires exception
#    unimp
#    unimp
#    
#	# null pointer read
#    lw a0, 0(zero)
#    
#    # unaligned write
#    sw a0, 2(zero)
#    
#    li a0, 2
#    call printhex
#    
#    # regular trap
#    ecall
#    
#    li a0, 3
#    call printhex
#    
#    li a0, 16383
#    lb a1, 0(a0)
#    
#    ebreak

    
    
