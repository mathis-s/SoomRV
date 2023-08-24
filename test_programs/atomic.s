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
    
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    amoadd.w a1, t1, (a0)
    lw t0, 0(a0)
    
    mv a0, t0
    call printhex
    
    mv ra, s0
    ret
    
