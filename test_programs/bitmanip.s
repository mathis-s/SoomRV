.text
.globl main
main:
    
    li a0, 32
    li a1, 16
    sh2add a0, a1, a0
    call printhex
    
    li a0, 0xFF
    li a1, 0xFFFFFFFF
    xnor a0, a1, a0
    call printhex
    
    li a0, 0xFF
    li a1, 0xFFFFFFFF
    andn a0, a1, a0
    call printhex
    
    li a0, 0xFF
    li a1, 0xFFFFFFFF
    orn a0, a0, a1
    call printhex
    
    li a0, 0xFF
    sext.b a0, a0
    call printhex
    
    li a0, -1
    zext.h a0, a0
    call printhex
    
    li a0, 32767
    sext.h a0, a0
    call printhex
    
    
	li a0, 0x00010000
    clz a0, a0
    call printhex
    
	li a0, 0x00010000
    ctz a0, a0
    call printhex
    
	li a0, 0xdeadbeef
    cpop a0, a0
    call printhex
    
    ebreak
    
    
    
    
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
