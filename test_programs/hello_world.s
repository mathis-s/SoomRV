	.file	"hello_world.c"
	.option nopic
	.attribute arch, "rv32i2p0_f2p0_d2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.type	print, @function
print:
	lbu	a5,0(a0)
	beq	a5,zero,.L1
.L3:
	addi	a0,a0,1
	sb	a5,1023(zero)
	lbu	a5,0(a0)
	bne	a5,zero,.L3
.L1:
	ret
	.size	print, .-print
	.section	.rodata
	.align	2
	.type	hexLut, @object
	.size	hexLut, 16
hexLut:
	.ascii	"0123456789abcdef"
	.text
	.align	2
	.type	printhex, @function
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
	ret
	.size	printhex, .-printhex
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"Hello, World!\n"
	.align	2
.LC1:
	.string	"\n"
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	sw	ra,12(sp)
	sw	s0,8(sp)
	sw	s1,4(sp)
	sw	s2,0(sp)
	lui	a0,%hi(.LC0)
	addi	a0,a0,%lo(.LC0)
	call	print
	li	s0,0
	lui	s2,%hi(.LC1)
	li	s1,10
.L7:
	mv	a0,s0
	call	printhex
	addi	a0,s2,%lo(.LC1)
	call	print
	addi	s0,s0,1
	bne	s0,s1,.L7
	li	a0,0
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	s1,4(sp)
	lw	s2,0(sp)
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.ident	"GCC: (g5964b5cd727) 11.1.0"
