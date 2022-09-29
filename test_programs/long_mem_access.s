.text
.globl main
main:

    li a0, 0
    li a1, 128
    li a2, 0x10000
    
    .loop:
        lw t0, 0(a1)
        add a0, a0, t0
        addi a1, a1, 4
        blt a1, a2, .loop
        
    ebreak
