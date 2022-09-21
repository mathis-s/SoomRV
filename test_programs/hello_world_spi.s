	.file	"hello_world_spi.c"
	.option nopic
	.attribute arch, "rv32i2p0_f2p0_d2p0_zba_zbb"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"Hello, World!\n"
	.align	2
.LC1:
	.string	"\n"
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	lui	a5,%hi(.LC0)
	addi	a5,a5,%lo(.LC0)
	li	a3,-16777216
.L2:
	lbu	a4,0(a5)
	bne	a4,zero,.L3
	li	a5,-16777216
	lui	a2,%hi(.LANCHOR0)
	li	a3,0
	addi	a5,a5,19
	li	a4,48
	addi	a2,a2,%lo(.LANCHOR0)
	lui	a7,%hi(.LC1)
	li	a6,10
.L6:
	sb	a4,0(a5)
	sb	a4,0(a5)
	sb	a4,0(a5)
	sb	a4,0(a5)
	sb	a4,0(a5)
	sb	a4,0(a5)
	sb	a4,0(a5)
	add	a1,a2,a3
	lbu	a1,0(a1)
	sb	a1,0(a5)
	addi	a1,a7,%lo(.LC1)
.L4:
	lbu	a0,0(a1)
	bne	a0,zero,.L5
	addi	a3,a3,1
	bne	a3,a6,.L6
	ret
.L3:
	addi	a5,a5,1
	sb	a4,19(a3)
	j	.L2
.L5:
	addi	a1,a1,1
	sb	a0,0(a5)
	j	.L4
	.size	main, .-main
	.section	.rodata
	.align	2
	.set	.LANCHOR0,. + 0
	.type	hexLut, @object
	.size	hexLut, 16
hexLut:
	.ascii	"0123456789abcdef"
	.ident	"GCC: (g5964b5cd727) 11.1.0"
