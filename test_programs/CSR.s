	.file	"CSR.c"
	.option nopic
	.attribute arch, "rv32i2p0_f2p0_d2p0_zba_zbb"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"Reading cycles 100 times:\n"
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	lui	a5,%hi(.LC0)
	li	a4,82
	addi	a5,a5,%lo(.LC0)
.L2:
	addi	a5,a5,1
	sb	a4,1023(zero)
	lbu	a4,0(a5)
	bne	a4,zero,.L2
	lui	a3,%hi(.LANCHOR0)
	li	a6,100
	addi	a3,a3,%lo(.LANCHOR0)
	li	t1,-16777216
	li	a4,-33554432
	li	a7,10
.L3:
	lw	a5,128(t1)
	addi	a6,a6,-1
	srli	a2,a5,28
	srli	a0,a5,24
	add	a2,a3,a2
	srli	a1,a5,20
	andi	a0,a0,15
	lbu	t3,0(a2)
	add	a0,a3,a0
	srli	a2,a5,16
	andi	a1,a1,15
	lbu	t5,0(a0)
	add	a1,a3,a1
	srli	a0,a5,12
	andi	a2,a2,15
	lbu	t4,0(a1)
	add	a2,a3,a2
	srli	a1,a5,8
	andi	a0,a0,15
	sb	t3,0(a4)
	add	a0,a3,a0
	lbu	t3,0(a2)
	andi	a1,a1,15
	srli	a2,a5,4
	sb	t5,0(a4)
	lbu	a0,0(a0)
	add	a1,a3,a1
	andi	a2,a2,15
	sb	t4,0(a4)
	lbu	a1,0(a1)
	add	a2,a3,a2
	andi	a5,a5,15
	sb	t3,0(a4)
	lbu	a2,0(a2)
	add	a5,a3,a5
	sb	a0,0(a4)
	lbu	a5,0(a5)
	sb	a1,0(a4)
	sb	a2,0(a4)
	sb	a5,0(a4)
	sb	a7,0(a4)
	bne	a6,zero,.L3
	li	a0,0
	ret
	.size	main, .-main
	.section	.rodata
	.align	2
	.set	.LANCHOR0,. + 0
	.type	hexLut, @object
	.size	hexLut, 16
hexLut:
	.ascii	"0123456789abcdef"
	.ident	"GCC: (g5964b5cd727) 11.1.0"
