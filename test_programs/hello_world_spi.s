	.file	"hello_world_spi.c"
	.option nopic
	.attribute arch, "rv32i2p0_f2p0_d2p0_zba1p0_zbb1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"Hello, World!\n"
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	lui	a5,%hi(.LC0)
	sw	ra,12(sp)
	sw	s0,8(sp)
	sw	s1,4(sp)
	addi	a5,a5,%lo(.LC0)
	li	a3,268435456
.L2:
	lbu	a4,0(a5)
	bne	a4,zero,.L3
	li	s0,0
	li	s1,10
.L4:
	mv	a0,s0
	addi	s0,s0,1
	call	printhex
	bne	s0,s1,.L4
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	s1,4(sp)
	li	a0,0
	addi	sp,sp,16
	jr	ra
.L3:
	addi	a5,a5,1
	sb	a4,0(a3)
	j	.L2
	.size	main, .-main
	.ident	"GCC: (g2ee5e430018) 12.2.0"
	.section	.note.GNU-stack,"",@progbits
