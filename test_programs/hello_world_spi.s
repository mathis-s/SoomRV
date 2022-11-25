	.file	"hello_world_spi.c"
	.option nopic
	.attribute arch, "rv32i2p0_m2p0_c2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"Hello, World!\n"
	.section	.text.startup,"ax",@progbits
	.align	1
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	lui	a5,%hi(.LC0)
	sw	ra,12(sp)
	sw	s0,8(sp)
	sw	s1,4(sp)
	li	a4,72
	addi	a5,a5,%lo(.LC0)
	li	a3,-16777216
	.align	4
.L2:
	addi	a5,a5,1
	sb	a4,19(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L2
	li	s0,0
	li	s1,10
	.align	4
.L3:
	mv	a0,s0
	addi	s0,s0,1
	call	printhex
	bne	s0,s1,.L3
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	s1,4(sp)
	li	a0,0
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.ident	"GCC: (g1ea978e3066) 12.1.0"
