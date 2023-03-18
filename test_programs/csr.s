.text
.globl main

main:

    li s0, 16
    
    li a0, 0
    csrw mcountinhibit, a0
    csrr a0, mcountinhibit
    call printhex
    
    .loop:
        csrrw a0, mcycle, zero
        call printdecu
        addi s0, s0, -1
        bnez s0, .loop
    
    ebreak
