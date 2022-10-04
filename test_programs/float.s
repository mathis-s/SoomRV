.text
.globl main
main:
    li t0, 0x1000
    li a0, 0x3F800000
    sw a0, 4(t0)
    flw fa0, 4(t0)
    fadd.s fa0, fa0, fa0
    li a0, 1
    call printhex
    ebreak
