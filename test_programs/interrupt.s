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
    jalr zero, a1, 4

main:
    
    # set irq handler address
    lui a0, %hi(irq_handler)
    addi a0, a0, %lo(irq_handler)
    li a1, 0xff000000
    sw a0, 0(a1)
    
    # print first 
    li a0, 1
    call printhex
    
    # not implemented, fires exception
    fadd.d f1, f1, f1
    
	# null pointer read
    lw a0, 0(zero)
    
    # unaligned write
    sw a0, 2(zero)
    
    li a0, 2
    call printhex
    
    # regular trap
    ecall
    
    li a0, 3
    call printhex
    
    li a0, 16383
    lb a1, 0(a0)
    
    ebreak

    
    
