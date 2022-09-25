.text
.globl main
# bogus program to get 4 IPC
main:
    
    li a1, 4096
    
    .loop:
        lw a2, 0(a0)
        c.addi a0, 1
        c.addi a1, -1
        c.bnez a1, .loop
    
    ebreak
