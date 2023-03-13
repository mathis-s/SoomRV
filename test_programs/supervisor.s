.text
.globl main

main:
    
    li a0, 0
    csrrw x0, mideleg, a0
    li a0, 1<<8
    csrrw x0, medeleg, a0
    
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
    
    # saving a1 is not actually necessary
    csrw mscratch, a1
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
    
    ebreak
    
