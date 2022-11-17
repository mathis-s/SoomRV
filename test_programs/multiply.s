.text
.globl main

main:
    li s0, 1<<31
    li s1, 8
    
    mulh a0, s0, s1
    call printhex
    
    mul a0, s0, s1
    call printhex
    

    ebreak
