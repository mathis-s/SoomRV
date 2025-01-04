	.file	"hello_world.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0_a2p1_c2p0_zba1p0_zbb1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	1
	.type	print, @function
print:
	addi	sp,sp,-48
	sw	ra,44(sp)
	sw	s0,40(sp)
	addi	s0,sp,48
	sw	a0,-36(s0)
	li	a5,268435456
	sw	a5,-20(s0)
	j	.L2
.L3:
	lw	a5,-36(s0)
	addi	a4,a5,1
	sw	a4,-36(s0)
	lbu	a4,0(a5)
	lw	a5,-20(s0)
	sb	a4,0(a5)
.L2:
	lw	a5,-36(s0)
	lbu	a5,0(a5)
	bne	a5,zero,.L3
	nop
	nop
	lw	ra,44(sp)
	lw	s0,40(sp)
	addi	sp,sp,48
	jr	ra
	.size	print, .-print
	.section	.rodata
	.align	2
.LC0:
	.string	"Hello, World!\n"
	.text
	.align	1
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32
	sw	ra,28(sp)
	sw	s0,24(sp)
	addi	s0,sp,32
	lui	a5,%hi(.LC0)
	addi	a0,a5,%lo(.LC0)
	call	print
	sw	zero,-20(s0)
	j	.L5
.L6:
	lw	a5,-20(s0)
	mv	a0,a5
	call	printhex
	lw	a5,-20(s0)
	addi	a5,a5,1
	sw	a5,-20(s0)
.L5:
	lw	a4,-20(s0)
	li	a5,9
	ble	a4,a5,.L6
	li	a5,0
	mv	a0,a5
	lw	ra,28(sp)
	lw	s0,24(sp)
	addi	sp,sp,32
	jr	ra
	.size	main, .-main
	.ident	"GCC: (g04696df0963) 14.2.0"
	.section	.note.GNU-stack,"",@progbits
