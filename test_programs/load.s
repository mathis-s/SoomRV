.section .rodata
.align 2
.zero 36
data: .word 0xdeadbeef
.zero 1024
data2: .word 0xdeadbeef
.text
.globl main
main:
    la a0, data
    la a2, data2
    lw a1, 0(a0)
    lw a1, 0(a2)
    lw a1, 0(a0)
    lw a1, 0(a2)
    lw a1, 0(a0)
    lw a1, 0(a2)
    lw a1, 0(a0)
    wfi
