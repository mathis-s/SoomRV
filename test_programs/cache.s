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

    # add mapping for violating address
    
    # get addr
    add a1, a1, a1
    li a1, 0xff000000
    lh a0, 10(a1)
    slli a0, a0, 11
    
    # add mapping
    li a1, 0xff000000
    sw a0, 64(a1)
    
    # get irq src
    li a1, 0xff000004
    lw a1, 0(a1)
    # re-run instructions (we haven't saved a0)
    jalr zero, a1, -4
    
    
main:
    # set irq handler address
    lui a0, %hi(irq_handler)
    addi a0, a0, %lo(irq_handler)
    li a1, 0xff000000
    sw a0, 0(a1)
    
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
    
    # do invalid access
    li a0, 32768
    lw a1, 0(a0)
    
    ebreak
