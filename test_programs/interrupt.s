.text
.globl main

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
	
irq_handler:
	# print interrupt reason (with marker)
    li a1, 0xff000008
    lw a1, 0(a1)
    ori a0, a1, 0x100
    call printhex
    # get irq src
    li a1, 0xff000004
    lw a1, 0(a1)
    # skip over exception
    jalr zero, a1, 4

main:
    
    # set irq handler address
    lui a0, %hi(irq_handler)
    addi a0, a0, %lo(irq_handler)
    li a1, 0xff000000
    sw a0, 0(a1)
    
    # print first 
    li a0, 1
    call printhex
    
    # not implemented, fires exception
    fadd.d f1, f1, f1
    
	# null pointer read
    lw a0, 0(zero)
    
    # unaligned write
    sw a0, 2(zero)
    
    li a0, 2
    call printhex
    
    # regular trap
    ecall
    
    li a0, 3
    call printhex
    
    ebreak

    
    
