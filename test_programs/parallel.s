.text
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a5, 0
    li a6, 0
    li t0, 100
    
    loop:
        addi a0, a0, 1
        addi a1, a1, 2
        addi a2, a2, 3
        addi a3, a3, 4
        addi a5, a5, 5
        addi a6, a6, 6
        
        addi a0, a0, 1
        addi a1, a1, 2
        addi a2, a2, 3
        addi a3, a3, 4
        addi a5, a5, 5
        addi a6, a6, 6
        
        addi a0, a0, 1
        addi a1, a1, 2
        addi a2, a2, 3
        addi a3, a3, 4
        addi a5, a5, 5
        addi a6, a6, 6
        
        addi a0, a0, 1
        addi a1, a1, 2
        addi a2, a2, 3
        addi a3, a3, 4
        addi a5, a5, 5
        addi a6, a6, 6
        
        addi a0, a0, 1
        addi a1, a1, 2
        addi a2, a2, 3
        addi a3, a3, 4
        addi a5, a5, 5
        addi a6, a6, 6
        blt a0, t0, loop
    

        
