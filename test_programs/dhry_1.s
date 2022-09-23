	.file	"dhry_1.c"
	.option nopic
	.text
	.align	2
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
	li	a4,-33554432
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
	.align	2
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
	.align	2
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
	li	a5,-33554432
.L6:
	addi	a0,a0,1
	sb	t1,0(a5)
	lbu	t1,0(a0)
	bne	t1,zero,.L6
.L4:
	addi	sp,sp,32
	jr	ra
	.size	printf, .-printf
	.align	2
	.globl	memcpy
	.type	memcpy, @function
memcpy:
	beq	a2,zero,.L12
	addi	a5,a1,1
	sub	a5,a0,a5
	addi	a4,a2,-1
	sltiu	a5,a5,3
	sltiu	a4,a4,7
	xori	a5,a5,1
	xori	a4,a4,1
	and	a5,a5,a4
	beq	a5,zero,.L14
	or	a5,a0,a1
	andi	a5,a5,3
	bne	a5,zero,.L14
	andi	a6,a2,-4
	mv	a5,a1
	mv	a4,a0
	add	a6,a6,a1
.L15:
	lw	a3,0(a5)
	addi	a5,a5,4
	addi	a4,a4,4
	sw	a3,-4(a4)
	bne	a5,a6,.L15
	andi	a5,a2,-4
	beq	a2,a5,.L12
	add	a4,a1,a5
	lbu	a6,0(a4)
	add	a3,a0,a5
	addi	a4,a5,1
	sb	a6,0(a3)
	bleu	a2,a4,.L12
	add	a3,a1,a4
	lbu	a3,0(a3)
	add	a4,a0,a4
	addi	a5,a5,2
	sb	a3,0(a4)
	bleu	a2,a5,.L12
	add	a1,a1,a5
	lbu	a4,0(a1)
	add	a5,a0,a5
	sb	a4,0(a5)
	ret
.L14:
	add	a2,a1,a2
.L17:
	lbu	a5,0(a1)
	addi	a1,a1,1
	addi	a0,a0,1
	sb	a5,-1(a0)
	bne	a1,a2,.L17
.L12:
	ret
	.size	memcpy, .-memcpy
	.align	2
	.globl	time
	.type	time, @function
time:
	li	a5,-16777216
	lw	a0,128(a5)
	ret
	.size	time, .-time
	.align	2
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
	beq	a3,zero,.L40
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
.L40:
	lw	a3,8(a0)
	li	a2,6
	sw	a2,12(a5)
	li	a0,2
	beq	a3,a0,.L33
	li	a2,3
	sw	a2,8(a5)
	li	a2,1
	beq	a3,a2,.L34
	bleu	a3,a2,.L39
	li	a2,4
	bne	a3,a2,.L37
	sw	a0,8(a5)
.L37:
	lw	a4,0(a4)
	li	a3,18
	sw	a3,12(a5)
	sw	a4,0(a5)
	ret
.L34:
	li	a3,100
	ble	a1,a3,.L37
.L39:
	sw	zero,8(a5)
	j	.L37
.L33:
	li	a3,1
	sw	a3,8(a5)
	j	.L37
	.size	Proc_1, .-Proc_1
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
	.align	2
.LC37:
	.string	"DHRYSTONE PROGRAM, 3'RD STRING"
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	lui	a5,%hi(.LC34)
	addi	sp,sp,-176
	addi	a5,a5,%lo(.LC34)
	sw	s4,152(sp)
	lw	a7,20(a5)
	lw	a6,24(a5)
	lhu	a0,28(a5)
	lbu	a1,30(a5)
	lw	t0,0(a5)
	lw	t6,4(a5)
	lw	t4,12(a5)
	lw	t3,16(a5)
	li	a3,126976
	lw	t5,8(a5)
	lui	t1,%hi(Next_Ptr_Glob)
	li	a5,131072
	lui	s4,%hi(Ptr_Glob)
	sw	a3,%lo(Next_Ptr_Glob)(t1)
	sw	s9,132(sp)
	sw	a5,%lo(Ptr_Glob)(s4)
	sw	ra,172(sp)
	sw	s0,168(sp)
	sw	s1,164(sp)
	sw	s2,160(sp)
	sw	s3,156(sp)
	sw	s5,148(sp)
	sw	s6,144(sp)
	sw	s7,140(sp)
	sw	s8,136(sp)
	sw	s10,128(sp)
	sw	s11,124(sp)
	sw	a3,0(a5)
	lui	a4,%hi(.LC35)
	li	a3,2
	addi	a4,a4,%lo(.LC35)
	sw	a3,8(a5)
	li	a3,40
	lw	a2,0(a4)
	sw	a3,12(a5)
	sw	zero,4(a5)
	sw	t0,16(a5)
	sw	t6,20(a5)
	lw	t1,4(a4)
	sw	t5,24(a5)
	sw	a7,36(a5)
	lw	a7,8(a4)
	sw	a6,40(a5)
	sh	a0,44(a5)
	sb	a1,46(a5)
	sw	t4,28(a5)
	sw	t3,32(a5)
	lhu	a3,28(a4)
	lw	a6,12(a4)
	lw	a0,16(a4)
	lw	a1,20(a4)
	sw	a2,48(sp)
	lw	a2,24(a4)
	lbu	a4,30(a4)
	sw	a7,56(sp)
	lui	a7,%hi(Arr_2_Glob)
	li	a5,10
	addi	s9,a7,%lo(Arr_2_Glob)
	sh	a3,76(sp)
	sb	a4,78(sp)
	sw	a5,1628(s9)
	li	a4,-33554432
	sw	t1,52(sp)
	sw	a6,60(sp)
	sw	a0,64(sp)
	sw	a1,68(sp)
	sw	a2,72(sp)
	sb	a5,0(a4)
	lui	a5,%hi(.LC0)
	li	a4,68
	addi	a5,a5,%lo(.LC0)
	li	a3,-33554432
.L42:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L42
	li	a5,10
	sb	a5,0(a3)
	lui	a5,%hi(Reg)
	lw	a5,%lo(Reg)(a5)
	li	a4,80
	bne	a5,zero,.L109
	lui	a5,%hi(.LC2)
	addi	a5,a5,%lo(.LC2)
	li	a3,-33554432
.L46:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L46
.L163:
	li	a5,10
	sb	a5,0(a3)
	lui	a5,%hi(.LC3)
	li	a4,80
	addi	a5,a5,%lo(.LC3)
	li	a3,-33554432
.L48:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L48
	li	a5,10
	sb	a5,0(a3)
	lui	a5,%hi(.LC4)
	li	a4,69
	addi	a5,a5,%lo(.LC4)
	li	a3,-33554432
.L49:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L49
	li	a4,-16777216
	lw	a3,128(a4)
	lw	a4,152(a4)
	lui	a5,%hi(.LC36)
	addi	a5,a5,%lo(.LC36)
	sw	a4,44(sp)
	lw	a4,0(a5)
	lbu	s11,50(sp)
	lui	a2,%hi(Begin_Time)
	sw	a4,8(sp)
	lw	a4,4(a5)
	lui	s0,%hi(.LANCHOR1)
	lui	s5,%hi(Arr_2_Glob+4096)
	sw	a4,12(sp)
	lw	a4,8(a5)
	lui	a6,%hi(.LC37)
	sw	a3,%lo(Begin_Time)(a2)
	sw	a4,16(sp)
	lw	a4,12(a5)
	li	s1,1
	lui	s8,%hi(Ch_1_Glob)
	sw	a4,20(sp)
	lw	a4,16(a5)
	lui	s2,%hi(Ch_2_Glob)
	lui	s6,%hi(Bool_Glob)
	sw	a4,24(sp)
	lw	a4,20(a5)
	addi	s0,s0,%lo(.LANCHOR1)
	addi	s5,s5,%lo(Arr_2_Glob+4096)
	sw	a4,28(sp)
	lw	a4,24(a5)
	lui	s3,%hi(Int_Glob)
	addi	s10,a6,%lo(.LC37)
	sw	a4,32(sp)
	lhu	a4,28(a5)
	lbu	a5,30(a5)
	sw	a4,36(sp)
	sw	a5,40(sp)
.L61:
	li	a5,65
	sb	a5,%lo(Ch_1_Glob)(s8)
	li	a5,66
	sb	a5,%lo(Ch_2_Glob)(s2)
	lw	a5,8(sp)
	sw	a5,80(sp)
	lw	a5,12(sp)
	sw	a5,84(sp)
	lw	a5,16(sp)
	sw	a5,88(sp)
	lw	a5,20(sp)
	sw	a5,92(sp)
	lw	a5,24(sp)
	sw	a5,96(sp)
	lw	a5,28(sp)
	sw	a5,100(sp)
	lw	a5,32(sp)
	sw	a5,104(sp)
	lw	a5,36(sp)
	sh	a5,108(sp)
	lw	a5,40(sp)
	sb	a5,110(sp)
	li	a5,89
	beq	s11,a5,.L51
	addi	a1,sp,80
	addi	a0,sp,48
	call	strcmp
	lw	a4,1628(s9)
	mv	a2,a0
	lw	a0,%lo(Ptr_Glob)(s4)
	li	a5,7
	li	a3,8
	addi	a4,a4,1
	slti	a2,a2,1
	sw	a5,32(s0)
	sw	a5,36(s0)
	sw	a5,1536(s5)
	sw	a3,152(s0)
	li	a5,5
	sw	a4,1628(s9)
	sw	a5,%lo(Int_Glob)(s3)
	sw	a2,%lo(Bool_Glob)(s6)
	sw	a3,1632(s9)
	sw	a3,1636(s9)
	call	Proc_1
	lbu	a4,%lo(Ch_2_Glob)(s2)
	li	a5,64
	bleu	a4,a5,.L167
	li	t3,0
	li	a5,65
	li	t1,0
	li	a3,1
	li	a0,3
	li	a1,67
.L52:
	addi	a5,a5,1
	andi	a5,a5,0xff
	bgtu	a5,a4,.L168
.L56:
	beq	a5,a1,.L106
	li	a2,0
.L54:
	bne	a3,a2,.L52
	lw	t1,20(s10)
	lw	a0,24(s10)
	lbu	a3,30(s10)
	lw	t2,0(s10)
	lw	t0,4(s10)
	lw	t6,8(s10)
	lw	t5,12(s10)
	lw	t4,16(s10)
	lhu	a2,28(s10)
	addi	a5,a5,1
	sw	t1,100(sp)
	sw	a0,104(sp)
	sb	a3,110(sp)
	sw	t2,80(sp)
	sw	t0,84(sp)
	sw	t6,88(sp)
	sw	t5,92(sp)
	sw	t4,96(sp)
	sh	a2,108(sp)
	andi	a5,a5,0xff
	mv	s7,s1
	mv	a0,s1
	li	t1,1
	li	a3,0
	bleu	a5,a4,.L56
.L168:
	beq	t1,zero,.L57
	sw	s7,%lo(Int_Glob)(s3)
.L57:
	beq	t3,zero,.L169
	li	a5,67
	sb	a5,%lo(Ch_1_Glob)(s8)
	li	a1,67
.L59:
	slli	a5,a0,1
	add	a5,a5,a0
	li	a4,7
	div	a4,a5,a4
	addi	a5,a5,-7
	slli	a2,a5,3
	sub	a5,a2,a5
	sub	a5,a5,a4
.L53:
	li	a2,65
	bne	a1,a2,.L60
	lw	a2,%lo(Int_Glob)(s3)
	addi	a4,a4,9
	sub	a4,a4,a2
.L60:
	addi	s1,s1,1
	li	a2,201
	bne	s1,a2,.L61
	li	a2,-16777216
	lw	a1,128(a2)
	lui	s5,%hi(End_Time)
	lw	s1,152(a2)
	lui	a2,%hi(.LC5)
	sw	a1,%lo(End_Time)(s5)
	addi	a2,a2,%lo(.LC5)
	li	a1,69
	li	a0,-33554432
.L62:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L62
	li	a2,10
	sb	a2,0(a0)
	lui	a2,%hi(.LC6)
	li	a1,70
	addi	a2,a2,%lo(.LC6)
	li	a0,-33554432
.L63:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L63
	li	a2,10
	sb	a2,0(a0)
	lui	a2,%hi(.LC7)
	li	a1,73
	addi	a2,a2,%lo(.LC7)
	li	a0,-33554432
.L64:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L64
	lw	a0,%lo(Int_Glob)(s3)
	sw	a3,16(sp)
	sw	a4,12(sp)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC8)
	li	a1,66
	addi	a2,a2,%lo(.LC8)
	li	a0,-33554432
.L65:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L65
	lw	a0,%lo(Bool_Glob)(s6)
	sw	a3,16(sp)
	sw	a4,12(sp)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC9)
	li	a1,67
	addi	a2,a2,%lo(.LC9)
	li	a0,-33554432
.L66:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L66
	lbu	a0,%lo(Ch_1_Glob)(s8)
	sw	a3,16(sp)
	sw	a4,12(sp)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC10)
	li	a1,67
	addi	a2,a2,%lo(.LC10)
	li	a0,-33554432
.L67:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L67
	lbu	a0,%lo(Ch_2_Glob)(s2)
	sw	a3,16(sp)
	sw	a4,12(sp)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC11)
	li	a1,65
	addi	a2,a2,%lo(.LC11)
	li	a0,-33554432
.L68:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L68
	lw	a0,32(s0)
	sw	a3,16(sp)
	sw	a4,12(sp)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC12)
	li	a1,65
	addi	a2,a2,%lo(.LC12)
	li	a0,-33554432
.L69:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L69
	lw	a0,1628(s9)
	sw	a3,16(sp)
	sw	a4,12(sp)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC13)
	li	a1,80
	addi	a2,a2,%lo(.LC13)
	li	a0,-33554432
.L70:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L70
	lui	a2,%hi(.LC14)
	addi	s7,a2,%lo(.LC14)
	li	a1,80
	addi	a2,a2,%lo(.LC14)
	li	a0,-33554432
.L71:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L71
	lw	a2,%lo(Ptr_Glob)(s4)
	sw	a3,16(sp)
	sw	a4,12(sp)
	lw	a0,0(a2)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC15)
	addi	s6,a2,%lo(.LC15)
	li	a1,32
	addi	a2,a2,%lo(.LC15)
	li	a0,-33554432
.L72:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L72
	lw	a2,%lo(Ptr_Glob)(s4)
	sw	a3,16(sp)
	sw	a4,12(sp)
	lw	a0,4(a2)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC16)
	addi	s3,a2,%lo(.LC16)
	li	a1,32
	addi	a2,a2,%lo(.LC16)
	li	a0,-33554432
.L73:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L73
	lw	a2,%lo(Ptr_Glob)(s4)
	sw	a3,16(sp)
	sw	a4,12(sp)
	lw	a0,8(a2)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC17)
	addi	s2,a2,%lo(.LC17)
	li	a1,32
	addi	a2,a2,%lo(.LC17)
	li	a0,-33554432
.L74:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L74
	lw	a2,%lo(Ptr_Glob)(s4)
	sw	a3,16(sp)
	sw	a4,12(sp)
	lw	a0,12(a2)
	sw	a5,8(sp)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	lui	a2,%hi(.LC18)
	addi	s0,a2,%lo(.LC18)
	li	a1,32
	addi	a2,a2,%lo(.LC18)
	li	a0,-33554432
.L75:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L75
	lw	a2,%lo(Ptr_Glob)(s4)
	li	a0,-33554432
	lbu	a1,16(a2)
	addi	a2,a2,16
	beq	a1,zero,.L78
.L76:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L76
.L78:
	li	a2,-33554432
	li	a1,10
	sb	a1,0(a2)
	lui	a2,%hi(.LC19)
	li	a1,78
	addi	a2,a2,%lo(.LC19)
	li	a0,-33554432
.L77:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L77
	li	a2,80
	li	a1,-33554432
.L79:
	addi	s7,s7,1
	sb	a2,0(a1)
	lbu	a2,0(s7)
	bne	a2,zero,.L79
	sw	a5,8(sp)
	lui	a5,%hi(Next_Ptr_Glob)
	lw	a2,%lo(Next_Ptr_Glob)(a5)
	sw	a3,16(sp)
	sw	a4,12(sp)
	lw	a0,0(a2)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	li	a2,32
	li	a1,-33554432
.L80:
	addi	s6,s6,1
	sb	a2,0(a1)
	lbu	a2,0(s6)
	bne	a2,zero,.L80
	sw	a5,8(sp)
	lui	a5,%hi(Next_Ptr_Glob)
	lw	a2,%lo(Next_Ptr_Glob)(a5)
	sw	a3,16(sp)
	sw	a4,12(sp)
	lw	a0,4(a2)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	li	a2,32
	li	a1,-33554432
.L81:
	addi	s3,s3,1
	sb	a2,0(a1)
	lbu	a2,0(s3)
	bne	a2,zero,.L81
	sw	a5,8(sp)
	lui	a5,%hi(Next_Ptr_Glob)
	lw	a2,%lo(Next_Ptr_Glob)(a5)
	sw	a3,16(sp)
	sw	a4,12(sp)
	lw	a0,8(a2)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	li	a2,32
	li	a1,-33554432
.L82:
	addi	s2,s2,1
	sb	a2,0(a1)
	lbu	a2,0(s2)
	bne	a2,zero,.L82
	sw	a5,8(sp)
	lui	a5,%hi(Next_Ptr_Glob)
	lw	a2,%lo(Next_Ptr_Glob)(a5)
	sw	a3,16(sp)
	sw	a4,12(sp)
	lw	a0,12(a2)
	call	printhex
	lw	a3,16(sp)
	lw	a4,12(sp)
	lw	a5,8(sp)
	li	a2,32
	li	a1,-33554432
.L83:
	addi	s0,s0,1
	sb	a2,0(a1)
	lbu	a2,0(s0)
	bne	a2,zero,.L83
	lui	a2,%hi(Next_Ptr_Glob)
	lw	a2,%lo(Next_Ptr_Glob)(a2)
	li	a0,-33554432
	lbu	a1,16(a2)
	addi	a2,a2,16
	beq	a1,zero,.L86
.L84:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L84
.L86:
	li	a2,-33554432
	li	a1,10
	sb	a1,0(a2)
	lui	a2,%hi(.LC20)
	li	a1,32
	addi	a2,a2,%lo(.LC20)
	li	a0,-33554432
.L85:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L85
	lui	a2,%hi(.LC21)
	li	a1,73
	addi	a2,a2,%lo(.LC21)
	li	a0,-33554432
.L87:
	addi	a2,a2,1
	sb	a1,0(a0)
	lbu	a1,0(a2)
	bne	a1,zero,.L87
	mv	a0,a4
	sw	a3,12(sp)
	sw	a5,8(sp)
	call	printhex
	lw	a3,12(sp)
	lw	a5,8(sp)
	lui	a4,%hi(.LC22)
	li	a2,73
	addi	a4,a4,%lo(.LC22)
	li	a1,-33554432
.L88:
	addi	a4,a4,1
	sb	a2,0(a1)
	lbu	a2,0(a4)
	bne	a2,zero,.L88
	mv	a0,a5
	sw	a3,8(sp)
	call	printhex
	lw	a3,8(sp)
	lui	a5,%hi(.LC23)
	li	a4,73
	addi	a5,a5,%lo(.LC23)
	li	a2,-33554432
.L89:
	addi	a5,a5,1
	sb	a4,0(a2)
	lbu	a4,0(a5)
	bne	a4,zero,.L89
	li	a0,7
	sw	a3,8(sp)
	call	printhex
	lw	a3,8(sp)
	lui	a5,%hi(.LC24)
	li	a4,69
	addi	a5,a5,%lo(.LC24)
	li	a2,-33554432
.L90:
	addi	a5,a5,1
	sb	a4,0(a2)
	lbu	a4,0(a5)
	bne	a4,zero,.L90
	mv	a0,a3
	call	printhex
	lui	a5,%hi(.LC25)
	li	a4,83
	addi	a5,a5,%lo(.LC25)
	li	a3,-33554432
.L91:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L91
	lbu	a4,48(sp)
	addi	a5,sp,48
	li	a3,-33554432
	beq	a4,zero,.L94
.L92:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L92
.L94:
	li	a5,-33554432
	li	a4,10
	sb	a4,0(a5)
	lui	a5,%hi(.LC26)
	li	a4,32
	addi	a5,a5,%lo(.LC26)
	li	a3,-33554432
.L93:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L93
	lui	a5,%hi(.LC27)
	li	a4,83
	addi	a5,a5,%lo(.LC27)
	li	a3,-33554432
.L95:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L95
	lbu	a4,80(sp)
	addi	a5,sp,80
	li	a3,-33554432
	beq	a4,zero,.L98
.L96:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L96
.L98:
	li	a5,-33554432
	li	a4,10
	sb	a4,0(a5)
	lui	a5,%hi(.LC28)
	li	a4,32
	addi	a5,a5,%lo(.LC28)
	li	a3,-33554432
.L97:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L97
	lui	a5,%hi(Begin_Time)
	lw	a5,%lo(Begin_Time)(a5)
	lw	s0,%lo(End_Time)(s5)
	lw	a4,44(sp)
	li	a3,-33554432
	sub	s0,s0,a5
	lui	a5,%hi(.LC29)
	sub	s1,s1,a4
	addi	a5,a5,%lo(.LC29)
	li	a4,10
.L99:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L99
	lui	a5,%hi(.LC30)
	li	a4,82
	addi	a5,a5,%lo(.LC30)
	li	a3,-33554432
.L100:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L100
	mv	a0,s0
	call	printdecu
	lui	a5,%hi(.LC31)
	li	a4,69
	addi	a5,a5,%lo(.LC31)
	li	a3,-33554432
.L101:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L101
	mv	a0,s1
	call	printdecu
	li	a5,1000
	mul	s1,s1,a5
	lui	a5,%hi(.LC32)
	li	a4,109
	addi	a5,a5,%lo(.LC32)
	li	a3,-33554432
	divu	a0,s1,s0
.L102:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L102
	call	printdecu
	li	a2,1757
	li	a1,999424
	addi	a1,a1,576
	li	a0,200704
	addi	a0,a0,-704
	lui	a5,%hi(.LC33)
	li	a4,109
	addi	a5,a5,%lo(.LC33)
	li	a3,-33554432
	mul	a2,s0,a2
	divu	a2,a2,a1
	divu	a0,a0,a2
.L103:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L103
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
.L51:
	j	.L51
.L106:
	li	a2,1
	li	t3,1
	j	.L54
.L167:
	lbu	a1,%lo(Ch_1_Glob)(s8)
	li	a5,13
	li	a4,1
	li	a3,1
	j	.L53
.L169:
	lbu	a1,%lo(Ch_1_Glob)(s8)
	j	.L59
.L109:
	lui	a5,%hi(.LC1)
	addi	a5,a5,%lo(.LC1)
	li	a3,-33554432
.L44:
	addi	a5,a5,1
	sb	a4,0(a3)
	lbu	a4,0(a5)
	bne	a4,zero,.L44
	j	.L163
	.size	main, .-main
	.text
	.align	2
	.globl	Proc_2
	.type	Proc_2, @function
Proc_2:
	lui	a5,%hi(Ch_1_Glob)
	lbu	a4,%lo(Ch_1_Glob)(a5)
	li	a5,65
	beq	a4,a5,.L172
	ret
.L172:
	lw	a5,0(a0)
	lui	a4,%hi(Int_Glob)
	lw	a4,%lo(Int_Glob)(a4)
	addi	a5,a5,9
	sub	a5,a5,a4
	sw	a5,0(a0)
	ret
	.size	Proc_2, .-Proc_2
	.align	2
	.globl	Proc_3
	.type	Proc_3, @function
Proc_3:
	lui	a4,%hi(Ptr_Glob)
	lw	a5,%lo(Ptr_Glob)(a4)
	beq	a5,zero,.L174
	lw	a5,0(a5)
	sw	a5,0(a0)
	lw	a5,%lo(Ptr_Glob)(a4)
.L174:
	lui	a4,%hi(Int_Glob)
	lw	a4,%lo(Int_Glob)(a4)
	addi	a4,a4,12
	sw	a4,12(a5)
	ret
	.size	Proc_3, .-Proc_3
	.align	2
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
	.align	2
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
	.align	2
	.globl	Proc_6
	.type	Proc_6, @function
Proc_6:
	li	a4,2
	beq	a0,a4,.L181
	li	a5,3
	sw	a5,0(a1)
	li	a5,1
	beq	a0,a5,.L182
	bleu	a0,a5,.L186
	li	a5,4
	bne	a0,a5,.L187
	sw	a4,0(a1)
.L185:
	ret
.L182:
	lui	a5,%hi(Int_Glob)
	lw	a4,%lo(Int_Glob)(a5)
	li	a5,100
	ble	a4,a5,.L185
.L186:
	sw	zero,0(a1)
	ret
.L187:
	ret
.L181:
	li	a5,1
	sw	a5,0(a1)
	ret
	.size	Proc_6, .-Proc_6
	.align	2
	.globl	Proc_7
	.type	Proc_7, @function
Proc_7:
	addi	a0,a0,2
	add	a1,a0,a1
	sw	a1,0(a2)
	ret
	.size	Proc_7, .-Proc_7
	.align	2
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
	.align	2
	.globl	Func_1
	.type	Func_1, @function
Func_1:
	andi	a0,a0,0xff
	andi	a1,a1,0xff
	beq	a0,a1,.L193
	li	a0,0
	ret
.L193:
	lui	a5,%hi(Ch_1_Glob)
	sb	a0,%lo(Ch_1_Glob)(a5)
	li	a0,1
	ret
	.size	Func_1, .-Func_1
	.align	2
	.globl	Func_2
	.type	Func_2, @function
Func_2:
	lbu	a4,2(a0)
	lbu	a5,3(a1)
	beq	a4,a5,.L196
	addi	sp,sp,-16
	sw	ra,12(sp)
	call	strcmp
	ble	a0,zero,.L198
	lw	ra,12(sp)
	lui	a5,%hi(Int_Glob)
	li	a4,10
	sw	a4,%lo(Int_Glob)(a5)
	li	a0,1
	addi	sp,sp,16
	jr	ra
.L196:
	j	.L196
.L198:
	lw	ra,12(sp)
	li	a0,0
	addi	sp,sp,16
	jr	ra
	.size	Func_2, .-Func_2
	.align	2
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
	.ident	"GCC: (g5964b5cd727) 11.1.0"
	.section	.note.GNU-stack,"",@progbits
