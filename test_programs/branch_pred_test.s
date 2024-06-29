.text
.globl main
main:
    li a0, 1000
    
    .loop:
        addi a0, a0, -1
        andi a1, a0, 1
        beqz a1, .skip
            addi a2, a2, 1
        .skip:
        
        
        bnez a0, .loop
    
    jr ra
