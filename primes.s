	.file	"primes.c"
	.option nopic
	.attribute arch, "rv32i2p0_m2p0_a2p0_f2p0_d2p0_c2p0"
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
	sll	a3,a7,a4
	lw	a2,0(a5)
	or	a3,a3,a2
	sw	a3,0(a5)
	add	a4,a4,a0
	srli	a5,a4,5
	bleu	a5,a6,.L3
.L1:
	ret
	.size	mark, .-mark
	.align	1
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32
	sw	ra,28(sp)
	sw	s0,24(sp)
	sw	s1,20(sp)
	sw	s2,16(sp)
	sw	s3,12(sp)
	sw	s4,8(sp)
	sw	s5,4(sp)
	sw	s6,0(sp)
	li	s0,1
	li	s1,0
	li	s2,3
	li	s3,30
	li	s5,128
	lui	s4,%hi(.LANCHOR0)
	addi	s4,s4,%lo(.LANCHOR0)
	lui	s6,%hi(.LANCHOR1)
	addi	s6,s6,%lo(.LANCHOR1)
.L8:
	mv	a0,s2
	call	mark
	li	a3,1
	j	.L6
.L9:
	addi	s2,s2,2
	addi	s0,s0,1
	slli	a4,s1,2
	add	a4,s4,a4
	sll	a5,a3,s0
	lw	a4,0(a4)
	and	a5,a5,a4
	beq	a5,zero,.L12
.L6:
	ble	s0,s3,.L9
	addi	s1,s1,1
	beq	s1,s5,.L13
	li	s0,-1
	j	.L6
.L12:
	srli	a5,s2,28
	add	a5,s6,a5
	lbu	a4,0(a5)
	li	a5,1023
	sb	a4,0(a5)
	srli	a4,s2,24
	andi	a4,a4,15
	add	a4,s6,a4
	lbu	a4,0(a4)
	sb	a4,0(a5)
	srli	a4,s2,20
	andi	a4,a4,15
	add	a4,s6,a4
	lbu	a4,0(a4)
	sb	a4,0(a5)
	srli	a4,s2,16
	andi	a4,a4,15
	add	a4,s6,a4
	lbu	a4,0(a4)
	sb	a4,0(a5)
	srli	a4,s2,12
	andi	a4,a4,15
	add	a4,s6,a4
	lbu	a4,0(a4)
	sb	a4,0(a5)
	srli	a4,s2,8
	andi	a4,a4,15
	add	a4,s6,a4
	lbu	a4,0(a4)
	sb	a4,0(a5)
	srli	a4,s2,4
	andi	a4,a4,15
	add	a4,s6,a4
	lbu	a4,0(a4)
	sb	a4,0(a5)
	andi	a4,s2,15
	add	a4,s6,a4
	lbu	a4,0(a4)
	sb	a4,0(a5)
	li	a4,10
	sb	a4,0(a5)
	j	.L8
.L13:
	li	a0,0
	lw	ra,28(sp)
	lw	s0,24(sp)
	lw	s1,20(sp)
	lw	s2,16(sp)
	lw	s3,12(sp)
	lw	s4,8(sp)
	lw	s5,4(sp)
	lw	s6,0(sp)
	addi	sp,sp,32
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
