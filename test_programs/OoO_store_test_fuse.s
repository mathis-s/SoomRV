 
.text
.globl main
main:
    li a0, 0xde
    sb a0, 1027(zero)
    li a0, 0xad
    sb a0, 1026(zero)
    li a0, 0xbe
    sb a0, 1025(zero)
    li a0, 0xee
    sb a0, 1024(zero)
    li a0, 0xef
    sb a0, 1024(zero)
    lw a0, 1024(zero)
    call printhex
    
    ebreak

