	.file	"primes.c"
	.option nopic
	.attribute arch, "rv32i2p0_f2p0_d2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.globl	sieve
	.bss
	.align	2
	.type	sieve, @object
	.size	sieve, 512
sieve:
	.zero	512
	.text
	.align	2
	.globl	mark
	.type	mark, @function
mark:
	srli	a4,a0,1
	add	a4,a4,a0
	srli	a5,a4,5
	li	a3,127
	bgtu	a5,a3,.L1
	lui	a1,%hi(sieve)
	addi	a1,a1,%lo(sieve)
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
	li	a5,10
	sb	a5,0(a4)
	ret
	.size	printhex, .-printhex
	.align	2
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
	lui	s4,%hi(sieve)
	addi	s4,s4,%lo(sieve)
	li	s6,1
.L9:
	mv	a0,s2
	call	mark
	j	.L7
.L10:
	addi	s2,s2,2
	addi	s0,s0,1
	slli	a4,s1,2
	add	a4,s4,a4
	sll	a5,s6,s0
	lw	a4,0(a4)
	and	a5,a5,a4
	beq	a5,zero,.L13
.L7:
	ble	s0,s3,.L10
	addi	s1,s1,1
	beq	s1,s5,.L14
	li	s0,-1
	j	.L7
.L13:
	mv	a0,s2
	call	printhex
	j	.L9
.L14:
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
	.ident	"GCC: (g5964b5cd727) 11.1.0"
