 
.text
.globl main
main:
    li a1, 0x80000000+0x10000
    li a0, 0xde
    sb a0, 1027(a1)
    li a0, 0xad
    sb a0, 1026(a1)
    li a0, 0xbe
    sb a0, 1025(a1)
    li a0, 0xee
    sb a0, 1024(a1)
    li a0, 0xef
    sb a0, 1024(a1)
    lw a0, 1024(a1)
    #call printhex
    
    ret
