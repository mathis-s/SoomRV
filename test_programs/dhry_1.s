	.file	"dhry_1.c"
	.option nopic
	.attribute arch, "rv32i2p0_m2p0_a2p0_c2p0_zba1p0_zbb1p0"
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
	beq	t1,zero,.L4
	li	a5,268435456
.L6:
	addi	a0,a0,1
	sb	t1,0(a5)
	lbu	t1,0(a0)
	bne	t1,zero,.L6
.L4:
	addi	sp,sp,32
	jr	ra
	.size	printf, .-printf
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"Dhrystone Benchmark, Version 2.1 (Language: C)\n"
	.align	2
.LC1:
	.string	"Program compiled with 'register' attribute\n"
	.align	2
.LC2:
	.string	"Program compiled without 'register' attribute\n"
	.align	2
.LC3:
	.string	"Please give the number of runs through the benchmark: "
	.align	2
.LC4:
	.string	"Execution starts, %d runs through Dhrystone\n"
	.align	2
.LC5:
	.string	"Execution ends\n"
	.align	2
.LC6:
	.string	"Final values of the variables used in the benchmark:\n"
	.align	2
.LC7:
	.string	"Int_Glob:            "
	.align	2
.LC8:
	.string	"Bool_Glob:           "
	.align	2
.LC9:
	.string	"Ch_1_Glob:           "
	.align	2
.LC10:
	.string	"Ch_2_Glob:           "
	.align	2
.LC11:
	.string	"Arr_1_Glob[8]:       "
	.align	2
.LC12:
	.string	"Arr_2_Glob[8][7]:    "
	.align	2
.LC13:
	.string	"Ptr_Glob->"
	.align	2
.LC14:
	.string	"Ptr_Comp:          "
	.align	2
.LC15:
	.string	"  Discr:             "
	.align	2
.LC16:
	.string	"  Enum_Comp:         "
	.align	2
.LC17:
	.string	"  Int_Comp:          "
	.align	2
.LC18:
	.string	"  Str_Comp:          "
	.align	2
.LC19:
	.string	"Next_Ptr_Glob->"
	.align	2
.LC20:
	.string	"        should be:   DHRYSTONE PROGRAM, SOME STRING\n"
	.align	2
.LC21:
	.string	"Int_1_Loc:           "
	.align	2
.LC22:
	.string	"Int_2_Loc:           "
	.align	2
.LC23:
	.string	"Int_3_Loc:           "
	.align	2
.LC24:
	.string	"Enum_Loc:            "
	.align	2
.LC25:
	.string	"Str_1_Loc:           "
	.align	2
.LC26:
	.string	"        should be:   DHRYSTONE PROGRAM, 1'ST STRING\n"
	.align	2
.LC27:
	.string	"Str_2_Loc:           "
	.align	2
.LC28:
	.string	"        should be:   DHRYSTONE PROGRAM, 2'ND STRING\n"
	.align	2
.LC29:
	.string	"\n\nRESULTS\n"
	.align	2
.LC30:
	.string	"Runtime (cycles) "
	.align	2
.LC31:
	.string	"Executed (instrs) "
	.align	2
.LC32:
	.string	"mIPC "
	.align	2
.LC33:
	.string	"mDMIPS/MHz "
	.align	2
.LC34:
	.string	"DHRYSTONE PROGRAM, SOME STRING"
	.align	2
.LC35:
	.string	"DHRYSTONE PROGRAM, 1'ST STRING"
	.align	2
.LC36:
	.string	"DHRYSTONE PROGRAM, 2'ND STRING"
	.section	.text.startup,"ax",@progbits
	.align	1
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-176
	lui	a5,%hi(.LC34)
	addi	a5,a5,%lo(.LC34)
	sw	s0,168(sp)
	li	a3,-2147356672
	lui	s0,%hi(Next_Ptr_Glob)
	sw	a3,%lo(Next_Ptr_Glob)(s0)
	lw	a7,20(a5)
	lw	a6,24(a5)
	lhu	a0,28(a5)
	lbu	a1,30(a5)
	lw	t0,0(a5)
	lw	t6,4(a5)
	lw	t4,12(a5)
	lw	t3,16(a5)
	lw	t5,8(a5)
	lui	s0,%hi(Ptr_Glob)
	li	a5,-2147352576
	sw	s3,156(sp)
	sw	a5,%lo(Ptr_Glob)(s0)
	sw	ra,172(sp)
	sw	s1,164(sp)
	sw	s2,160(sp)
	sw	s4,152(sp)
	sw	s5,148(sp)
	sw	s6,144(sp)
	sw	s7,140(sp)
	sw	s8,136(sp)
	sw	s9,132(sp)
	sw	s10,128(sp)
	sw	s11,124(sp)
	lui	a4,%hi(.LC35)
	addi	a4,a4,%lo(.LC35)
	sw	a3,0(a5)
	li	a3,2
	lw	a2,0(a4)
	sw	a3,8(a5)
	li	a3,40
	sw	a3,12(a5)
	sw	zero,4(a5)
	sw	t0,16(a5)
	sw	t6,20(a5)
	lw	t1,4(a4)
	sw	t5,24(a5)
	sw	a7,36(a5)
	sw	a6,40(a5)
	sh	a0,44(a5)
	sb	a1,46(a5)
	sw	t4,28(a5)
	sw	t3,32(a5)
	lhu	a3,28(a4)
	lw	a7,8(a4)
	lw	a6,12(a4)
	lw	a0,16(a4)
	lw	a1,20(a4)
	sw	a2,48(sp)
	lw	a2,24(a4)
	lbu	a4,30(a4)
	lui	s3,%hi(Arr_2_Glob)
	li	a5,10
	addi	s3,s3,%lo(Arr_2_Glob)
	sh	a3,76(sp)
	sb	a4,78(sp)
	sw	a5,1628(s3)
	li	a4,268435456
	sw	t1,52(sp)
	sw	a7,56(sp)
	sw	a6,60(sp)
	sw	a0,64(sp)
	sw	a1,68(sp)
	sw	a2,72(sp)
	sb	a5,0(a4)
	lui	a5,%hi(.LC0)
	li	a4,68
	addi	a5,a5,%lo(.LC0)
	li	a3,268435456
.L13:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L13
	li	a5,10
	sb	a5,0(a3)
	lui	a5,%hi(Reg)
	lw	a5,%lo(Reg)(a5)
	li	a4,80
	bne	a5,zero,.L79
	lui	a5,%hi(.LC2)
	addi	a5,a5,%lo(.LC2)
	li	a3,268435456
.L17:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L17
.L134:
	li	a5,10
	sb	a5,0(a3)
	lui	a5,%hi(.LC3)
	li	a4,80
	addi	a5,a5,%lo(.LC3)
	li	a3,268435456
.L19:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L19
	li	a5,10
	sb	a5,0(a3)
	lui	a5,%hi(.LC4)
	li	a4,69
	addi	a5,a5,%lo(.LC4)
	li	a3,268435456
.L21:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L21
	lui	a5,%hi(.LC36)
	addi	a5,a5,%lo(.LC36)
	lui	a4,%hi(Ptr_Glob)
	lw	s0,%lo(Ptr_Glob)(a4)
	lw	a4,0(a5)
	lbu	s4,50(sp)
	li	s9,2000
	sw	a4,4(sp)
	lw	a4,4(a5)
	lui	s5,%hi(.LANCHOR1)
#APP
# 43 "test_programs/dhry_1.c" 1
	csrr s2, minstret
# 0 "" 2
#NO_APP
	sw	a4,8(sp)
	lw	a4,8(a5)
	sw	s2,44(sp)
	lui	s6,%hi(Ch_1_Glob)
	sw	a4,12(sp)
	lw	a4,12(a5)
	mv	s2,s4
	addi	s5,s5,%lo(.LANCHOR1)
	sw	a4,16(sp)
	lw	a4,16(a5)
	li	s8,65
	li	s1,89
	sw	a4,20(sp)
	lw	a4,20(a5)
	li	s7,7
	li	s11,8
	sw	a4,24(sp)
	lw	a4,24(a5)
	li	s10,5
	mv	s4,s9
	sw	a4,28(sp)
	lhu	a4,28(a5)
	lbu	a5,30(a5)
	sw	a4,32(sp)
	lui	a4,%hi(Begin_Time)
	sw	a5,36(sp)
#APP
# 49 "test_programs/dhry_1.c" 1
	csrr a5, mcycle
# 0 "" 2
#NO_APP
	sw	a5,%lo(Begin_Time)(a4)
	lui	a5,%hi(Arr_2_Glob+4096)
	addi	a5,a5,%lo(Arr_2_Glob+4096)
	sw	a5,40(sp)
.L28:
	lui	a5,%hi(Ch_2_Glob)
	li	a4,66
	sb	a4,%lo(Ch_2_Glob)(a5)
	lw	a5,4(sp)
	sb	s8,%lo(Ch_1_Glob)(s6)
	sw	a5,80(sp)
	lw	a5,8(sp)
	sw	a5,84(sp)
	lw	a5,12(sp)
	sw	a5,88(sp)
	lw	a5,16(sp)
	sw	a5,92(sp)
	lw	a5,20(sp)
	sw	a5,96(sp)
	lw	a5,24(sp)
	sw	a5,100(sp)
	lw	a5,28(sp)
	sw	a5,104(sp)
	lw	a5,32(sp)
	sh	a5,108(sp)
	lw	a5,36(sp)
	sb	a5,110(sp)
	li	a5,0
.L22:
	beq	s2,s1,.L72
	li	s9,65
	beq	a5,zero,.L23
	sb	s1,%lo(Ch_1_Glob)(s6)
	li	s9,89
.L23:
	addi	a1,sp,80
	addi	a0,sp,48
	call	strcmp
	lw	a5,1628(s3)
	sw	s11,152(s5)
	sw	s11,1632(s3)
	addi	a5,a5,1
	sw	a5,1628(s3)
	lw	a5,40(sp)
	sw	s11,1636(s3)
	sw	s7,36(s5)
	sw	s7,32(s5)
	sw	s7,1536(a5)
	lw	ra,4(s0)
	lw	a5,0(s0)
	lw	t2,8(s0)
	lw	t0,16(s0)
	lw	t6,20(s0)
	lw	t5,24(s0)
	lw	t4,28(s0)
	lw	t3,32(s0)
	lw	t1,36(s0)
	lui	a4,%hi(Bool_Glob)
	slti	a0,a0,1
	lw	a3,44(s0)
	lw	a1,40(s0)
	sw	a0,%lo(Bool_Glob)(a4)
	lui	a4,%hi(Int_Glob)
	sw	s10,%lo(Int_Glob)(a4)
	sw	a5,0(a5)
	sw	ra,4(a5)
	sw	t2,8(a5)
	sw	t0,16(a5)
	sw	t6,20(a5)
	sw	t5,24(a5)
	sw	t4,28(a5)
	sw	t3,32(a5)
	sw	t1,36(a5)
	sw	a1,40(a5)
	sw	a3,44(a5)
	lw	a3,0(s0)
	li	a4,17
	sw	s10,12(a5)
	sw	a3,0(a5)
	sw	a4,12(s0)
	lw	a1,4(a5)
	beq	a1,zero,.L143
	lw	ra,0(a3)
	lw	t2,4(a3)
	lw	t0,8(a3)
	lw	t6,12(a3)
	lw	t5,16(a3)
	lw	t4,20(a3)
	lw	t3,24(a3)
	lw	t1,28(a3)
	lw	a0,32(a3)
	lw	a1,36(a3)
	lw	a5,40(a3)
	lw	a3,44(a3)
	sw	ra,0(s0)
	sw	t2,4(s0)
	sw	t0,8(s0)
	sw	t6,12(s0)
	sw	t5,16(s0)
	sw	t4,20(s0)
	sw	t3,24(s0)
	sw	t1,28(s0)
	sw	a0,32(s0)
	sw	a1,36(s0)
	sw	a5,40(s0)
	sw	a3,44(s0)
.L26:
	li	a5,5
	beq	s9,s8,.L27
	li	a5,1
.L27:
	addi	s4,s4,-1
	bne	s4,zero,.L28
	lui	s1,%hi(End_Time)
	lw	s2,44(sp)
#APP
# 49 "test_programs/dhry_1.c" 1
	csrr a4, mcycle
# 0 "" 2
#NO_APP
	sw	a4,%lo(End_Time)(s1)
	lui	a4,%hi(.LC5)
	li	a3,69
	addi	a4,a4,%lo(.LC5)
	li	a2,268435456
#APP
# 43 "test_programs/dhry_1.c" 1
	csrr s0, minstret
# 0 "" 2
#NO_APP
.L29:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L29
	li	a4,10
	sb	a4,0(a2)
	lui	a4,%hi(.LC6)
	li	a3,70
	addi	a4,a4,%lo(.LC6)
	li	a2,268435456
.L30:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L30
	li	a4,10
	sb	a4,0(a2)
	lui	a4,%hi(.LC7)
	li	a3,73
	addi	a4,a4,%lo(.LC7)
	li	a2,268435456
.L31:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L31
	sw	a5,4(sp)
	lui	a5,%hi(Int_Glob)
	lw	a0,%lo(Int_Glob)(a5)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC8)
	li	a3,66
	addi	a4,a4,%lo(.LC8)
	li	a2,268435456
.L32:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L32
	sw	a5,4(sp)
	lui	a5,%hi(Bool_Glob)
	lw	a0,%lo(Bool_Glob)(a5)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC9)
	li	a3,67
	addi	a4,a4,%lo(.LC9)
	li	a2,268435456
.L33:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L33
	lbu	a0,%lo(Ch_1_Glob)(s6)
	sw	a5,4(sp)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC10)
	li	a3,67
	addi	a4,a4,%lo(.LC10)
	li	a2,268435456
.L34:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L34
	sw	a5,4(sp)
	lui	a5,%hi(Ch_2_Glob)
	lbu	a0,%lo(Ch_2_Glob)(a5)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC11)
	li	a3,65
	addi	a4,a4,%lo(.LC11)
	li	a2,268435456
.L35:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L35
	lw	a0,32(s5)
	sw	a5,4(sp)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC12)
	li	a3,65
	addi	a4,a4,%lo(.LC12)
	li	a2,268435456
.L36:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L36
	lw	a0,1628(s3)
	sw	a5,4(sp)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC13)
	li	a3,80
	addi	a4,a4,%lo(.LC13)
	li	a2,268435456
.L37:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L37
	lui	a4,%hi(.LC14)
	addi	s7,a4,%lo(.LC14)
	li	a3,80
	addi	a4,a4,%lo(.LC14)
	li	a2,268435456
.L38:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L38
	sw	a5,4(sp)
	lui	a5,%hi(Ptr_Glob)
	lw	a4,%lo(Ptr_Glob)(a5)
	lw	a0,0(a4)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC15)
	addi	s6,a4,%lo(.LC15)
	li	a3,32
	addi	a4,a4,%lo(.LC15)
	li	a2,268435456
.L39:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L39
	sw	a5,4(sp)
	lui	a5,%hi(Ptr_Glob)
	lw	a4,%lo(Ptr_Glob)(a5)
	lw	a0,4(a4)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC16)
	addi	s5,a4,%lo(.LC16)
	li	a3,32
	addi	a4,a4,%lo(.LC16)
	li	a2,268435456
.L40:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L40
	sw	a5,4(sp)
	lui	a5,%hi(Ptr_Glob)
	lw	a4,%lo(Ptr_Glob)(a5)
	lw	a0,8(a4)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC17)
	addi	s4,a4,%lo(.LC17)
	li	a3,32
	addi	a4,a4,%lo(.LC17)
	li	a2,268435456
.L41:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L41
	sw	a5,4(sp)
	lui	a5,%hi(Ptr_Glob)
	lw	a4,%lo(Ptr_Glob)(a5)
	lw	a0,12(a4)
	call	printhex
	lw	a5,4(sp)
	lui	a4,%hi(.LC18)
	addi	s3,a4,%lo(.LC18)
	li	a3,32
	addi	a4,a4,%lo(.LC18)
	li	a2,268435456
.L42:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L42
	lui	a4,%hi(Ptr_Glob)
	lw	a4,%lo(Ptr_Glob)(a4)
	li	a2,268435456
	lbu	a3,16(a4)
	addi	a4,a4,16
	beq	a3,zero,.L45
.L43:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L43
.L45:
	li	a4,268435456
	li	a3,10
	sb	a3,0(a4)
	lui	a4,%hi(.LC19)
	li	a3,78
	addi	a4,a4,%lo(.LC19)
	li	a2,268435456
.L44:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L44
	li	a4,80
	li	a3,268435456
.L46:
	addi	s7,s7,1
	sb	a4,0(a3)
	lbu	a4,0(s7)
	bne	a4,zero,.L46
	sw	a5,4(sp)
	lui	a5,%hi(Next_Ptr_Glob)
	lw	a4,%lo(Next_Ptr_Glob)(a5)
	lw	a0,0(a4)
	call	printhex
	lw	a5,4(sp)
	li	a4,32
	li	a3,268435456
.L47:
	addi	s6,s6,1
	sb	a4,0(a3)
	lbu	a4,0(s6)
	bne	a4,zero,.L47
	sw	a5,4(sp)
	lui	a5,%hi(Next_Ptr_Glob)
	lw	a4,%lo(Next_Ptr_Glob)(a5)
	lw	a0,4(a4)
	call	printhex
	lw	a5,4(sp)
	li	a4,32
	li	a3,268435456
.L48:
	addi	s5,s5,1
	sb	a4,0(a3)
	lbu	a4,0(s5)
	bne	a4,zero,.L48
	sw	a5,4(sp)
	lui	a5,%hi(Next_Ptr_Glob)
	lw	a4,%lo(Next_Ptr_Glob)(a5)
	lw	a0,8(a4)
	call	printhex
	lw	a5,4(sp)
	li	a4,32
	li	a3,268435456
.L49:
	addi	s4,s4,1
	sb	a4,0(a3)
	lbu	a4,0(s4)
	bne	a4,zero,.L49
	sw	a5,4(sp)
	lui	a5,%hi(Next_Ptr_Glob)
	lw	a4,%lo(Next_Ptr_Glob)(a5)
	lw	a0,12(a4)
	call	printhex
	lw	a5,4(sp)
	li	a4,32
	li	a3,268435456
.L50:
	addi	s3,s3,1
	sb	a4,0(a3)
	lbu	a4,0(s3)
	bne	a4,zero,.L50
	lui	a4,%hi(Next_Ptr_Glob)
	lw	a4,%lo(Next_Ptr_Glob)(a4)
	li	a2,268435456
	lbu	a3,16(a4)
	addi	a4,a4,16
	beq	a3,zero,.L53
.L51:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L51
.L53:
	li	a4,268435456
	li	a3,10
	sb	a3,0(a4)
	lui	a4,%hi(.LC20)
	li	a3,32
	addi	a4,a4,%lo(.LC20)
	li	a2,268435456
.L52:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L52
	lui	a4,%hi(.LC21)
	li	a3,73
	addi	a4,a4,%lo(.LC21)
	li	a2,268435456
.L54:
	addi	a4,a4,1
	sb	a3,0(a2)
	lbu	a3,0(a4)
	bne	a3,zero,.L54
	mv	a0,a5
	call	printhex
	lui	a5,%hi(.LC22)
	li	a4,73
	addi	a5,a5,%lo(.LC22)
	li	a3,268435456
.L55:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L55
	li	a0,13
	call	printhex
	lui	a5,%hi(.LC23)
	li	a4,73
	addi	a5,a5,%lo(.LC23)
	li	a3,268435456
.L56:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L56
	li	a0,7
	call	printhex
	lui	a5,%hi(.LC24)
	li	a4,69
	addi	a5,a5,%lo(.LC24)
	li	a3,268435456
.L57:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L57
	li	a0,1
	call	printhex
	lui	a5,%hi(.LC25)
	li	a4,83
	addi	a5,a5,%lo(.LC25)
	li	a3,268435456
.L58:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L58
	lbu	a4,48(sp)
	addi	a5,sp,48
	li	a3,268435456
	beq	a4,zero,.L61
.L59:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L59
.L61:
	li	a5,268435456
	li	a4,10
	sb	a4,0(a5)
	lui	a5,%hi(.LC26)
	li	a4,32
	addi	a5,a5,%lo(.LC26)
	li	a3,268435456
.L60:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L60
	lui	a5,%hi(.LC27)
	li	a4,83
	addi	a5,a5,%lo(.LC27)
	li	a3,268435456
.L62:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L62
	lbu	a4,80(sp)
	addi	a5,sp,80
	li	a3,268435456
	beq	a4,zero,.L65
.L63:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L63
.L65:
	li	a5,268435456
	li	a4,10
	sb	a4,0(a5)
	lui	a5,%hi(.LC28)
	li	a4,32
	addi	a5,a5,%lo(.LC28)
	li	a3,268435456
.L64:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L64
	lui	a5,%hi(Begin_Time)
	lw	a5,%lo(Begin_Time)(a5)
	lw	s1,%lo(End_Time)(s1)
	sub	s0,s0,s2
	li	a4,10
	sub	s1,s1,a5
	lui	a5,%hi(.LC29)
	addi	a5,a5,%lo(.LC29)
	li	a3,268435456
.L66:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L66
	lui	a5,%hi(.LC30)
	li	a4,82
	addi	a5,a5,%lo(.LC30)
	li	a3,268435456
.L67:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L67
	mv	a0,s1
	call	printdecu
	lui	a5,%hi(.LC31)
	li	a4,69
	addi	a5,a5,%lo(.LC31)
	li	a3,268435456
.L68:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L68
	mv	a0,s0
	call	printdecu
	li	a5,1000
	mul	s0,s0,a5
	lui	a5,%hi(.LC32)
	li	a4,109
	addi	a5,a5,%lo(.LC32)
	li	a3,268435456
	divu	a0,s0,s1
.L69:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L69
	call	printdecu
	li	a2,1757
	li	a1,999424
	addi	a1,a1,576
	li	a0,1998848
	addi	a0,a0,1152
	lui	a5,%hi(.LC33)
	li	a4,109
	addi	a5,a5,%lo(.LC33)
	li	a3,268435456
	mul	a2,s1,a2
	divu	a2,a2,a1
	divu	a0,a0,a2
.L70:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L70
	call	printdecu
	lw	ra,172(sp)
	lw	s0,168(sp)
	lw	s1,164(sp)
	lw	s2,160(sp)
	lw	s3,156(sp)
	lw	s4,152(sp)
	lw	s5,148(sp)
	lw	s6,144(sp)
	lw	s7,140(sp)
	lw	s8,136(sp)
	lw	s9,132(sp)
	lw	s10,128(sp)
	lw	s11,124(sp)
	li	a0,0
	addi	sp,sp,176
	jr	ra
.L72:
	li	a5,1
	j	.L22
.L143:
	lw	a1,8(s0)
	li	a4,6
	sw	a4,12(a5)
	li	a4,2
	beq	a1,a4,.L74
	beq	a1,zero,.L25
	addi	a1,a1,-4
	snez	a1,a1
	addi	a1,a1,2
.L25:
	li	a4,18
	sw	a1,8(a5)
	sw	a3,0(a5)
	sw	a4,12(a5)
	j	.L26
.L74:
	li	a1,1
	j	.L25
.L79:
	lui	a5,%hi(.LC1)
	addi	a5,a5,%lo(.LC1)
	li	a3,268435456
.L15:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L15
	j	.L134
	.size	main, .-main
	.text
	.align	1
	.globl	Proc_1
	.type	Proc_1, @function
Proc_1:
	lui	a2,%hi(Ptr_Glob)
	lw	a4,%lo(Ptr_Glob)(a2)
	lw	a5,0(a0)
	lw	a1,0(a4)
	lw	a3,44(a4)
	lw	t2,4(a4)
	lw	t0,8(a4)
	lw	t6,16(a4)
	lw	t5,20(a4)
	lw	t4,24(a4)
	lw	t3,28(a4)
	lw	t1,32(a4)
	lw	a7,36(a4)
	lw	a6,40(a4)
	sw	a1,0(a5)
	lw	a1,0(a0)
	sw	a3,44(a5)
	sw	t2,4(a5)
	li	a3,5
	sw	t0,8(a5)
	sw	t6,16(a5)
	sw	t5,20(a5)
	sw	t4,24(a5)
	sw	t3,28(a5)
	sw	t1,32(a5)
	sw	a7,36(a5)
	sw	a6,40(a5)
	sw	a3,12(a0)
	sw	a1,0(a5)
	lw	a4,0(a4)
	lui	a1,%hi(Int_Glob)
	lw	a1,%lo(Int_Glob)(a1)
	sw	a4,0(a5)
	lw	a4,%lo(Ptr_Glob)(a2)
	sw	a3,12(a5)
	addi	a3,a1,12
	sw	a3,12(a4)
	lw	a3,4(a5)
	beq	a3,zero,.L152
	lw	a5,0(a0)
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
	sw	t6,0(a0)
	sw	t5,4(a0)
	sw	t4,8(a0)
	sw	t3,12(a0)
	sw	t1,16(a0)
	sw	a7,20(a0)
	sw	a6,24(a0)
	sw	a1,28(a0)
	sw	a2,32(a0)
	sw	a3,36(a0)
	sw	a4,40(a0)
	sw	a5,44(a0)
	ret
.L152:
	lw	a3,8(a0)
	li	a2,6
	sw	a2,12(a5)
	li	a2,2
	beq	a3,a2,.L153
	li	a0,3
	sw	a0,8(a5)
	li	a0,1
	beq	a3,a0,.L148
	li	a1,4
	beq	a3,a1,.L149
	beq	a3,zero,.L151
.L147:
	lw	a4,0(a4)
	li	a3,18
	sw	a3,12(a5)
	sw	a4,0(a5)
	ret
.L148:
	li	a3,100
	ble	a1,a3,.L147
.L151:
	sw	zero,8(a5)
	j	.L147
.L149:
	sw	a2,8(a5)
	j	.L147
.L153:
	lw	a4,0(a4)
	li	a3,1
	sw	a3,8(a5)
	li	a3,18
	sw	a3,12(a5)
	sw	a4,0(a5)
	ret
	.size	Proc_1, .-Proc_1
	.align	1
	.globl	Proc_2
	.type	Proc_2, @function
Proc_2:
	lui	a5,%hi(Ch_1_Glob)
	lbu	a4,%lo(Ch_1_Glob)(a5)
	li	a5,65
	beq	a4,a5,.L156
	ret
.L156:
	lw	a5,0(a0)
	lui	a4,%hi(Int_Glob)
	lw	a4,%lo(Int_Glob)(a4)
	addi	a5,a5,9
	sub	a5,a5,a4
	sw	a5,0(a0)
	ret
	.size	Proc_2, .-Proc_2
	.align	1
	.globl	Proc_3
	.type	Proc_3, @function
Proc_3:
	lui	a4,%hi(Ptr_Glob)
	lw	a5,%lo(Ptr_Glob)(a4)
	beq	a5,zero,.L158
	lw	a5,0(a5)
	sw	a5,0(a0)
	lw	a5,%lo(Ptr_Glob)(a4)
.L158:
	lui	a4,%hi(Int_Glob)
	lw	a4,%lo(Int_Glob)(a4)
	addi	a4,a4,12
	sw	a4,12(a5)
	ret
	.size	Proc_3, .-Proc_3
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
	.globl	Proc_6
	.type	Proc_6, @function
Proc_6:
	li	a5,2
	beq	a0,a5,.L170
	li	a4,3
	sw	a4,0(a1)
	li	a4,1
	beq	a0,a4,.L167
	li	a4,4
	beq	a0,a4,.L168
	beq	a0,zero,.L169
.L166:
	ret
.L167:
	lui	a5,%hi(Int_Glob)
	lw	a4,%lo(Int_Glob)(a5)
	li	a5,100
	ble	a4,a5,.L166
.L169:
	sw	zero,0(a1)
	ret
.L168:
	sw	a5,0(a1)
	ret
.L170:
	li	a5,1
	sw	a5,0(a1)
	ret
	.size	Proc_6, .-Proc_6
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
	.globl	Proc_8
	.type	Proc_8, @function
Proc_8:
	addi	a4,a2,5
	li	a6,200
	mul	a6,a4,a6
	sh2add	a0,a4,a0
	sw	a3,0(a0)
	sw	a4,120(a0)
	sw	a3,4(a0)
	sh2add	a5,a2,a6
	add	a5,a1,a5
	lw	a3,16(a5)
	sw	a4,20(a5)
	sw	a4,24(a5)
	addi	a4,a3,1
	sw	a4,16(a5)
	lw	a4,0(a0)
	add	a1,a1,a6
	li	a5,4096
	sh2add	a2,a2,a1
	add	a5,a5,a2
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
	beq	a0,a1,.L176
	li	a0,0
	ret
.L176:
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
	sw	ra,12(sp)
	lbu	a5,2(a0)
	lbu	a4,3(a1)
	li	a2,0
	li	a3,0
.L178:
	beq	a5,a4,.L181
	beq	a3,zero,.L179
	lui	a5,%hi(Ch_1_Glob)
	sb	a2,%lo(Ch_1_Glob)(a5)
.L179:
	call	strcmp
	li	a5,0
	ble	a0,zero,.L177
	lui	a5,%hi(Int_Glob)
	li	a4,10
	sw	a4,%lo(Int_Glob)(a5)
	li	a5,1
.L177:
	lw	ra,12(sp)
	mv	a0,a5
	addi	sp,sp,16
	jr	ra
.L181:
	li	a3,1
	mv	a2,a5
	j	.L178
	.size	Func_2, .-Func_2
	.align	1
	.globl	Func_3
	.type	Func_3, @function
Func_3:
	addi	a0,a0,-2
	seqz	a0,a0
	ret
	.size	Func_3, .-Func_3
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
	.ident	"GCC: (g2ee5e430018) 12.2.0"
	.section	.note.GNU-stack,"",@progbits
