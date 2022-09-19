.text
.globl main

main:

    li a0, 100
    
    .loop:
        
        
        .l0:
            j .l1
        .l1:
            j .l2
        .l2:
            j .l3
        .l3:
            j .l4
        .l4:
            j .l5
        .l5:
            j .l6
        .l6:
            j .l7
        .l7:
            j .l8
        .l8:
            j .l9
        .l9:
            j .l10
        .l10:
            j .l11
        .l11:
            j .l12
        .l12:
            j .l13
        .l13:
            j .l14
        .l14:
            j .l15
        .l15:
            j .l16
        .l16:
            j .l17
        .l17:
            j .l18
        .l18:
            j .l19
        .l19:
            j .l20
        .l20:
            j .l21
        .l21:
            j .l22
        .l22:
            j .l23
        .l23:
            j .l24
        .l24:
            j .l25
        .l25:
            j .l26
        .l26:
            j .l27
        .l27:
    
        addi a0, a0, -1
        bnez a0, .loop
    
    ebreak
