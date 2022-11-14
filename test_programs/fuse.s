.text
.globl main

main:
    
    li a1, 30720
    li s0, 32768
    
    .align 4
    .loop:
        addi a0, a0, 256
        sw a0, 0(a1)
        addi a1, a1, 4
        bne a1, s0, .loop
    
    li a0, 128
    .wait:
        addi a0, a0, -1
        bnez a0, .wait
    li a1, 30720
    li s0, 32768
    
    .align 4
    .loop2:
        addi a0, a0, 1
        sw a0, 0(a1)
        addi a1, a1, 4
        bne a1, s0, .loop2
    
    ret
