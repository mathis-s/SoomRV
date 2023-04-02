.text
.globl main
main:
    
    li a0, 0x80020000
    
    # zero will be the actual value at a0
    li t0, 0
    sw t0, 0(a0)
    li t1, 1
    
    # 42 is the cached value at a0
    li t0, 42
    sw t0, 0(a0)
    
    amoadd.w x0, t1, (a0)
    amoadd.w x0, t1, (a0)
    amoadd.w x0, t1, (a0)
    lw t0, 0(a0)
    
    mv a0, t0
    call printhex
    
    ebreak
    
