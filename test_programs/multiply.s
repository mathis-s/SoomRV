.text
.globl main

main:
    li a0, 111
    li a1, 111
    div a0, a0, a1
    mul a1, a1, a1
	div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    div a0, a0, a1
    mul a1, a1, a1
    
    call printhex
    ebreak
