.text
.globl main


main:
    addi sp, sp, -16
    sw ra, 0(sp)

    li a1, 100
    la s0, 0x80000000+0x40000
    
    .loop:
    # simple example, this should work immediately
    lr.w a0, (s0)
    sc.w a0, a0, (s0)

    addi s0, s0, 4
    addi a1, a1, -1
    bnez a1, .loop
    #call printhex

    lw ra, 0(sp)
    addi sp, sp, 16
    ret
