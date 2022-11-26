.text
    
printdecu_fast:
	# get space on stack
	addi sp, sp, -8
	mv a4, sp
	li a1, 10

	.loop_printdecu_fast:
		# divide
		# divu a2, a0, a1
		li a2, 0xcccccccd
		mulhu a2, a0, a2
		srli a2, a2, 3
		# rounded down original
		mul a3, a2, a1
		
		# get char
		sub a3, a0, a3
		ori a3, a3, 0x30
		sb a3, 0(a4)
		addi a4, a4, 1
		mv a0, a2
		bnez a2, .loop_printdecu_fast
		
	li a1, 0xff000003
	.loop_print:
		addi a4, a4, -1
		lb a0, 0(a4)
		sb a0, 0(a1)
		bne a4, sp, .loop_print
	
	addi sp, sp, 8
	li a0, 10
	sb a0, 0(a1)
	ret

.globl main
main:
	
	mv s3, ra
	
	li s2, 401
	
	li s0, 0x3C23D70A # 0.01f
	li s1, 0xC000A3D7 # -2.01f
	li s4, 0x49742400 # 1000000.0f
	li s5, 0x3f800000 # 1.0f
	li s6, 0x3FC00000 # 1.5f
	li s7, 0x3F000000 # 0.5f
	.loop:
		
		fadd.s s1, s1, s0
		
		fsqrt.s a0, s1
		fdiv.s a0, s5, a0
		fmul.s a0, a0, s4
		fcvt.w.s a0, a0
		call printdecu_fast
		
		srli a0, s1, 1
		li a1, 0x5f3759df
		sub a0, a1, a0
		fmul.s a1, a0, a0
		fmul.s a3, s1, s7
		fmul.s a1, a1, a3
		fsub.s a1, s6, a1
		fmul.s a0, a0, a1
		
		fmul.s a0, a0, s4
		fcvt.w.s a0, a0
		call printdecu_fast
		
		li a0, 10
		li a1, 0xff000003
		sb a0, 0(a1)
		
		addi s2, s2, -1
		bnez s2, .loop
	
	mv ra, s3
	ret
