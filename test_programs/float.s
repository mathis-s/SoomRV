.text
.globl main
main:
    li t0, 2
    fcvt.s.wu fa0, t0
    fadd.s fa0, fa0, fa0
    fcvt.wu.s a0, fa0
    call printhex
    ebreak
