.text
.globl main

main:
    
    nop
    li a0, 0x12345678
    li a0, 0x23456789
    auipc a0, 0x34567
    addi a0, a0, 0x7FA
    li a0, 0x456789AB
    li a0, 0x56789ABC
    
    ebreak
