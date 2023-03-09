.text
.globl main

main:
    
    fscsr a0, zero
    call printhex
    
    # max with signaling NaN should signal
    li a0, 0x7FB00001
    li a1, 0x40490FDB
    fmax.s a0, a0, a1
    
    fscsr a0, zero
    call printhex
    
    # max with non-signaling NaN should not signal
    li a0, 0x7FC00000
    li a1, 0x40490FDB
    fmax.s a0, a0, a1
    
    fscsr a0, zero
    call printhex
    
    # ordering comparison signals
    li a0, 0x7FC00000
    li a1, 0x40490FDB
    flt.s a0, a0, a1
    
    fscsr a0, zero
    call printhex
    
    # equality comparison should not signal
    li a0, 0x7FC00000
    li a1, 0x40490FDB
    feq.s a0, a0, a1
    
    fscsr a0, zero
    call printhex
    
    # division by zero
    li a0, 0x40490FDB
    li a1, 0x0
    fdiv.s a0, a0, a1
    
    fscsr a0, zero
    call printhex
    
    # division zero by zero
    li a0, 0x0
    li a1, 0x0
    fdiv.s a0, a0, a1
    
    fscsr a0, zero
    call printhex
    
    # not exact
    li a0, 0x7F7FFFFF
    li a1, 0x3F800000
    fadd.s a0, a0, a1
    
    fscsr a0, zero
    call printhex
    
    # overflow
    li a0, 0x7F7FFFFF
    li a1, 0x7F7FFFFF
    fadd.s a0, a0, a1
    
    fscsr a0, zero
    call printhex
    
    # underflow
    li a0, 0x1
    li a1, 0x40000000
    fdiv.s a0, a0, a1
    
    fscsr a0, zero
    call printhex



    ebreak
