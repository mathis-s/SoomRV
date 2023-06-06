.text
.globl main

.align 2
irq_handler:
    
    csrr a0, mcause
    call printdecu
    csrr a0, mcause
    addi a0, a0, -1
    bnez a0, .irq_handler_not_ld_af
    # terminate on ifetch af
    li a0, 0x11100000
    li a1, 0x55
    sb a1, 0(a0)
    .irq_handler_not_ld_af:

    csrr a0, mtval
    call printhex
    
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
    
    # not implemented, fires exception
    unimp
    unimp
    
    li a0, 64
	# unaligned read
    lw a0, -1(a0)
    
    # unaligned write (long dependency)
    li a0, 64*3
    li a1, 3
    div a0, a0, a1
    sw a0, 2(a0)
    
    # short dependency
    li a0, 8
    lw a0, 2(a0)
    li a0, 16
    sw a0, 2(a0)
    
    # regular trap
    ecall

    # breakpoint
    ebreak
    
    # loop of invalid reads
    li s0, 4
    .loop:
        lw a0, 1(x0)
        sw a0, 1(x0)
        addi s0, s0, -1
        bnez s0, .loop
    
    # terminate with if af
    li a0, 42
    jr a0

    
    
