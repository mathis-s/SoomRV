.text
.globl main

main:
    
    li a0, 0
    csrrw x0, mideleg, a0
    # delegate ebreak_u to s mode
    li a0, 0#1<<8
    csrrw x0, medeleg, a0
    
    # enable all counters in u mode
    li a0, -1
    csrw mcounteren, a0
    csrw scounteren, a0

    
    la a0, machine_trap
    csrrw x0, mtvec, a0
    
    #la a0, supervisor_trap
    #csrrw x0, stvec, a0
    
    # create page table starting at 0x10000 to 0x10fff
    li s0, 0x80020000
    
    # memset PT to zero
    li a0, 0
    mv a1, s0
    li a2, 4096
    
    # create one valid (rwx) entry pointing to 0x2000000
    # entry is for addresses 0 to (excl) 4Mi
    li a0, 0x000000ff | ((0x20800000))
    sw a0, 0(s0)
    
    li a0, 0x82000000 + 2048
    li a1, 0xdeadbeef
    sw a1, 0(a0)
    li a1, 0x12345678
    sw a1, 4(a0)
    
    # write instructions for user
    li a0, 0x82000000
    li a1, 0x00001537
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x80050513
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00052503
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00000073
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00001537
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x80050513
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00452503
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00000073
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00001537
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x80050513
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x02a00593
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00b52023
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00001537
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x80050513
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00052503
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00000073
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00400537
    sw a1, 0(a0)
    addi a0, a0, 4
    li a1, 0x00050067
    sw a1, 0(a0)
    
    
    li a0, 0x80000000 | (0x80020)
    csrw satp, a0

    fence.i
    sfence.vma

    li a0, 0
    csrrw x0, mepc, a0
    li a0, 0x00000000
    csrrw x0, mstatus, a0
    mret

.align 2
machine_trap:
    
    mv s0, a0
    
    csrr a1, mcause
    li a0, 2
    beq a1, a0, .terminate
    li a0, 12
    beq a1, a0, .terminate
    
    mv a0, s0
    call printhex
    
    li a1, 1<<17
    csrs mstatus, a1
    
    csrr a1, mepc
    lb a2, 0(a1)
    andi a2, a2, 3
    sltiu a2, a2, 3
    xori a2, a2, 1
    add a2, a2, a2
    add a1, a1, a2
    addi a1, a1, 2
    csrw mepc, a1
    
    mret
    
    .terminate:
        call printdecu
        csrr a0, mepc
        call printhex
        
        li a0, 0x11100000
        li a1, 0x55
        sb a1, 0(a0)
        
        .loop:
            j .loop

#.align 2
#supervisor_trap:
#    # disable address translation
#    li a1, 0x80000000
#    csrc satp, a1
#    
#    # print value in a0
#    call printhex
#    
#    csrr a1, sepc
#    lb a2, 0(a1)
#    andi a2, a2, 3
#    sltiu a2, a2, 3
#    xori a2, a2, 1
#    add a2, a2, a2
#    add a1, a1, a2
#    addi a1, a1, 2
#    csrw sepc, a1
#    
#    # re-enable address translation
#    li a1, 0x80000000
#    csrs satp, a1
#    sret
    
user:
    
    # should print deadbeef with address translation
    li a0, 2048
    lw a0, 0(a0)
    ecall
    
    # should print 12345678 with address translation
    li a0, 2048
    lw a0, 4(a0)
    ecall
    
    # overwrite deadbeef with 42
    li a0, 2048
    li a1, 42
    sw a1, 0(a0)
    li a0, 2048
    lw a0, 0(a0)
    ecall

    # jump to invalid address will create instruction access page fault
    li a0, 1<<22
    jr a0
    
