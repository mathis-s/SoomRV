.text
.globl main


main:
    
    la s0, 0x10000
    
    # simple example, this should work immediately
    lr.w a0, (s0)
    sc.w a0, a0, (s0)
    call printhex
    
    # The branch is initially not predicted, thus the reservation is removed 
    # by the speculatively executed sc. The real SC execution fails.
    # The branch is predicted after a few mispredicts however; then the sc will succeed.
    .loop:
        lr.w a0, (s0)
        addi a0, a0, 1
        bnez a0, .fwd
        addi a0, a0, 1
        addi a0, a0, 1
        .fwd:
        addi a0, a0, 1
        addi a0, a0, 1
        addi a0, a0, 1
        sc.w a0, s0, (s0)
        mv s1, a0
        call printhex
        bnez s1, .loop
    
    ebreak
