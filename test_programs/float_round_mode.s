.text
.globl main

main:
    
    li a0, 0
    fsrm zero, a0
    
    li a0, 0x3DFCD6E9 # 0.12345678
    li a1, 0x41200000 # 10.0
    fadd.s a0, a0, a1
    call printhex
    
    li a0, 1
    fsrm zero, a0
    
    li a0, 0x3DFCD6E9 # 0.12345678
    li a1, 0x41200000 # 10.0
    fadd.s a0, a0, a1
    call printhex
    
    li a0, 2
    fsrm zero, a0
    
    li a0, 0x3DFCD6E9 # 0.12345678
    li a1, 0x41200000 # 10.0
    fadd.s a0, a0, a1
    call printhex
    
    li a0, 3
    fsrm zero, a0
    
    li a0, 0x3DFCD6E9 # 0.12345678
    li a1, 0x41200000 # 10.0
    fadd.s a0, a0, a1
    call printhex
    
    li a0, 4
    fsrm zero, a0
    
    li a0, 0x3DFCD6E9 # 0.12345678
    li a1, 0x41200000 # 10.0
    fadd.s a0, a0, a1
    call printhex
    
    # set dyn rounding mode to an invalid value
    li a0, 5
    fsrm zero, a0
    
    li a0, 0x3DFCD6E9 # 0.12345678
    li a1, 0x41200000 # 10.0
    fadd.s a0, a0, a1, rdn # this does not use frm, does not throw
    call printhex
    
    fadd.s a0, a0, a1 # this throws
    
    .loop:
        j .loop
