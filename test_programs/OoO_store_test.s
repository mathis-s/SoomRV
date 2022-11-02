.text
.globl main
main:
    li s1, 42
    li s0, -5
    addi s0, s0, 1
    addi s0, s0, 1
    addi s0, s0, 1
    addi s0, s0, 1
    addi s0, s0, 1
    beqz s0, .branch
        sw s1, 1024(zero)
    .branch:
    lw a0, 1024(zero)
    call printhex
    
    ebreak

