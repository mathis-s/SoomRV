.text
.globl main
main:
    
    li a0, 128
    li a1, 0
    
    .loop:
        
        andi t0, a0, 1
        beqz t0, .skip
            addi a1, a1, 1
        .skip:
        
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        
        addi a0, a0, -1
        bnez a0, .loop
    
    ebreak
