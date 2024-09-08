	.file	"dhry_1.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0_a2p1_c2p0_zicsr2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	1
	.type	printhex, @function
printhex:
	lui	a5,%hi(.LANCHOR0)
	addi	a5,a5,%lo(.LANCHOR0)
	srli	a3,a0,28
	srli	a4,a0,24
	add	a3,a5,a3
	srli	a2,a0,20
	andi	a4,a4,15
	lbu	a6,0(a3)
	add	a4,a5,a4
	srli	a3,a0,16
	andi	a2,a2,15
	add	a2,a5,a2
	lbu	t1,0(a4)
	srli	a1,a0,12
	andi	a3,a3,15
	li	a4,268435456
	add	a3,a5,a3
	lbu	a7,0(a2)
	andi	a1,a1,15
	srli	a2,a0,8
	sb	a6,0(a4)
	add	a1,a5,a1
	lbu	a6,0(a3)
	andi	a2,a2,15
	srli	a3,a0,4
	sb	t1,0(a4)
	add	a2,a5,a2
	lbu	a1,0(a1)
	andi	a3,a3,15
	sb	a7,0(a4)
	add	a3,a5,a3
	lbu	a2,0(a2)
	andi	a0,a0,15
	sb	a6,0(a4)
	lbu	a3,0(a3)
	add	a5,a5,a0
	sb	a1,0(a4)
	lbu	a5,0(a5)
	sb	a2,0(a4)
	sb	a3,0(a4)
	sb	a5,0(a4)
	li	a5,10
	sb	a5,0(a4)
	ret
	.size	printhex, .-printhex
	.align	1
	.type	Func_1.constprop.0, @function
Func_1.constprop.0:
	li	a5,67
	beq	a0,a5,.L6
	li	a0,0
	ret
.L6:
	lui	a5,%hi(Ch_1_Glob)
	sb	a0,%lo(Ch_1_Glob)(a5)
	li	a0,1
	ret
	.size	Func_1.constprop.0, .-Func_1.constprop.0
	.align	1
	.type	Func_3.constprop.0, @function
Func_3.constprop.0:
	li	a0,0
	ret
	.size	Func_3.constprop.0, .-Func_3.constprop.0
	.align	1
	.type	Proc_6.constprop.0.isra.0, @function
Proc_6.constprop.0.isra.0:
	sw	zero,0(a0)
	ret
	.size	Proc_6.constprop.0.isra.0, .-Proc_6.constprop.0.isra.0
	.align	1
	.type	Proc_7.constprop.0.isra.0, @function
Proc_7.constprop.0.isra.0:
	addi	a0,a0,5
	sw	a0,0(a1)
	ret
	.size	Proc_7.constprop.0.isra.0, .-Proc_7.constprop.0.isra.0
	.align	1
	.type	Proc_8.constprop.0.isra.0, @function
Proc_8.constprop.0.isra.0:
	addi	a2,a0,5
	li	a5,200
	mul	a5,a2,a5
	slli	a0,a0,2
	lui	a4,%hi(Arr_2_Glob)
	addi	a4,a4,%lo(Arr_2_Glob)
	lui	a3,%hi(.LANCHOR1)
	slli	a6,a2,2
	addi	a3,a3,%lo(.LANCHOR1)
	add	a3,a3,a6
	sw	a1,0(a3)
	sw	a1,4(a3)
	add	a5,a5,a0
	add	a4,a5,a4
	lw	a0,16(a4)
	sw	a2,20(a4)
	sw	a2,24(a4)
	addi	a0,a0,1
	sw	a0,16(a4)
	lui	a4,%hi(Arr_2_Glob+4000)
	addi	a4,a4,%lo(Arr_2_Glob+4000)
	add	a5,a5,a4
	sw	a1,20(a5)
	li	a4,5
	lui	a5,%hi(Int_Glob)
	sw	a2,120(a3)
	sw	a4,%lo(Int_Glob)(a5)
	ret
	.size	Proc_8.constprop.0.isra.0, .-Proc_8.constprop.0.isra.0
	.align	1
	.globl	malloc
	.type	malloc, @function
malloc:
	lui	a4,%hi(mallocPtr)
	lw	a5,%lo(mallocPtr)(a4)
	add	a0,a5,a0
	sw	a0,%lo(mallocPtr)(a4)
	mv	a0,a5
	ret
	.size	malloc, .-malloc
	.align	1
	.globl	printf
	.type	printf, @function
printf:
	lbu	t1,0(a0)
	addi	sp,sp,-32
	sw	a1,4(sp)
	sw	a2,8(sp)
	sw	a3,12(sp)
	sw	a4,16(sp)
	sw	a5,20(sp)
	sw	a6,24(sp)
	sw	a7,28(sp)
	beq	t1,zero,.L12
	li	a5,268435456
.L14:
	addi	a0,a0,1
	sb	t1,0(a5)
	lbu	t1,0(a0)
	bne	t1,zero,.L14
.L12:
	addi	sp,sp,32
	jr	ra
	.size	printf, .-printf
	.align	1
	.globl	Proc_2
	.type	Proc_2, @function
Proc_2:
	lui	a5,%hi(Ch_1_Glob)
	lbu	a4,%lo(Ch_1_Glob)(a5)
	li	a5,65
	beq	a4,a5,.L22
	ret
.L22:
	lw	a5,0(a0)
	lui	a4,%hi(Int_Glob)
	lw	a4,%lo(Int_Glob)(a4)
	addi	a5,a5,9
	sub	a5,a5,a4
	sw	a5,0(a0)
	ret
	.size	Proc_2, .-Proc_2
	.align	1
	.globl	Proc_4
	.type	Proc_4, @function
Proc_4:
	lui	a5,%hi(Ch_1_Glob)
	lbu	a5,%lo(Ch_1_Glob)(a5)
	lui	a4,%hi(Bool_Glob)
	lw	a3,%lo(Bool_Glob)(a4)
	addi	a5,a5,-65
	seqz	a5,a5
	or	a5,a5,a3
	sw	a5,%lo(Bool_Glob)(a4)
	lui	a5,%hi(Ch_2_Glob)
	li	a4,66
	sb	a4,%lo(Ch_2_Glob)(a5)
	ret
	.size	Proc_4, .-Proc_4
	.align	1
	.globl	Proc_5
	.type	Proc_5, @function
Proc_5:
	lui	a5,%hi(Ch_1_Glob)
	li	a4,65
	sb	a4,%lo(Ch_1_Glob)(a5)
	lui	a5,%hi(Bool_Glob)
	sw	zero,%lo(Bool_Glob)(a5)
	ret
	.size	Proc_5, .-Proc_5
	.align	1
	.globl	Proc_7
	.type	Proc_7, @function
Proc_7:
	addi	a0,a0,2
	add	a1,a0,a1
	sw	a1,0(a2)
	ret
	.size	Proc_7, .-Proc_7
	.align	1
	.globl	Proc_3
	.type	Proc_3, @function
Proc_3:
	lui	a5,%hi(Ptr_Glob)
	lw	a2,%lo(Ptr_Glob)(a5)
	beq	a2,zero,.L27
	lw	a4,0(a2)
	sw	a4,0(a0)
	lw	a2,%lo(Ptr_Glob)(a5)
.L27:
	lui	a5,%hi(Int_Glob)
	lw	a1,%lo(Int_Glob)(a5)
	addi	a2,a2,12
	li	a0,10
	tail	Proc_7
	.size	Proc_3, .-Proc_3
	.align	1
	.globl	Proc_8
	.type	Proc_8, @function
Proc_8:
	addi	a4,a2,5
	li	a6,200
	mul	a6,a4,a6
	slli	a2,a2,2
	slli	a5,a4,2
	add	a0,a0,a5
	sw	a3,0(a0)
	sw	a4,120(a0)
	sw	a3,4(a0)
	add	a5,a6,a2
	add	a5,a1,a5
	lw	a3,16(a5)
	sw	a4,20(a5)
	sw	a4,24(a5)
	addi	a4,a3,1
	sw	a4,16(a5)
	lw	a4,0(a0)
	add	a1,a1,a6
	add	a1,a1,a2
	li	a5,4096
	add	a5,a5,a1
	sw	a4,-76(a5)
	lui	a5,%hi(Int_Glob)
	li	a4,5
	sw	a4,%lo(Int_Glob)(a5)
	ret
	.size	Proc_8, .-Proc_8
	.align	1
	.globl	Func_1
	.type	Func_1, @function
Func_1:
	andi	a0,a0,0xff
	andi	a1,a1,0xff
	beq	a0,a1,.L35
	li	a0,0
	ret
.L35:
	lui	a5,%hi(Ch_1_Glob)
	sb	a0,%lo(Ch_1_Glob)(a5)
	li	a0,1
	ret
	.size	Func_1, .-Func_1
	.align	1
	.globl	Func_2
	.type	Func_2, @function
Func_2:
	addi	sp,sp,-16
	sw	s0,8(sp)
	sw	s1,4(sp)
	sw	ra,12(sp)
	mv	s0,a0
	mv	s1,a1
.L37:
	lbu	a1,3(s1)
	lbu	a0,2(s0)
	call	Func_1
	bne	a0,zero,.L37
	mv	a1,s1
	mv	a0,s0
	call	strcmp
	li	a5,0
	ble	a0,zero,.L36
	lui	a5,%hi(Int_Glob)
	li	a4,10
	sw	a4,%lo(Int_Glob)(a5)
	li	a5,1
.L36:
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	s1,4(sp)
	mv	a0,a5
	addi	sp,sp,16
	jr	ra
	.size	Func_2, .-Func_2
	.align	1
	.globl	Func_3
	.type	Func_3, @function
Func_3:
	addi	a0,a0,-2
	seqz	a0,a0
	ret
	.size	Func_3, .-Func_3
	.align	1
	.globl	Proc_6
	.type	Proc_6, @function
Proc_6:
	addi	sp,sp,-16
	sw	s0,8(sp)
	sw	s1,4(sp)
	sw	ra,12(sp)
	mv	s0,a0
	mv	s1,a1
	call	Func_3
	li	a5,3
	beq	a0,zero,.L44
	mv	a5,s0
.L44:
	sw	a5,0(s1)
	li	a5,2
	beq	s0,a5,.L45
	bgtu	s0,a5,.L46
	beq	s0,zero,.L56
	lui	a5,%hi(Int_Glob)
	lw	a4,%lo(Int_Glob)(a5)
	li	a5,100
	ble	a4,a5,.L51
.L56:
	lw	ra,12(sp)
	lw	s0,8(sp)
	sw	zero,0(s1)
	lw	s1,4(sp)
	addi	sp,sp,16
	jr	ra
.L46:
	li	a4,4
	bne	s0,a4,.L50
	sw	a5,0(s1)
.L50:
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	s1,4(sp)
	addi	sp,sp,16
	jr	ra
.L45:
	lw	ra,12(sp)
	lw	s0,8(sp)
	li	a5,1
	sw	a5,0(s1)
	lw	s1,4(sp)
	addi	sp,sp,16
	jr	ra
.L51:
	lw	ra,12(sp)
	lw	s0,8(sp)
	li	a5,3
	sw	a5,0(s1)
	lw	s1,4(sp)
	addi	sp,sp,16
	jr	ra
	.size	Proc_6, .-Proc_6
	.align	1
	.globl	Proc_1
	.type	Proc_1, @function
Proc_1:
	addi	sp,sp,-16
	lui	a5,%hi(Ptr_Glob)
	sw	s2,0(sp)
	lw	s2,%lo(Ptr_Glob)(a5)
	sw	s0,8(sp)
	lw	s0,0(a0)
	lw	a5,0(s2)
	sw	s1,4(sp)
	lw	t5,4(s2)
	lw	t4,8(s2)
	lw	t3,16(s2)
	lw	t1,20(s2)
	lw	a7,24(s2)
	lw	a6,28(s2)
	lw	a1,36(s2)
	lw	a2,40(s2)
	lw	a3,44(s2)
	sw	ra,12(sp)
	mv	s1,a0
	lw	a0,32(s2)
	sw	a5,0(s0)
	lw	a4,0(s1)
	li	a5,5
	sw	a0,32(s0)
	sw	t5,4(s0)
	sw	t4,8(s0)
	sw	t3,16(s0)
	sw	t1,20(s0)
	sw	a7,24(s0)
	sw	a6,28(s0)
	sw	a1,36(s0)
	sw	a2,40(s0)
	sw	a3,44(s0)
	sw	a5,12(s1)
	sw	a5,12(s0)
	sw	a4,0(s0)
	mv	a0,s0
	call	Proc_3
	lw	a5,4(s0)
	beq	a5,zero,.L60
	lw	a5,0(s1)
	lw	ra,12(sp)
	lw	s0,8(sp)
	lw	t6,0(a5)
	lw	t5,4(a5)
	lw	t4,8(a5)
	lw	t3,12(a5)
	lw	t1,16(a5)
	lw	a7,20(a5)
	lw	a6,24(a5)
	lw	a1,28(a5)
	lw	a2,32(a5)
	lw	a3,36(a5)
	lw	a4,40(a5)
	lw	a5,44(a5)
	sw	t6,0(s1)
	sw	t5,4(s1)
	sw	t4,8(s1)
	sw	t3,12(s1)
	sw	t1,16(s1)
	sw	a7,20(s1)
	sw	a6,24(s1)
	sw	a1,28(s1)
	sw	a2,32(s1)
	sw	a3,36(s1)
	sw	a4,40(s1)
	sw	a5,44(s1)
	lw	s2,0(sp)
	lw	s1,4(sp)
	addi	sp,sp,16
	jr	ra
.L60:
	lw	a0,8(s1)
	li	a5,6
	sw	a5,12(s0)
	addi	a1,s0,8
	call	Proc_6
	lw	a5,0(s2)
	addi	a2,s0,12
	lw	ra,12(sp)
	sw	a5,0(s0)
	lw	s0,8(sp)
	lw	s1,4(sp)
	lw	s2,0(sp)
	li	a1,10
	li	a0,6
	addi	sp,sp,16
	tail	Proc_7
	.size	Proc_1, .-Proc_1
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"DHRYSTONE PROGRAM, SOME STRING"
	.align	2
.LC2:
	.string	"\n"
	.align	2
.LC3:
	.string	"Dhrystone Benchmark, Version 2.1 (Language: C)\n"
	.align	2
.LC4:
	.string	"Program compiled with 'register' attribute\n"
	.align	2
.LC5:
	.string	"Program compiled without 'register' attribute\n"
	.align	2
.LC6:
	.string	"Please give the number of runs through the benchmark: "
	.align	2
.LC7:
	.string	"Execution starts, %d runs through Dhrystone\n"
	.align	2
.LC10:
	.string	"Execution ends\n"
	.align	2
.LC11:
	.string	"Final values of the variables used in the benchmark:\n"
	.align	2
.LC12:
	.string	"Int_Glob:            "
	.align	2
.LC13:
	.string	"Bool_Glob:           "
	.align	2
.LC14:
	.string	"Ch_1_Glob:           "
	.align	2
.LC15:
	.string	"Ch_2_Glob:           "
	.align	2
.LC16:
	.string	"Arr_1_Glob[8]:       "
	.align	2
.LC17:
	.string	"Arr_2_Glob[8][7]:    "
	.align	2
.LC18:
	.string	"Ptr_Glob->"
	.align	2
.LC19:
	.string	"Ptr_Comp:          "
	.align	2
.LC20:
	.string	"  Discr:             "
	.align	2
.LC21:
	.string	"  Enum_Comp:         "
	.align	2
.LC22:
	.string	"  Int_Comp:          "
	.align	2
.LC23:
	.string	"  Str_Comp:          "
	.align	2
.LC24:
	.string	"Next_Ptr_Glob->"
	.align	2
.LC25:
	.string	"        should be:   DHRYSTONE PROGRAM, SOME STRING\n"
	.align	2
.LC26:
	.string	"Int_1_Loc:           "
	.align	2
.LC27:
	.string	"Int_2_Loc:           "
	.align	2
.LC28:
	.string	"Int_3_Loc:           "
	.align	2
.LC29:
	.string	"Enum_Loc:            "
	.align	2
.LC30:
	.string	"Str_1_Loc:           "
	.align	2
.LC31:
	.string	"        should be:   DHRYSTONE PROGRAM, 1'ST STRING\n"
	.align	2
.LC32:
	.string	"Str_2_Loc:           "
	.align	2
.LC33:
	.string	"        should be:   DHRYSTONE PROGRAM, 2'ND STRING\n"
	.align	2
.LC34:
	.string	"\n\nRESULTS\n"
	.align	2
.LC35:
	.string	"Runtime (cycles) "
	.align	2
.LC36:
	.string	"Executed (instrs) "
	.align	2
.LC37:
	.string	"mIPC "
	.align	2
.LC38:
	.string	"mDMIPS/MHz "
	.align	2
.LC1:
	.string	"DHRYSTONE PROGRAM, 1'ST STRING"
	.align	2
.LC8:
	.string	"DHRYSTONE PROGRAM, 2'ND STRING"
	.align	2
.LC9:
	.string	"DHRYSTONE PROGRAM, 3'RD STRING"
	.section	.text.startup,"ax",@progbits
	.align	1
	.globl	main
	.type	main, @function
main:
	lui	a5,%hi(.LC0)
	addi	sp,sp,-160
	addi	a5,a5,%lo(.LC0)
	sw	s7,124(sp)
	lw	t0,0(a5)
	lw	t6,4(a5)
	lw	t4,12(a5)
	lw	t3,16(a5)
	li	a3,-2147352576
	lw	t5,8(a5)
	lw	t1,20(a5)
	lw	a7,24(a5)
	lhu	a6,28(a5)
	lbu	a0,30(a5)
	li	a2,-2147356672
	lui	a5,%hi(Next_Ptr_Glob)
	lui	s7,%hi(Ptr_Glob)
	sw	ra,156(sp)
	sw	a2,%lo(Next_Ptr_Glob)(a5)
	sw	s0,152(sp)
	sw	s1,148(sp)
	sw	a3,%lo(Ptr_Glob)(s7)
	sw	s2,144(sp)
	sw	s3,140(sp)
	sw	s4,136(sp)
	sw	s5,132(sp)
	sw	s6,128(sp)
	sw	s8,120(sp)
	sw	s9,116(sp)
	sw	s10,112(sp)
	sw	s11,108(sp)
	sw	a2,0(a3)
	lui	a4,%hi(.LC1)
	li	a2,2
	addi	a4,a4,%lo(.LC1)
	sw	a2,8(a3)
	li	a2,40
	li	a5,-2147352576
	sw	a2,12(a3)
	lw	a1,0(a4)
	sw	zero,4(a3)
	lw	a3,4(a4)
	sw	t0,16(a5)
	sw	t6,20(a5)
	sw	t5,24(a5)
	sw	t4,28(a5)
	sw	t3,32(a5)
	sw	t1,36(a5)
	sw	a7,40(a5)
	sh	a6,44(a5)
	sb	a0,46(a5)
	lw	t1,8(a4)
	lw	a7,12(a4)
	lw	a6,16(a4)
	lw	a2,24(a4)
	sw	a1,32(sp)
	sw	a3,36(sp)
	lw	a1,20(a4)
	lhu	a3,28(a4)
	lbu	a4,30(a4)
	lui	a0,%hi(Arr_2_Glob)
	lui	s0,%hi(.LC2)
	li	a5,10
	addi	s1,a0,%lo(Arr_2_Glob)
	addi	a0,s0,%lo(.LC2)
	sw	a5,1628(s1)
	sw	t1,40(sp)
	sw	a7,44(sp)
	sw	a6,48(sp)
	sw	a1,52(sp)
	sw	a2,56(sp)
	sh	a3,60(sp)
	sb	a4,62(sp)
	sw	s1,12(sp)
	call	printf
	lui	a0,%hi(.LC3)
	addi	a0,a0,%lo(.LC3)
	call	printf
	addi	a0,s0,%lo(.LC2)
	call	printf
	lui	a5,%hi(Reg)
	lw	a5,%lo(Reg)(a5)
	beq	a5,zero,.L62
	lui	a0,%hi(.LC4)
	addi	a0,a0,%lo(.LC4)
	call	printf
	addi	a0,s0,%lo(.LC2)
	call	printf
.L63:
	lui	a0,%hi(.LC6)
	addi	a0,a0,%lo(.LC6)
	call	printf
	lui	a5,%hi(.LC2)
	addi	a0,a5,%lo(.LC2)
	call	printf
	lui	a0,%hi(.LC7)
	li	a1,2000
	addi	a0,a0,%lo(.LC7)
	call	printf
	lui	a4,%hi(Begin_Time)
#APP
# 49 "test_programs/dhry_1.c" 1
	csrr a5, mcycle
# 0 "" 2
#NO_APP
	lui	s2,%hi(.LC8)
	sw	a5,%lo(Begin_Time)(a4)
	lui	a4,%hi(.LC9)
#APP
# 43 "test_programs/dhry_1.c" 1
	csrr a5, minstret
# 0 "" 2
#NO_APP
	li	s3,1
	addi	s2,s2,%lo(.LC8)
	lui	s8,%hi(Bool_Glob)
	lui	s1,%hi(Ch_2_Glob)
	lui	s6,%hi(Int_Glob)
	li	s11,1
	addi	s9,a4,%lo(.LC9)
	sw	a5,8(sp)
.L69:
	call	Proc_5
	call	Proc_4
	lw	t5,0(s2)
	lw	t4,4(s2)
	lw	t3,8(s2)
	lw	t1,12(s2)
	lw	a7,16(s2)
	lw	a6,20(s2)
	lw	a2,24(s2)
	lhu	a3,28(s2)
	lbu	a5,30(s2)
	addi	a1,sp,64
	addi	a0,sp,32
	sw	t5,64(sp)
	sw	t4,68(sp)
	sw	t3,72(sp)
	sw	t1,76(sp)
	sw	a7,80(sp)
	sw	a6,84(sp)
	sw	a2,88(sp)
	sh	a3,92(sp)
	sb	a5,94(sp)
	sw	s11,28(sp)
	call	Func_2
	seqz	a5,a0
	addi	a1,sp,24
	li	a0,2
	sw	a5,%lo(Bool_Glob)(s8)
	call	Proc_7.constprop.0.isra.0
	lw	s5,24(sp)
	li	a5,3
	li	a0,3
	mv	a1,s5
	sw	a5,20(sp)
	call	Proc_8.constprop.0.isra.0
	lw	a0,%lo(Ptr_Glob)(s7)
	call	Proc_1
	lbu	a5,%lo(Ch_2_Glob)(s1)
	li	a4,64
	bleu	a5,a4,.L70
	li	s10,65
	mv	a0,s10
	call	Func_1.constprop.0
	li	s0,1
	li	s4,3
	addi	a3,s10,1
	beq	s0,a0,.L74
.L65:
	lbu	a2,%lo(Ch_2_Glob)(s1)
	andi	s10,a3,0xff
	bltu	a2,s10,.L67
.L66:
	lw	s0,28(sp)
	mv	a0,s10
	call	Func_1.constprop.0
	addi	a3,s10,1
	bne	s0,a0,.L65
.L74:
	addi	a0,sp,28
	call	Proc_6.constprop.0.isra.0
	lw	t5,0(s9)
	lw	t4,4(s9)
	lw	t3,8(s9)
	lw	t1,12(s9)
	lw	a7,16(s9)
	lw	a6,20(s9)
	lw	a0,24(s9)
	lhu	a2,28(s9)
	lbu	a3,30(s9)
	lbu	a1,%lo(Ch_2_Glob)(s1)
	addi	a5,s10,1
	sw	t5,64(sp)
	sw	t4,68(sp)
	sw	t3,72(sp)
	sw	t1,76(sp)
	sw	a7,80(sp)
	sw	a6,84(sp)
	sw	a0,88(sp)
	sh	a2,92(sp)
	sb	a3,94(sp)
	sw	s3,%lo(Int_Glob)(s6)
	andi	s10,a5,0xff
	mv	s4,s3
	bgeu	a1,s10,.L66
.L67:
	slli	s0,s4,1
	add	s0,s0,s4
.L64:
	div	s4,s0,s5
	addi	a0,sp,20
	addi	s3,s3,1
	sw	s4,20(sp)
	call	Proc_2
	li	a5,2001
	bne	s3,a5,.L69
	lui	a0,%hi(.LC10)
	lui	s3,%hi(End_Time)
	addi	a0,a0,%lo(.LC10)
#APP
# 49 "test_programs/dhry_1.c" 1
	csrr a5, mcycle
# 0 "" 2
#NO_APP
	lui	s10,%hi(.LC2)
	sw	a5,%lo(End_Time)(s3)
	call	printf
	addi	a0,s10,%lo(.LC2)
	call	printf
	lui	a0,%hi(.LC11)
	addi	a0,a0,%lo(.LC11)
	call	printf
	addi	a0,s10,%lo(.LC2)
	call	printf
	lw	a1,%lo(Int_Glob)(s6)
	lui	a0,%hi(.LC12)
	addi	a0,a0,%lo(.LC12)
	call	printf
	lw	a0,%lo(Int_Glob)(s6)
	sub	s0,s0,s5
	slli	s2,s0,3
	call	printhex
	lw	a1,%lo(Bool_Glob)(s8)
	lui	a0,%hi(.LC13)
	addi	a0,a0,%lo(.LC13)
	call	printf
	lw	a0,%lo(Bool_Glob)(s8)
	sub	s2,s2,s0
	sub	s2,s2,s4
	call	printhex
	lui	s4,%hi(Ch_1_Glob)
	lbu	a1,%lo(Ch_1_Glob)(s4)
	lui	a0,%hi(.LC14)
	addi	a0,a0,%lo(.LC14)
	call	printf
	lbu	a0,%lo(Ch_1_Glob)(s4)
	lui	s9,%hi(.LC19)
	lui	s8,%hi(.LC20)
	call	printhex
	lbu	a1,%lo(Ch_2_Glob)(s1)
	lui	a0,%hi(.LC15)
	addi	a0,a0,%lo(.LC15)
	call	printf
	lbu	a0,%lo(Ch_2_Glob)(s1)
	lui	s1,%hi(.LANCHOR1)
	addi	s1,s1,%lo(.LANCHOR1)
	call	printhex
	lw	a1,32(s1)
	lui	a0,%hi(.LC16)
	addi	a0,a0,%lo(.LC16)
	call	printf
	lw	a0,32(s1)
	lui	s6,%hi(.LC21)
	lui	s4,%hi(.LC22)
	call	printhex
	lw	s1,12(sp)
	lui	a0,%hi(.LC17)
	addi	a0,a0,%lo(.LC17)
	lw	a1,1628(s1)
#APP
# 43 "test_programs/dhry_1.c" 1
	csrr s0, minstret
# 0 "" 2
#NO_APP
	call	printf
	lw	a0,1628(s1)
	lui	s1,%hi(.LC23)
	call	printhex
	lui	a0,%hi(.LC18)
	addi	a0,a0,%lo(.LC18)
	call	printf
	addi	a0,s9,%lo(.LC19)
	call	printf
	lw	a5,%lo(Ptr_Glob)(s7)
	lw	a0,0(a5)
	call	printhex
	lw	a5,%lo(Ptr_Glob)(s7)
	addi	a0,s8,%lo(.LC20)
	lw	a1,4(a5)
	call	printf
	lw	a5,%lo(Ptr_Glob)(s7)
	lw	a0,4(a5)
	call	printhex
	lw	a5,%lo(Ptr_Glob)(s7)
	addi	a0,s6,%lo(.LC21)
	lw	a1,8(a5)
	call	printf
	lw	a5,%lo(Ptr_Glob)(s7)
	lw	a0,8(a5)
	call	printhex
	lw	a5,%lo(Ptr_Glob)(s7)
	addi	a0,s4,%lo(.LC22)
	lw	a1,12(a5)
	call	printf
	lw	a5,%lo(Ptr_Glob)(s7)
	lw	a0,12(a5)
	call	printhex
	lw	a1,%lo(Ptr_Glob)(s7)
	addi	a0,s1,%lo(.LC23)
	addi	a1,a1,16
	call	printf
	lw	a0,%lo(Ptr_Glob)(s7)
	lui	s7,%hi(Next_Ptr_Glob)
	addi	a0,a0,16
	call	printf
	addi	a0,s10,%lo(.LC2)
	call	printf
	lui	a0,%hi(.LC24)
	addi	a0,a0,%lo(.LC24)
	call	printf
	addi	a0,s9,%lo(.LC19)
	call	printf
	lw	a5,%lo(Next_Ptr_Glob)(s7)
	lw	a0,0(a5)
	call	printhex
	addi	a0,s8,%lo(.LC20)
	call	printf
	lw	a5,%lo(Next_Ptr_Glob)(s7)
	lw	a0,4(a5)
	call	printhex
	addi	a0,s6,%lo(.LC21)
	call	printf
	lw	a5,%lo(Next_Ptr_Glob)(s7)
	lw	a0,8(a5)
	call	printhex
	addi	a0,s4,%lo(.LC22)
	call	printf
	lw	a5,%lo(Next_Ptr_Glob)(s7)
	lw	a0,12(a5)
	call	printhex
	addi	a0,s1,%lo(.LC23)
	call	printf
	lw	a0,%lo(Next_Ptr_Glob)(s7)
	addi	a0,a0,16
	call	printf
	addi	a0,s10,%lo(.LC2)
	call	printf
	lui	a0,%hi(.LC25)
	addi	a0,a0,%lo(.LC25)
	call	printf
	lw	s1,20(sp)
	lui	a0,%hi(.LC26)
	addi	a0,a0,%lo(.LC26)
	mv	a1,s1
	call	printf
	mv	a0,s1
	call	printhex
	lui	a0,%hi(.LC27)
	mv	a1,s2
	addi	a0,a0,%lo(.LC27)
	call	printf
	mv	a0,s2
	call	printhex
	lui	a0,%hi(.LC28)
	mv	a1,s5
	addi	a0,a0,%lo(.LC28)
	call	printf
	mv	a0,s5
	call	printhex
	lw	s1,28(sp)
	lui	a0,%hi(.LC29)
	addi	a0,a0,%lo(.LC29)
	mv	a1,s1
	call	printf
	mv	a0,s1
	call	printhex
	lui	a0,%hi(.LC30)
	addi	a1,sp,32
	addi	a0,a0,%lo(.LC30)
	call	printf
	addi	a0,sp,32
	call	printf
	addi	a0,s10,%lo(.LC2)
	call	printf
	lui	a0,%hi(.LC31)
	addi	a0,a0,%lo(.LC31)
	call	printf
	lui	a0,%hi(.LC32)
	addi	a1,sp,64
	addi	a0,a0,%lo(.LC32)
	call	printf
	addi	a0,sp,64
	call	printf
	addi	a0,s10,%lo(.LC2)
	call	printf
	lui	a0,%hi(.LC33)
	addi	a0,a0,%lo(.LC33)
	call	printf
	lui	a5,%hi(Begin_Time)
	lw	a4,8(sp)
	lw	a5,%lo(Begin_Time)(a5)
	lw	s1,%lo(End_Time)(s3)
	lui	a0,%hi(.LC34)
	addi	a0,a0,%lo(.LC34)
	sub	s0,s0,a4
	sub	s1,s1,a5
	call	printf
	lui	a0,%hi(.LC35)
	addi	a0,a0,%lo(.LC35)
	call	printf
	mv	a0,s1
	call	printdecu
	lui	a0,%hi(.LC36)
	addi	a0,a0,%lo(.LC36)
	call	printf
	mv	a0,s0
	call	printdecu
	li	a5,1000
	mul	s0,s0,a5
	lui	a0,%hi(.LC37)
	addi	a0,a0,%lo(.LC37)
	call	printf
	divu	s0,s0,s1
	mv	a0,s0
	call	printdecu
	li	a5,1757
	mul	a5,s1,a5
	li	a3,999424
	addi	a3,a3,576
	li	a4,1998848
	addi	a4,a4,1152
	lui	a0,%hi(.LC38)
	addi	a0,a0,%lo(.LC38)
	divu	a5,a5,a3
	divu	s0,a4,a5
	call	printf
	mv	a0,s0
	call	printdecu
	lw	ra,156(sp)
	lw	s0,152(sp)
	lw	s1,148(sp)
	lw	s2,144(sp)
	lw	s3,140(sp)
	lw	s4,136(sp)
	lw	s5,132(sp)
	lw	s6,128(sp)
	lw	s7,124(sp)
	lw	s8,120(sp)
	lw	s9,116(sp)
	lw	s10,112(sp)
	lw	s11,108(sp)
	li	a0,0
	addi	sp,sp,160
	jr	ra
.L70:
	li	s0,9
	j	.L64
.L62:
	lui	a0,%hi(.LC5)
	addi	a0,a0,%lo(.LC5)
	call	printf
	lui	a5,%hi(.LC2)
	addi	a0,a5,%lo(.LC2)
	call	printf
	j	.L63
	.size	main, .-main
	.globl	Dhrystones_Per_Second
	.globl	Microseconds
	.globl	User_Time
	.globl	End_Time
	.globl	Begin_Time
	.globl	Reg
	.globl	mallocPtr
	.globl	Arr_2_Glob
	.globl	Arr_1_Glob
	.globl	Ch_2_Glob
	.globl	Ch_1_Glob
	.globl	Bool_Glob
	.globl	Int_Glob
	.globl	Next_Ptr_Glob
	.globl	Ptr_Glob
	.section	.rodata
	.align	2
	.set	.LANCHOR0,. + 0
	.type	hexLut, @object
	.size	hexLut, 16
hexLut:
	.ascii	"0123456789abcdef"
	.bss
	.align	2
	.set	.LANCHOR1,. + 0
	.type	Arr_1_Glob, @object
	.size	Arr_1_Glob, 200
Arr_1_Glob:
	.zero	200
	.type	Arr_2_Glob, @object
	.size	Arr_2_Glob, 10000
Arr_2_Glob:
	.zero	10000
	.section	.sbss,"aw",@nobits
	.align	2
	.type	Dhrystones_Per_Second, @object
	.size	Dhrystones_Per_Second, 4
Dhrystones_Per_Second:
	.zero	4
	.type	Microseconds, @object
	.size	Microseconds, 4
Microseconds:
	.zero	4
	.type	User_Time, @object
	.size	User_Time, 4
User_Time:
	.zero	4
	.type	End_Time, @object
	.size	End_Time, 4
End_Time:
	.zero	4
	.type	Begin_Time, @object
	.size	Begin_Time, 4
Begin_Time:
	.zero	4
	.type	Reg, @object
	.size	Reg, 4
Reg:
	.zero	4
	.type	Ch_2_Glob, @object
	.size	Ch_2_Glob, 1
Ch_2_Glob:
	.zero	1
	.type	Ch_1_Glob, @object
	.size	Ch_1_Glob, 1
Ch_1_Glob:
	.zero	1
	.zero	2
	.type	Bool_Glob, @object
	.size	Bool_Glob, 4
Bool_Glob:
	.zero	4
	.type	Int_Glob, @object
	.size	Int_Glob, 4
Int_Glob:
	.zero	4
	.type	Next_Ptr_Glob, @object
	.size	Next_Ptr_Glob, 4
Next_Ptr_Glob:
	.zero	4
	.type	Ptr_Glob, @object
	.size	Ptr_Glob, 4
Ptr_Glob:
	.zero	4
	.section	.sdata,"aw"
	.align	2
	.type	mallocPtr, @object
	.size	mallocPtr, 4
mallocPtr:
	.word	131072
	.ident	"GCC: () 13.2.0"
	.section	.note.GNU-stack,"",@progbits
