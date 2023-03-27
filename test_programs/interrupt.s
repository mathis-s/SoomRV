.text
.globl main

.align 2
irq_handler:
    
    csrrs a0, mcause, x0
    call printdecu
    
    #csrrs a0, mstatus, x0
    #call printhex
    
    # get irq src
    csrrs a1, mepc, x0
    # skip over exception
    # load first byte of instruction
    lb a2, 0(a1)
    # mask off length specifier
    andi a2, a2, 3
    
    
    sltiu a2, a2, 3
    xori a2, a2, 1
    add a2, a2, a2
    add a1, a1, a2
    #jalr zero, a1, 2
    
    addi a1, a1, 2
    csrrw zero, mepc, a1
    mret
    
    
main:
    
    # set irq handler address
    la a0, irq_handler
    csrrw x0, mtvec, a0
    
    li a0, 1
    sb a0, 15(a1)
    
    # print first 
    li a0, 1
    call printhex
    
    # not implemented, fires exception
    unimp
    unimp
    
	# unaligned read
    lw a0, -1(zero)
    
    # unaligned write
    sw a0, 2(zero)
    
    li a0, 2
    call printhex
    
    # regular trap
    ecall
    
    li a0, 3
    call printhex
    
    # loop of invalid reads
    li s0, 4
    .loop:
        lw a0, 1(x0)
        sw a0, 1(x0)
        addi s0, s0, -1
        bnez s0, .loop
    
    li a0, 0xff000000
    li a1, 0x55
    sb a1, 4(a0)

    
    
