.text
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
		call printdecu
		
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
		call printdecu
		
		li a0, 10
		li a1, 0x10000000
		sb a0, 0(a1)
		
		addi s2, s2, -1
		bnez s2, .loop
	
	fsgnj.s ra, s3, s3
	ret
