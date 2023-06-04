.text
.globl main
main:
    mv s2, ra
    li s0, 0x11200000
    sw zero, 0(s0)
    li s1, 100
    .loop:
        addi s1, s1, -1
        sb s1, 1(s0)
        lw a0, 0(s0)
        call printhex
        bgez s1, .loop
    
    mv ra, s2
    ret
