.text
.globl main
main:
    
    li a0, 0x80008000
    addi a1, a0, 4
    addi a2, a0, 8
    addi a3, a0, 12
    addi a4, a0, 16
    addi a5, a0, 20
    addi a6, a0, 24
    addi a7, a0, 28

    li t0, 1
    li t1, 2
    li t2, 4
    li t3, 8
    li t4, 16
    li t5, 32
    li t6, 64
    li s0, 128

    li s1, 1024
    .loop:
        amoand.w x0, t0, (a0)
        amoand.w x0, t1, (a1)
        amoand.w x0, t2, (a2)
        amoand.w x0, t3, (a3)
        amoand.w x0, t4, (a4)
        amoand.w x0, t5, (a5)
        amoand.w x0, t6, (a6)
        amoand.w x0, s0, (a7)
        
        addi s1, s1, -1
        bnez s1, .loop
    ret
