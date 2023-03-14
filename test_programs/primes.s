	.file	"primes.c"
	.option nopic
	.attribute arch, "rv32i2p0_m2p0_a2p0_c2p0_zba1p0_zbb1p0"
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
	lui	a2,%hi(.LANCHOR0)
	addi	a2,a2,%lo(.LANCHOR0)
	li	a6,1
	li	a1,127
.L3:
	sll	a3,a6,a4
	sh2add	a5,a5,a2
	amoor.w zero,a3,0(a5)
	add	a4,a4,a0
	srli	a5,a4,5
	bleu	a5,a1,.L3
.L1:
	ret
	.size	mark, .-mark
	.section	.text.startup,"ax",@progbits
	.align	1
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32
	sw	s3,12(sp)
	lui	s3,%hi(.LANCHOR0)
	sw	s0,24(sp)
	sw	s1,20(sp)
	sw	s2,16(sp)
	sw	s4,8(sp)
	sw	s5,4(sp)
	sw	s6,0(sp)
	sw	ra,28(sp)
	li	s0,1
	li	s2,0
	li	s1,3
	li	s5,127
	addi	s3,s3,%lo(.LANCHOR0)
	li	s4,1
	li	s6,31
.L10:
	srli	a4,s1,1
	add	a4,a4,s1
	srli	a5,a4,5
	bgtu	a5,s5,.L8
.L7:
	sll	a3,s4,a4
	sh2add	a5,a5,s3
	amoor.w tp,a3,0(a5)
	add	a4,a4,s1
	srli	a5,a4,5
	bleu	a5,s5,.L7
.L8:
	bne	s0,s6,.L11
	beq	s2,s5,.L12
	addi	s2,s2,1
	li	s0,-1
.L11:
	sh2add	a5,s2,s3
	lw	a4,0(a5)
	addi	s0,s0,1
	sll	a5,s4,s0
	and	a5,a5,a4
	addi	s1,s1,2
	bne	a5,zero,.L8
	mv	a0,s1
	call	printhex
	j	.L10
.L12:
	lw	ra,28(sp)
	lw	s0,24(sp)
	lw	s1,20(sp)
	lw	s2,16(sp)
	lw	s3,12(sp)
	lw	s4,8(sp)
	lw	s5,4(sp)
	lw	s6,0(sp)
	li	a0,0
	addi	sp,sp,32
	jr	ra
	.size	main, .-main
	.globl	sieve
	.bss
	.align	2
	.set	.LANCHOR0,. + 0
	.type	sieve, @object
	.size	sieve, 512
sieve:
	.zero	512
	.ident	"GCC: (g2ee5e430018) 12.2.0"
	.section	.note.GNU-stack,"",@progbits
