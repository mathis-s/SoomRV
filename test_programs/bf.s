	.file	"bf.c"
	.option nopic
	.attribute arch, "rv32i2p0_m2p0_a2p0_c2p0_zba1p0_zbb1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	1
	.globl	translate
	.type	translate, @function
translate:
	lbu	a5,0(a0)
	beq	a5,zero,.L1
	lui	a2,%hi(size)
	lw	a7,%lo(size)(a2)
	lui	t1,%hi(.L5)
	lui	t4,%hi(.LANCHOR0)
	mv	a4,a0
	li	a3,0
	li	a6,50
	addi	t1,t1,%lo(.L5)
	addi	t4,t4,%lo(.LANCHOR0)
	li	t5,128
.L16:
	addi	a5,a5,-43
	andi	a5,a5,0xff
	addi	a4,a4,1
	bgtu	a5,a6,.L3
	sh2add	a5,a5,t1
	lw	a5,0(a5)
	jr	a5
	.section	.rodata
	.align	2
	.align	2
.L5:
	.word	.L12
	.word	.L11
	.word	.L10
	.word	.L9
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L8
	.word	.L3
	.word	.L7
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L3
	.word	.L6
	.word	.L3
	.word	.L4
	.text
.L3:
	add	a5,a4,a7
	sub	a5,a5,a0
	sw	a5,%lo(size)(a2)
	lbu	a5,0(a4)
	bne	a5,zero,.L16
	ret
.L4:
	addi	a1,a3,1
	li	a5,3
.L15:
	add	t3,a4,a7
	sub	t3,t3,a0
	sw	t3,%lo(size)(a2)
	sh2add	a3,a3,t4
	sw	a5,0(a3)
	lbu	a5,0(a4)
	beq	a5,zero,.L1
	beq	a1,t5,.L1
	mv	a3,a1
	j	.L16
.L6:
	addi	a1,a3,1
	li	a5,2
	j	.L15
.L7:
	addi	a1,a3,1
	li	a5,5
	j	.L15
.L8:
	addi	a1,a3,1
	li	a5,4
	j	.L15
.L9:
	addi	a1,a3,1
	li	a5,6
	j	.L15
.L10:
	addi	a1,a3,1
	li	a5,1
	j	.L15
.L11:
	addi	a1,a3,1
	li	a5,7
	j	.L15
.L12:
	addi	a1,a3,1
	li	a5,0
	j	.L15
.L1:
	ret
	.size	translate, .-translate
	.align	1
	.globl	run
	.type	run, @function
run:
	lui	t5,%hi(size)
	lw	a6,%lo(size)(t5)
	li	a2,0
	beq	a6,zero,.L51
	lui	a1,%hi(.LANCHOR0)
	lui	a0,%hi(.L44)
	li	a4,0
	li	t3,0
	addi	a1,a1,%lo(.LANCHOR0)
	addi	a0,a0,%lo(.L44)
	li	t1,7
	li	t6,268435456
	li	t4,2
.L22:
	sh2add	a3,a4,a1
	lw	a5,0(a3)
.L43:
	bgtu	a5,t1,.L43
	sh2add	a5,a5,a0
	lw	a5,0(a5)
	jr	a5
	.section	.rodata
	.align	2
	.align	2
.L44:
	.word	.L24
	.word	.L26
	.word	.L27
	.word	.L33
	.word	.L39
	.word	.L40
	.word	.L41
	.word	.L42
	.text
.L41:
	sb	a2,0(t6)
	lw	a6,%lo(size)(t5)
.L50:
	addi	a4,a4,1
.L25:
	bltu	a4,a6,.L22
.L52:
	ret
.L40:
	add	a5,a1,t3
	addi	t3,t3,1
	sb	a2,512(a5)
	add	a5,a1,t3
	lbu	a2,512(a5)
	addi	a4,a4,1
	j	.L25
.L39:
	add	a5,a1,t3
	addi	t3,t3,-1
	sb	a2,512(a5)
	addi	a4,a4,1
	add	a5,a1,t3
	lbu	a2,512(a5)
	bltu	a4,a6,.L22
	j	.L52
.L33:
	li	a7,0
	bne	a2,zero,.L38
	addi	a4,a4,1
	j	.L25
.L53:
	addi	a5,a5,-3
	seqz	a5,a5
	sub	a7,a7,a5
.L37:
	addi	a5,a4,-1
	addi	a3,a3,-4
	beq	a7,zero,.L50
	mv	a4,a5
.L38:
	lw	a5,0(a3)
	bne	a5,t4,.L53
	addi	a7,a7,1
	j	.L37
.L27:
	bne	a2,zero,.L50
	li	a7,0
	j	.L32
.L54:
	addi	a5,a5,-3
	seqz	a5,a5
	sub	a7,a7,a5
.L31:
	addi	a4,a4,1
	addi	a3,a3,4
	beq	a7,zero,.L25
.L32:
	lw	a5,0(a3)
	bne	a5,t4,.L54
	addi	a7,a7,1
	j	.L31
.L24:
	addi	a2,a2,1
	addi	a4,a4,1
	andi	a2,a2,0xff
	bltu	a4,a6,.L22
	j	.L52
.L26:
	addi	a2,a2,-1
	addi	a4,a4,1
	andi	a2,a2,0xff
	bltu	a4,a6,.L22
	j	.L52
.L42:
	addi	a4,a4,1
	li	a2,0
	bltu	a4,a6,.L22
	j	.L52
.L51:
	ret
	.size	run, .-run
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------.>+.>."
	.section	.text.startup,"ax",@progbits
	.align	1
	.globl	main
	.type	main, @function
main:
	lui	a0,%hi(.LC0)
	addi	sp,sp,-16
	addi	a0,a0,%lo(.LC0)
	sw	ra,12(sp)
	call	translate
	call	run
	lw	ra,12(sp)
	li	a0,0
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.globl	size
	.globl	tape
	.globl	instrs
	.bss
	.align	2
	.set	.LANCHOR0,. + 0
	.type	instrs, @object
	.size	instrs, 512
instrs:
	.zero	512
	.type	tape, @object
	.size	tape, 128
tape:
	.zero	128
	.section	.sbss,"aw",@nobits
	.align	2
	.type	size, @object
	.size	size, 4
size:
	.zero	4
	.ident	"GCC: (g2ee5e430018) 12.2.0"
	.section	.note.GNU-stack,"",@progbits
