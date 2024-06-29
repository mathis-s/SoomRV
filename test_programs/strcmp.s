.section .rodata
.align 2
.S0: .string "String A"
.align 2
.S1: .string "String B"
.text
.globl main
main:
    addi sp, sp, -16
    sw ra, 0(sp)

    li s0, 10
    
    .loop:
        la a0, .S0
        la a1, .S1
        call strcmp

        addi s0, s0, -1
        bnez s0, .loop

    lw ra, 0(sp)
    addi sp, sp, 16
    ret
