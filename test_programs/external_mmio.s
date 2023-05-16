.text
.globl main
main:
    mv s2, ra
    li s0, 0x11200000
    li s1, 100
    .loop:
        lw a0, 0(s0)
        sw x0, 0(s0)
        call printhex
        addi s1, s1, -1
        bnez s1, .loop
    
    mv ra, s2
    ret
