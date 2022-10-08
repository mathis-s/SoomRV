.globl _start
_start:
    
    # set irq handler address
    lui a0, %hi(_exception)
    addi a0, a0, %lo(_exception)
    li a1, 0xff000000
    sw a0, 0(a1)
    
    li sp, 0x10000
    call main
    ebreak
    
_exception:
    #li a1, 0xff000004
    #lw a1, 0(a1)
    #call printhex
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
    
    li a4, 0xfe000000
    bnez a0, .print2
    li a0, 0x30
    sb a0, 0(a4)
    j .end2
    
    .print2:
    li a1, 1000000000
    li a3, 10
    li a5, 0

    .loop2:
        divu a2, a0, a1
        remu a0, a0, a1
        or a5, a5, a2
        ori a2, a2, 0x30
        
        beqz a5, .skip2
            sb a2, 0(a4)
        .skip2:
        
        divu a1, a1, a3
        bnez a1, .loop2
    
    .end2:
    li a0, 10
    sb a0, 0(a4)
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
	li	a4,0xfe000000
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
