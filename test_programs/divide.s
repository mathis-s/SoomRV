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
    
    li a4, 1023
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
    
.section .rodata
hexLut:
	.ascii	"0123456789abcdef"
.text
printhex:
	lui	a5,%hi(hexLut)
	addi	a5,a5,%lo(hexLut)
	srli	a4,a0,28
	add	a4,a5,a4
	lbu	a3,0(a4)
	li	a4,1023
	sb	a3,0(a4)
	srli	a3,a0,24
	andi	a3,a3,15
	add	a3,a5,a3
	lbu	a3,0(a3)
	sb	a3,0(a4)
	srli	a3,a0,20
	andi	a3,a3,15
	add	a3,a5,a3
	lbu	a3,0(a3)
	sb	a3,0(a4)
	srli	a3,a0,16
	andi	a3,a3,15
	add	a3,a5,a3
	lbu	a3,0(a3)
	sb	a3,0(a4)
	srli	a3,a0,12
	andi	a3,a3,15
	add	a3,a5,a3
	lbu	a3,0(a3)
	sb	a3,0(a4)
	srli	a3,a0,8
	andi	a3,a3,15
	add	a3,a5,a3
	lbu	a3,0(a3)
	sb	a3,0(a4)
	srli	a3,a0,4
	andi	a3,a3,15
	add	a3,a5,a3
	lbu	a3,0(a3)
	sb	a3,0(a4)
	andi	a0,a0,15
	add	a5,a5,a0
	lbu	a5,0(a5)
	sb	a5,0(a4)
	li a5, 10
	sb a5, 0(a4)
	ret

