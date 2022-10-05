	.file	"primes.c"
	.option nopic
	.attribute arch, "rv32i2p0_f2p0_d2p0_c2p0_zba_zbb"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	1
	.globl	mark
	.type	mark, @function
mark:
	srli	a4,a0,1
	add	a4,a4,a0
	srli	a5,a4,5
	li	a3,127
	bgtu	a5,a3,.L1
	lui	a1,%hi(.LANCHOR0)
	addi	a1,a1,%lo(.LANCHOR0)
	li	a7,1
	li	a6,127
.L3:
	slli	a5,a5,2
	add	a5,a1,a5
	lw	a2,0(a5)
	sll	a3,a7,a4
	add	a4,a4,a0
	or	a3,a3,a2
	sw	a3,0(a5)
	srli	a5,a4,5
	bleu	a5,a6,.L3
.L1:
	ret
	.size	mark, .-mark
	.section	.text.startup,"ax",@progbits
	.align	1
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	lui	a6,%hi(.LANCHOR0)
	lui	t0,%hi(.LANCHOR1)
	sw	s0,12(sp)
	sw	s1,8(sp)
	sw	s2,4(sp)
	li	a1,1
	li	a0,0
	li	a3,3
	li	t4,127
	addi	a6,a6,%lo(.LANCHOR0)
	li	t1,1
	li	t3,31
	li	t5,128
	addi	t0,t0,%lo(.LANCHOR1)
	li	t6,-33554432
	li	t2,10
.L10:
	srli	a4,a3,1
	add	a4,a4,a3
	srli	a5,a4,5
	bgtu	a5,t4,.L9
.L8:
	slli	a5,a5,2
	add	a5,a6,a5
	lw	a7,0(a5)
	sll	a2,t1,a4
	add	a4,a4,a3
	or	a2,a2,a7
	sw	a2,0(a5)
	srli	a5,a4,5
	bleu	a5,t4,.L8
.L9:
	bne	a1,t3,.L11
	addi	a0,a0,1
	beq	a0,t5,.L16
	li	a4,1
	li	a1,0
.L12:
	slli	a5,a0,2
	add	a5,a6,a5
	lw	a5,0(a5)
	addi	a3,a3,2
	and	a5,a4,a5
	bne	a5,zero,.L9
	srli	a5,a3,28
	srli	a2,a3,24
	add	a5,t0,a5
	andi	a2,a2,15
	srli	a4,a3,20
	lbu	s0,0(a5)
	add	a2,t0,a2
	andi	a4,a4,15
	srli	a5,a3,16
	lbu	a7,0(a2)
	add	a4,t0,a4
	andi	a5,a5,15
	srli	a2,a3,12
	lbu	s1,0(a4)
	add	a5,t0,a5
	andi	a2,a2,15
	srli	a4,a3,8
	sb	s0,0(t6)
	lbu	s2,0(a5)
	add	a2,t0,a2
	andi	a4,a4,15
	srli	a5,a3,4
	sb	a7,0(t6)
	lbu	s0,0(a2)
	add	a4,t0,a4
	andi	a5,a5,15
	sb	s1,0(t6)
	lbu	a7,0(a4)
	add	a5,t0,a5
	andi	a4,a3,15
	sb	s2,0(t6)
	lbu	a2,0(a5)
	add	a5,t0,a4
	sb	s0,0(t6)
	lbu	a5,0(a5)
	sb	a7,0(t6)
	sb	a2,0(t6)
	sb	a5,0(t6)
	sb	t2,0(t6)
	j	.L10
.L11:
	addi	a1,a1,1
	sll	a4,t1,a1
	j	.L12
.L16:
	lw	s0,12(sp)
	lw	s1,8(sp)
	lw	s2,4(sp)
	li	a0,0
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.globl	sieve
	.section	.rodata
	.align	2
	.set	.LANCHOR1,. + 0
	.type	hexLut, @object
	.size	hexLut, 16
hexLut:
	.ascii	"0123456789abcdef"
	.bss
	.align	2
	.set	.LANCHOR0,. + 0
	.type	sieve, @object
	.size	sieve, 512
sieve:
	.zero	512
	.ident	"GCC: (g5964b5cd727) 11.1.0"
