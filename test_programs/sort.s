	.file	"sort.c"
	.option nopic
	.text
	.align	1
	.type	quick_sort, @function
quick_sort:
	ble	a1,a0,.L74
	addi	sp,sp,-96
	sw	s0,88(sp)
	lui	s0,%hi(list)
	addi	s0,s0,%lo(list)
	slli	a6,a1,2
	sw	ra,92(sp)
	sw	s1,84(sp)
	sw	s2,80(sp)
	sw	s3,76(sp)
	sw	s4,72(sp)
	sw	s5,68(sp)
	sw	s6,64(sp)
	sw	s7,60(sp)
	sw	s8,56(sp)
	sw	s9,52(sp)
	sw	s10,48(sp)
	sw	s11,44(sp)
	mv	a2,a1
	add	a6,s0,a6
.L2:
	lw	t1,0(a6)
	addi	a5,a0,-1
	slli	a4,a0,2
	mv	s11,a5
	add	a3,s0,a4
	mv	a1,a0
.L4:
	lw	a7,0(a3)
	addi	a1,a1,1
	bltu	t1,a7,.L3
	addi	s11,s11,1
	slli	s1,s11,2
	add	s1,s0,s1
	lw	t3,0(s1)
	sw	a7,0(s1)
	sw	t3,0(a3)
.L3:
	addi	a3,a3,4
	bgt	a2,a1,.L4
	addi	a3,s11,1
	slli	a3,a3,2
	lw	a7,0(a6)
	add	a3,s0,a3
	lw	a1,0(a3)
	sw	a7,0(a3)
	slli	s1,s11,2
	sw	a1,0(a6)
	add	s1,s0,s1
	ble	s11,a0,.L10
.L5:
	lw	t1,0(s1)
	mv	s9,a5
	add	a3,s0,a4
	mv	a1,a0
.L8:
	lw	a7,0(a3)
	addi	a1,a1,1
	bltu	t1,a7,.L7
	addi	s9,s9,1
	slli	s2,s9,2
	add	s2,s0,s2
	lw	t3,0(s2)
	sw	a7,0(s2)
	sw	t3,0(a3)
.L7:
	addi	a3,a3,4
	bgt	s11,a1,.L8
	addi	a3,s9,1
	slli	a3,a3,2
	lw	a7,0(s1)
	add	a3,s0,a3
	lw	a1,0(a3)
	sw	a7,0(a3)
	slli	s2,s9,2
	sw	a1,0(s1)
	add	s2,s0,s2
	ble	s9,a0,.L14
.L9:
	lw	t1,0(s2)
	mv	s10,a5
	add	a3,s0,a4
	mv	a1,a0
.L12:
	lw	a7,0(a3)
	addi	a1,a1,1
	bltu	t1,a7,.L11
	addi	s10,s10,1
	slli	s3,s10,2
	add	s3,s0,s3
	lw	t3,0(s3)
	sw	a7,0(s3)
	sw	t3,0(a3)
.L11:
	addi	a3,a3,4
	bgt	s9,a1,.L12
	addi	a3,s10,1
	slli	a3,a3,2
	lw	a7,0(s2)
	add	a3,s0,a3
	lw	a1,0(a3)
	sw	a7,0(a3)
	slli	s3,s10,2
	sw	a1,0(s2)
	add	s3,s0,s3
	ble	s10,a0,.L18
.L13:
	lw	t3,0(s3)
	mv	a3,a5
	add	a1,s0,a4
	mv	a7,a0
.L16:
	lw	t1,0(a1)
	addi	a7,a7,1
	bltu	t3,t1,.L15
	addi	a3,a3,1
	slli	s4,a3,2
	add	s4,s0,s4
	lw	t4,0(s4)
	sw	t1,0(s4)
	sw	t4,0(a1)
.L15:
	addi	a1,a1,4
	bgt	s10,a7,.L16
	addi	a1,a3,1
	slli	a1,a1,2
	lw	t1,0(s3)
	add	a1,s0,a1
	lw	a7,0(a1)
	sw	t1,0(a1)
	slli	s4,a3,2
	sw	a7,0(s3)
	add	s4,s0,s4
	ble	a3,a0,.L22
.L17:
	lw	t4,0(s4)
	mv	a7,a5
	add	a1,s0,a4
	mv	t1,a0
.L20:
	lw	t3,0(a1)
	addi	t1,t1,1
	bltu	t4,t3,.L19
	addi	a7,a7,1
	slli	s5,a7,2
	add	s5,s0,s5
	lw	t5,0(s5)
	sw	t3,0(s5)
	sw	t5,0(a1)
.L19:
	addi	a1,a1,4
	bgt	a3,t1,.L20
	addi	a1,a7,1
	slli	a1,a1,2
	lw	t3,0(s4)
	add	a1,s0,a1
	lw	t1,0(a1)
	sw	t3,0(a1)
	slli	s5,a7,2
	sw	t1,0(s4)
	add	s5,s0,s5
	ble	a7,a0,.L26
.L21:
	lw	t5,0(s5)
	mv	t1,a5
	add	a1,s0,a4
	mv	t3,a0
.L24:
	lw	t4,0(a1)
	addi	t3,t3,1
	bltu	t5,t4,.L23
	addi	t1,t1,1
	slli	s6,t1,2
	add	s6,s0,s6
	lw	t6,0(s6)
	sw	t4,0(s6)
	sw	t6,0(a1)
.L23:
	addi	a1,a1,4
	bgt	a7,t3,.L24
	addi	a1,t1,1
	slli	a1,a1,2
	lw	t4,0(s5)
	add	a1,s0,a1
	lw	t3,0(a1)
	sw	t4,0(a1)
	slli	s6,t1,2
	sw	t3,0(s5)
	add	s6,s0,s6
	ble	t1,a0,.L30
.L25:
	lw	t6,0(s6)
	mv	t3,a5
	add	a1,s0,a4
	mv	t4,a0
.L28:
	lw	t5,0(a1)
	addi	t4,t4,1
	bltu	t6,t5,.L27
	addi	t3,t3,1
	slli	s7,t3,2
	add	s7,s0,s7
	lw	t0,0(s7)
	sw	t5,0(s7)
	sw	t0,0(a1)
.L27:
	addi	a1,a1,4
	bgt	t1,t4,.L28
	addi	a1,t3,1
	slli	a1,a1,2
	lw	t5,0(s6)
	add	a1,s0,a1
	lw	t4,0(a1)
	sw	t5,0(a1)
	slli	s7,t3,2
	sw	t4,0(s6)
	add	s7,s0,s7
	ble	t3,a0,.L34
.L29:
	lw	t0,0(s7)
	mv	t4,a5
	add	a1,s0,a4
	mv	t5,a0
.L32:
	lw	t6,0(a1)
	addi	t5,t5,1
	bltu	t0,t6,.L31
	addi	t4,t4,1
	slli	s8,t4,2
	add	s8,s0,s8
	lw	t2,0(s8)
	sw	t6,0(s8)
	sw	t2,0(a1)
.L31:
	addi	a1,a1,4
	bgt	t3,t5,.L32
	addi	a1,t4,1
	slli	a1,a1,2
	lw	t6,0(s7)
	add	a1,s0,a1
	lw	t5,0(a1)
	sw	t6,0(a1)
	slli	s8,t4,2
	sw	t5,0(s7)
	add	s8,s0,s8
	ble	t4,a0,.L37
.L33:
	lw	t6,0(s8)
	add	a4,s0,a4
	mv	t5,a0
.L36:
	lw	t0,0(a4)
	addi	t5,t5,1
	bltu	t6,t0,.L35
	addi	a5,a5,1
	slli	a1,a5,2
	add	a1,s0,a1
	lw	t2,0(a1)
	sw	t0,0(a1)
	sw	t2,0(a4)
.L35:
	addi	a4,a4,4
	bgt	t4,t5,.L36
	addi	a4,a5,1
	slli	a4,a4,2
	lw	a1,0(s8)
	add	a4,s0,a4
	lw	t5,0(a4)
	sw	a1,0(a4)
	mv	a1,a5
	sw	t5,0(s8)
	sw	a6,28(sp)
	sw	a2,24(sp)
	sw	t4,20(sp)
	sw	t3,16(sp)
	sw	t1,12(sp)
	sw	a7,8(sp)
	sw	a3,4(sp)
	sw	a5,0(sp)
	call	quick_sort
	lw	a5,0(sp)
	lw	t4,20(sp)
	lw	a3,4(sp)
	addi	a0,a5,2
	lw	a7,8(sp)
	lw	t1,12(sp)
	lw	t3,16(sp)
	lw	a2,24(sp)
	lw	a6,28(sp)
	bge	a0,t4,.L37
	addi	a5,a5,1
	slli	a4,a0,2
	j	.L33
.L10:
	addi	a0,s11,2
	blt	a0,a2,.L2
	lw	ra,92(sp)
	lw	s0,88(sp)
	lw	s1,84(sp)
	lw	s2,80(sp)
	lw	s3,76(sp)
	lw	s4,72(sp)
	lw	s5,68(sp)
	lw	s6,64(sp)
	lw	s7,60(sp)
	lw	s8,56(sp)
	lw	s9,52(sp)
	lw	s10,48(sp)
	lw	s11,44(sp)
	addi	sp,sp,96
	jr	ra
.L37:
	addi	a0,t4,2
	bge	a0,t3,.L34
	addi	a5,t4,1
	slli	a4,a0,2
	j	.L29
.L26:
	addi	a0,a7,2
	bge	a0,a3,.L22
	addi	a5,a7,1
	slli	a4,a0,2
	j	.L17
.L30:
	addi	a0,t1,2
	bge	a0,a7,.L26
	addi	a5,t1,1
	slli	a4,a0,2
	j	.L21
.L22:
	addi	a0,a3,2
	bge	a0,s10,.L18
	addi	a5,a3,1
	slli	a4,a0,2
	j	.L13
.L34:
	addi	a0,t3,2
	bge	a0,t1,.L30
	addi	a5,t3,1
	slli	a4,a0,2
	j	.L25
.L18:
	addi	a0,s10,2
	bge	a0,s9,.L14
	addi	a5,s10,1
	slli	a4,a0,2
	j	.L9
.L14:
	addi	a0,s9,2
	bge	a0,s11,.L10
	addi	a5,s9,1
	slli	a4,a0,2
	j	.L5
.L74:
	ret
	.size	quick_sort, .-quick_sort
	.section	.text.startup,"ax",@progbits
	.align	1
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	lui	a2,%hi(list)
	sw	s0,8(sp)
	sw	s1,4(sp)
	addi	s0,a2,%lo(list)
	li	s1,65536
	li	a5,-559038464
	sw	ra,12(sp)
	add	s1,s0,s1
	addi	a2,a2,%lo(list)
	addi	a5,a5,-273
	.align	3
.L79:
	slli	a3,a5,13
	xor	a3,a3,a5
	srli	a4,a3,17
	xor	a4,a4,a3
	sw	a5,0(a2)
	slli	a5,a4,5
	addi	a2,a2,4
	xor	a5,a5,a4
	bne	a2,s1,.L79
	li	a1,16384
	addi	a1,a1,-1
	li	a0,0
	call	quick_sort
	.align	3
.L80:
	lw	a0,0(s0)
	addi	s0,s0,4
	call	printhex
	bne	s0,s1,.L80
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	s1,4(sp)
	li	a0,0
	addi	sp,sp,16
	jr	ra
	.size	main, .-main
	.globl	list
	.bss
	.align	2
	.type	list, @object
	.size	list, 65536
list:
	.zero	65536
	.ident	"GCC: (g5964b5cd727) 11.1.0"
	.section	.note.GNU-stack,"",@progbits
