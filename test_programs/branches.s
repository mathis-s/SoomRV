.text
.globl main

main:

    li a0, 100
    
    .loop:
        
        
        .l0:
            j .l3
        .l1:
            j .l2
        .l2:
            j .end
        .l3:
            j .l1
        .end:
    
        addi a0, a0, -1
        bnez a0, .loop
    
    ebreak
