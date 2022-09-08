.text
.globl main

main:
    li a0, 0xff000000
    
    # set oe on all
    li t0, 0xffff
    sh t0, 20(a0)
    
    # set autodisable delay to 32
    li t0, 32
    sb t0, 24(a0)
    
    # autodisable upper four pins
    li t0, 0xf0
    sb t0, 26(a0)
    
        
    # enable/disable pins
    li t0, 0xAAAA
    sh t0, 22(a0)
    
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    
    ebreak
    
    
    
    
