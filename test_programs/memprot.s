.text
.globl main

irq_handler:
    
    fence iorw, iorw
    
    li a0, 1
    call printhex
    
    # get irq src
    li a1, 0xff000000    
    lw a1, 8(a1)
    # continue
    jr a1

main:
    
    # set irq handler address
    lui a0, %hi(irq_handler)
    addi a0, a0, %lo(irq_handler)
    li a1, 0xff000000
    sw a0, 4(a1)
    
    # we are not in user mode, access should work
    li a0, 0x50000000
    lw a0, 0(a0)
    
    li a0, 1
    call printhex
    
    
    li a0, 0xff000000
    # disable control reg access, enable r/w masks
    li a1, 0b11110
    sb a1, 15(a0)
    
    fence iorw, iorw
    
    # this will trigger an exception
    li s0, 0x50000000
    lw s0, 0(s0)
    
    
    # exception doesn't re-enable protection, so do it manually
    li a0, 0xff000000
    # enable read access for section
    li a1, 1048576
    sw a1, 16(a0)
    #sw a1, 24(a0)
    
    # disable control reg access, enable r/w masks
    li a1, 0b11110
    sb a1, 15(a0)
    
    fence iorw, iorw
    
    # this doesn't interrupt
    li s0, 0x50000000
    lw s0, 0(s0)
    
    # this does
    li s0, 0x50000000
    sw s0, 0(s0)
    
    ebreak
