.set IO_ADDR, 0x10000000
.section .rodata
.str_boot_msg: .string "SoomRV booting\n"
.str_except_msg: .string "Unhandled Exception "
.section .data
.reg_buf:
    .zero 4*32
.text
.globl _start
_start:
    
    # set irq handler address
    la a0, _exception
    csrrw x0, mtvec, a0
    csrrw x0, stvec, a0
    
    #la a0, .str_boot_msg
    #call prints
    #call checksum
    #call printhex
    
    li sp, 0x80020000
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
    
    .align 2
    .terminate:
    li a0, 0x11100000
    li a1, 0x55
    sb a1, 0(a0)
    .end_loop:
        j .end_loop
    

.align 2
_exception:
    csrw mscratch, a0
    la a0, .reg_buf
    sw x0, 0(a0)
    sw x1, 4(a0)
    sw x2, 8(a0)
    sw x3, 12(a0)
    sw x4, 16(a0)
    sw x5, 20(a0)
    sw x6, 24(a0)
    sw x7, 28(a0)
    sw x8, 32(a0)
    sw x9, 36(a0)
    #sw x10, 40(a0)
    sw x11, 44(a0)
    sw x12, 48(a0)
    sw x13, 52(a0)
    sw x14, 56(a0)
    sw x15, 60(a0)
    sw x16, 64(a0)
    sw x17, 68(a0)
    sw x18, 72(a0)
    sw x19, 76(a0)
    sw x20, 80(a0)
    sw x21, 84(a0)
    sw x22, 88(a0)
    sw x23, 92(a0)
    sw x24, 96(a0)
    sw x25, 100(a0)
    sw x26, 104(a0)
    sw x27, 108(a0)
    sw x28, 112(a0)
    sw x29, 116(a0)
    sw x30, 120(a0)
    sw x31, 124(a0)
    csrr a1, mscratch
    sw a1, 40(a0)

    la a0, .str_except_msg
    call prints

    csrr a0, mcause
    call printhex

    csrr a0, mepc
    call printhex

    li a0, IO_ADDR
    li a1, 10
    sb a1, 0(a0)

    la s0, .reg_buf
    addi s1, s0, 128
    .exception_dump_regs:
        lw a0, 0(s0)
        call printhex
        addi s0, s0, 4
        bne s0, s1, .exception_dump_regs
    
    li a0, IO_ADDR
    li a1, 10
    sb a1, 0(a0)
    
    # Reading the instruction might cause another exception,
    # so set tvec to terminate.
    la a0, .terminate
    csrw mtvec, a0

    csrr a0, mepc
    lb a1, 3(a0)
    slli a1, a1, 24
    lb a2, 2(a0)
    slli a2, a2, 16
    or a1, a1, a2
    lb a2, 1(a0)
    slli a2, a2, 8
    or a1, a1, a2
    lb a2, 0(a0)
    or a0, a1, a2

    call printhex

    j .terminate

checksum:
    li s0, 0x80000000
    li s1, 0x80000000 + 65536*4
    mv s2, ra
    li s3, 0
    .checksum_loop:
        lw a0, 0(s0)
        add s3, s3, a0
        addi s0, s0, 4
        bne s0, s1, .checksum_loop
    mv ra, s2
    mv a0, s3
    ret

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
    
    li a4, -1
    .align 4
    .loop_strcmp:
        lw a2, 0(a0)
        lw a3, 0(a1)
        bne a2, a3, .final_strcmp
        orc.b a2, a2
        bne a2, a4, .final_strcmp

        lw a2, 4(a0)
        lw a3, 4(a1)
        bne a2, a3, .final_strcmp
        orc.b a2, a2
        bne a2, a4, .final_strcmp

        addi a0, a0, 8
        addi a1, a1, 8
        j .loop_strcmp
    
    .final_strcmp:
        lb a2, 0(a0)
        lb a3, 0(a1)
        bne a2, a3, .return_strcmp
        beqz a2, .return_strcmp

        lb a2, 1(a0)
        lb a3, 1(a1)
        bne a2, a3, .return_strcmp
        beqz a2, .return_strcmp

        lb a2, 2(a0)
        lb a3, 2(a1)
        bne a2, a3, .return_strcmp
        beqz a2, .return_strcmp

        lb a2, 3(a0)
        lb a3, 3(a1)
        
    .return_strcmp:
    sub a0, a2, a3
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

.globl prints
prints:
    li a1, IO_ADDR
    .prints_loop:
        lbu a2, 0(a0)
        beqz a2, .prints_ret
        addi a0, a0, 1
        sb a2, 0(a1)
        j .prints_loop
    .prints_ret:
    ret
