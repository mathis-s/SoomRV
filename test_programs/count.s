 
.text
.globl main
main:
    li a0, 16
    .loop:
        addi a0, a0, -1
        bnez a0, .loop
        
    li a0, 16
    lw a0, 0(a0)
        
    ebreak
