.text
.globl main

main:
    
    li a1, 10
    
    .loop:
        li a0, 0x12345678
        li a0, 0x23456789
        auipc a0, 0x34567
        addi a0, a0, 0x7FA
        li a0, 0x456789AB
        li a0, 0x56789ABC
        addi a1, a1, -1
        bne a1, x0, .loop
    
    
    ebreak
