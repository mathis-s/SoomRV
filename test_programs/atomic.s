.text
.globl main
main:
    
    li a0, 0x80020000
    mv s0, ra
    
    li t0, 0
    sw t0, 0(a0)
    li t1, 1

    li t0, 42
    sw t0, 0(a0)
    
    li a2, 128
    .loop:
    amoswap.w t1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    addi a2, a2, -1
    bnez a2, .loop

    lw t0, 0(a0)
    
    mv a0, t0
    call printhex
    
    mv ra, s0
    ret
    
