.set IO_ADDR, 0xff000003

.globl _start
_start:
    
    # set irq handler address
    la a0, _exception
    csrrw x0, mtvec, a0
    
    li sp, 0x20000
    call main
    
    # print IPC
    #li a0, 0xff000098
    #li a1, 0xff000080
    #lw a0, 0(a0)
    #lw a1, 0(a1)
    #
    #li a2, 1000
    #mul a0, a0, a2
    #divu a0, a0, a1
    #call printdecu
    ebreak

.align 2
_exception:
    ebreak

    
.globl strcpy
strcpy:
    
    mv a2, a0
    andi t0, a2, 3
    beqz t0, .aligned
    
    .align_loop:
        lb t0, 0(a1)
        addi a1, a1, 1
        sb t0, 0(a2)
        addi a2, a2, 1
        beqz a1, .return
        andi t0, a1, 3
        bnez t0, .align_loop
        
    .aligned:
    li t2, -1
    .loop:
        lw t0, 0(a1)
        orc.b t1, t0
        bne t1, t2, .final
        sw t0, 0(a2)
        addi a1, a1, 4
        addi a2, a2, 4
        j .loop
        
    
    .final:
        lb t0, 0(a1)
        addi a1, a1, 1
        sb t0, 0(a2)
        addi a2, a2, 1
        bnez t0, .final

    .return:
    ret

.globl strcmp
strcmp:
    
    li t2, -1
    .loop_strcmp:
        lw t0, 0(a0)
        lw t1, 0(a1)
        bne t0, t1, .final_strcmp
        orc.b t0, t0
        bne t0, t2, .final_strcmp
        addi a0, a0, 4
        addi a1, a1, 4
        j .loop_strcmp
    
    .final_strcmp:
        lb t0, 0(a0)
        lb t1, 0(a1)
        bne t0, t1, .return_strcmp
        beqz t0, .return_strcmp
        addi a0, a0, 1
        addi a1, a1, 1
        j .final_strcmp
        
    .return_strcmp:
    sub a0, t0, t1
    ret

.globl printdecu
printdecu:
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
		
	li a1, IO_ADDR
	.loop_print:
		addi a4, a4, -1
		lb a0, 0(a4)
		sb a0, 0(a1)
		bne a4, sp, .loop_print
	
	addi sp, sp, 8
	li a0, 10
	sb a0, 0(a1)
	ret
    
.globl memcpy
.type	memcpy, @function
memcpy:
    beqz a2, .memcpy_end
    mv a3, a0
    .memcpy_loop:
        lb a4, 0(a1)
        sb a4, 0(a3)
        addi a1, a1, 1
        addi a3, a3, 1
        addi a2, a2, -1
        bnez a2, .memcpy_loop
    .memcpy_end:
    ret
    
.globl memset
.type	memset, @function
memset:
    beqz a2, .memset_end
    mv a3, a0
    .memset_loop:
        sb a1, 0(a3)
        addi a3, a3, 1
        addi a2, a2, -1
        bnez a2, .memset_loop
    .memset_end:
    ret

.section .rodata
hexLut:
	.ascii	"0123456789abcdef"
.text
.globl printhex
printhex:
	lui	a5,%hi(hexLut)
	addi	a5,a5,%lo(hexLut)
	srli	a4,a0,28
	add	a4,a5,a4
	lbu	a3,0(a4)
	li	a4,IO_ADDR
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
	li a5, 10
	sb a5, 0(a4)
	ret
