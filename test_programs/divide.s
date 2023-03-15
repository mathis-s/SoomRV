.text
.globl main
main:
    
    
    li a0, 103945
    li a1, -2
    
    min a0, a1, a0
    call printdec_slow
    #mv a0, s0
    #call printhex
    
    ebreak
    
    
printdecu_slow:
    
    li a4, 1023
    bnez a0, .print2
    li a0, 0x30
    sb a0, 0(a4)
    j .end2
    
    .print2:
    li a1, 1000000000
    li a3, 10
    li a5, 0

    .loop2:
        divu a2, a0, a1
        remu a0, a0, a1
        or a5, a5, a2
        ori a2, a2, 0x30
        
        beqz a5, .skip2
            
            sb a2, 0(a4)
        .skip2:
        
        divu a1, a1, a3
        bnez a1, .loop2
    
    .end2:
    li a0, 10
    sb a0, 0(a4)
    ret
    
    
printdec_slow:
    
    li a4, 0xff000003
    bnez a0, .check_sign
    li a0, 0x30
    sb a0, 0(a4)
    j .end
    
    .check_sign:
    bge a0, zero, .print
    sub a0, zero, a0
    li a1, '-'
    sb a1, 0(a4)
    
    .print:
    li a1, 1000000000
    li a3, 10
    li a5, 0

    .loop:
        divu a2, a0, a1
        remu a0, a0, a1
        or a5, a5, a2
        ori a2, a2, 0x30
        
        beqz a5, .skip
            
            sb a2, 0(a4)
        .skip:
        
        divu a1, a1, a3
        bnez a1, .loop
    
    .end:
    li a0, 10
    sb a0, 0(a4)
    ret

