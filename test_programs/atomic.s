.text
.globl main
main:
    
    li a0, 0x1000
    
    # zero will be the actual value at a0
    li t0, 0
    sw t0, 0(a0)
    cbo.flush 0(a0)
    li t1, 1
    
    # 42 is the cached value at a0
    li t0, 42
    sw t0, 0(a0)
    
    # order we want
    # 1. amoadd_ld runs
    # 2. cbo.inval commits
    # 3. amoadd_store runs
    
    # invalidate the cached 42.
    # real value should be zero from now on
    li a1, 1
    divu a0, a0, a1
    cbo.inval 0(a0)
    
    divu t1, t1, t1
    divu t1, t1, t1
    
    amoadd.w x0, t1, (a0)
    lw t0, 0(a0)
    
    mv a0, t0
    call printhex
    
    ebreak
    
