.text
.globl main
main:
    li a0, 100
    
    
    .loop:
        addi a0, a0, -1
        nop
        bnez a0, .loop
    
    ebreak
