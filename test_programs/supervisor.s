.text
.globl main

main:
    
    li a0, 0
    csrrw x0, mideleg, a0
    # delegate ebreak_u to s mode
    li a0, 1<<8
    csrrw x0, medeleg, a0
    
    # enable all counters in u mode
    li a0, -1
    csrw mcounteren, a0
    csrw scounteren, a0

    
    la a0, machine_trap
    csrrw x0, mtvec, a0
    
    la a0, supervisor_trap
    csrrw x0, stvec, a0

    la a0, user
    csrrw x0, mepc, a0
    li a0, 0x00000000
    csrrw x0, mstatus, a0
    mret

.align 2
machine_trap:
    
    csrw mscratch, a1
    
    csrr a1, mcause
    li a0, 2
    bne a0, a1, .not_ii
        li a0, 0x11100000
        li a1, 0x55
        sb a1, 0(a0)
    .not_ii:
    csrr a1, mepc
    addi a1, a1, 4
    csrw mepc, a1
    csrr a1, mscratch
    
    li a0, 41
    mret

.align 2
supervisor_trap:
    
    csrw sscratch, a1
    csrr a1, sepc
    addi a1, a1, 4
    csrw sepc, a1
    csrr a1, sscratch
    
    # ecall_s is not delegated, thus this jumps to machine_trap
    ecall
    
    addi a0, a0, 1
    sret
    
user:
    
    # ecall_u is delegated, this this jumps to supervisor_trap
    ecall
    call printhex
    
    # read address misalign is not delegated, this jumps to machine_trap
    lw a0, 1(zero)
    call printhex
    
    # read only alias to counters should be accessible
    #csrr a0, hpmcounter4
    #call printhex
    
    # r/w counter is inaccessible in u mode,
    # invalid instruction causes ebreak, thus terminating the program
    csrr a0, mhpmcounter4
    
    .wait:
        j .wait
    
