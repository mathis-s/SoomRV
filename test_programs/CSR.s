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
	lui	a4,%hi(.LANCHOR0)
	li	a0,100
	addi	a4,a4,%lo(.LANCHOR0)
	li	a7,-16777216
	li	a6,10
.L3:
	lw	a5,64(a7)
	addi	a0,a0,-1
	srli	a3,a5,28
	srli	a1,a5,24
	add	a3,a4,a3
	srli	a2,a5,20
	andi	a1,a1,15
	lbu	t1,0(a3)
	add	a1,a4,a1
	srli	a3,a5,16
	andi	a2,a2,15
	lbu	t4,0(a1)
	add	a2,a4,a2
	srli	a1,a5,12
	andi	a3,a3,15
	lbu	t3,0(a2)
	add	a3,a4,a3
	srli	a2,a5,8
	andi	a1,a1,15
	sb	t1,1023(zero)
	add	a1,a4,a1
	lbu	t1,0(a3)
	andi	a2,a2,15
	srli	a3,a5,4
	sb	t4,1023(zero)
	lbu	a1,0(a1)
	add	a2,a4,a2
	andi	a3,a3,15
	sb	t3,1023(zero)
	lbu	a2,0(a2)
	add	a3,a4,a3
	andi	a5,a5,15
	sb	t1,1023(zero)
	lbu	a3,0(a3)
	add	a5,a4,a5
	sb	a1,1023(zero)
	lbu	a5,0(a5)
	sb	a2,1023(zero)
	sb	a3,1023(zero)
	sb	a5,1023(zero)
	sb	a6,1023(zero)
	bne	a0,zero,.L3
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
