.text
.globl main

main:

    li s0, 100
    
    .loop:
        csrrw a0, minstret, zero
        call printdecu
        addi s0, s0, -1
        bnez s0, .loop
    
    ebreak
