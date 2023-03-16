.text
.globl main

main:

    li s0, 16
    
    .loop:
        csrrw a0, mhpmcounter5, zero
        call printdecu
        addi s0, s0, -1
        bnez s0, .loop
    
    ebreak
