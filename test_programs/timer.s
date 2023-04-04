.text
.globl main


main:

    li a0, 0
    csrrw x0, mideleg, a0
    li a0, 0
    csrrw x0, medeleg, a0
    
    # enable all counters in u mode
    li a0, -1
    csrw mcounteren, a0
    csrw scounteren, a0
    
    # enable machine timer interrupt
    li a0, 1<<7
    csrs mie, a0
    
    la a0, machine_trap
    csrrw x0, mtvec, a0
    
    # set up timer interrupt in 1000 cycles
    li a1, 0x1100bff8
    li a2, 100
    lw a0, 0(a1)
    add a0, a0, a2
    li a1, 0x11004000
    sw a0, 0(a1)

    la a0, user
    csrrw x0, mepc, a0
    li a0, 0x00000000
    csrrw x0, mstatus, a0
    mret

    
.align 2
machine_trap:
    
    csrw mscratch, a0
    
    li a0, 0x80040000
    sw x1, 0(a0)
    sw x2, 4(a0)
    sw x3, 8(a0)
    sw x4, 12(a0)
    sw x5, 16(a0)
    sw x6, 20(a0)
    sw x7, 24(a0)
    sw x8, 28(a0)
    sw x9, 32(a0)
    sw x11, 40(a0)
    sw x12, 44(a0)
    sw x13, 48(a0)
    sw x14, 52(a0)
    sw x15, 56(a0)
    sw x16, 60(a0)
    sw x17, 64(a0)
    sw x18, 68(a0)
    sw x19, 72(a0)
    sw x20, 76(a0)
    sw x21, 80(a0)
    sw x22, 84(a0)
    sw x23, 88(a0)
    sw x24, 92(a0)
    sw x25, 96(a0)
    sw x26, 100(a0)
    sw x27, 104(a0)
    sw x28, 108(a0)
    sw x29, 112(a0)
    sw x30, 116(a0)
    sw x31, 120(a0)
    
    #call printdecu
    csrr a0, mepc
    call printhex

    csrr a0, mcause
    bltz a0, .continue
        li a0, 0x11100000
        li a1, 0x55
        sb a1, 0(a0)
    
        .end_loop:
            j .end_loop
    .continue:
    
    # schedule timer interrupt in 1000 cycles
    li a1, 0x1100bff8
    li a2, 100
    lw a0, 0(a1)
    add a0, a0, a2
    li a1, 0x11004000
    sw a0, 0(a1)
    
    li a0, 0x80040000
    lw x1, 0(a0)
    lw x2, 4(a0)
    lw x3, 8(a0)
    lw x4, 12(a0)
    lw x5, 16(a0)
    lw x6, 20(a0)
    lw x7, 24(a0)
    lw x8, 28(a0)
    lw x9, 32(a0)
    lw x11, 40(a0)
    lw x12, 44(a0)
    lw x13, 48(a0)
    lw x14, 52(a0)
    lw x15, 56(a0)
    lw x16, 60(a0)
    lw x17, 64(a0)
    lw x18, 68(a0)
    lw x19, 72(a0)
    lw x20, 76(a0)
    lw x21, 80(a0)
    lw x22, 84(a0)
    lw x23, 88(a0)
    lw x24, 92(a0)
    lw x25, 96(a0)
    lw x26, 100(a0)
    lw x27, 104(a0)
    lw x28, 108(a0)
    lw x29, 112(a0)
    lw x30, 116(a0)
    lw x31, 120(a0)
    
    # wait until mip.MTIP is no longer set
    .wait:
        csrr a0, mip
        andi a0, a0, 1<<7
        bnez a0, .wait
    
    csrr a0, mscratch
    mret
    
user:
    li a0, 0

    #.loop:
    #    j .loop
    #nop
    #nop
    #nop
    #ebreak
    
    .loop:
        addi a0, a0, 1
        mv s0, a0
        call printdecu
        mv a0, s0
        j .loop
    
