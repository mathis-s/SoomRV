	.file	"sort.c"
	.option nopic
	.attribute arch, "rv32i2p0_f2p0_d2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.globl	_start
	.type	_start, @function
_start:
	li sp, 2048
	addi	sp,sp,-16
	sw	ra,12(sp)
	call	main
.L2:
	j	end
	.size	_start, .-_start
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"Hello, World\n"
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	sw	ra,12(sp)
	lui	a0,%hi(.LC0)
	addi	a0,a0,%lo(.LC0)
	call	print
	li	a0,0
	lw	ra,12(sp)
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.align	2
	.type	print, @function
print:
	lbu	a5,0(a0)
	beq	a5,zero,.L6
.L8:
	addi	a0,a0,1
	sb	a5,1023(zero)
	lbu	a5,0(a0)
	bne	a5,zero,.L8
.L6:
	ret
end:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	.size	print, .-print
	.ident	"GCC: (g5964b5cd727) 11.1.0"
