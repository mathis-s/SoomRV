.text
.globl main
# bogus program to get 4 IPC
main:
    
    li a1, 2048
    
    .loop:
        lb a2, 0(a0)
        c.addi a0, 1
        c.addi a1, -1
        c.bnez a1, .loop
        
    li a1, 2048
    
    .loop2:
        lb a2, 0(a0)
        c.addi a0, 1
        c.addi a1, -1
        c.bnez a1, .loop2
    
    ebreak
