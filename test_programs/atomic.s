.text
.globl main
main:
    
    li a0, 0x1000
    
    li t0, 2
    li t1, 1
    
    sw t0, 0(a0)
    
    amoadd.w x0, t1, (a0)
    amoadd.w x0, t1, (a0)
    lw t0, 0(a0)
    
    mv s0, t0
    mv s1, t1
    
    mv a0, s0
    call printhex
    
    mv a0, s1
    call printhex
    
    ebreak
    
