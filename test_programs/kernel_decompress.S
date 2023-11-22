
#define MEM_START (0x80000000)
#define MEM_END (0x84000000)
#define COPY_SIZE  (11<<20)
#define EXTRA_SHIFT (2<<20)
#define COPY_TO (MEM_END - COPY_SIZE - EXTRA_SHIFT)
#define DTB_ADDR (0x84000000 - 1024*1024)

.text
.globl _start
_start:
    li a0, COPY_TO
    li a1, MEM_START
    li a2, COPY_SIZE
    call memcpy
    la a0, do_decompress
    li a1, COPY_TO-MEM_START
    add a0, a0, a1
    fence.i
    jr a0

print:
    li a3, 0x10000000
    lbu a2, 0(a0)
    .print_loop:
        lbu a1, 5(a3)
        andi a1, a1, 32
        beqz a1, .print_loop
        sb a2, 0(a3)
        addi a0, a0, 1
        lbu a2, 0(a0)
        bnez a2, .print_loop
    ret

.align 2
_exception:
    csrw mscratch, a0
    li a0, 0x81000000
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

    csrr a0, mcause
    call printhex

    csrr a0, mepc
    call printhex

    li a0, 0x10000000
    li a1, 10
    sb a1, 0(a0)

    li s0, 0x81000000
    addi s1, s0, 128
    .exception_dump_regs:
        lw a0, 0(s0)
        call printhex
        addi s0, s0, 4
        bne s0, s1, .exception_dump_regs
    
    li a0, 0x10000000
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
    .terminate:
    li a0, 0x11100000
    li a1, 0x55
    sb a1, 0(a0)
    .end_loop:
        j .end_loop

printhex:
    mv a5, a0
    li a0, 0x10000000
    li a6, 28
    .printhex_loop:
        lbu a1, 5(a0)
        andi a1, a1, 32
        beqz a1, .printhex_loop
        srl a1, a5, a6
        andi a1, a1, 0xF
        addi a1, a1, -10
        bgez a1, .printhex_af
        addi a1, a1, 10+'0'-'A'    
        .printhex_af:
        addi a1, a1, 'A'
        sb a1, 0(a0)
        addi a6, a6, -4
        bgez a6, .printhex_loop
    .printhex_wait:
    lbu a1, 5(a0)
    andi a1, a1, 32
    beqz a1, .printhex_wait
    li a1, '\n'
    sb a1, 0(a0)
    ret

do_decompress:

    la a0, _exception
    csrrw x0, mtvec, a0
    csrrw x0, stvec, a0
    
    la a0, .message
    call print

    li sp, MEM_END - 1024
    la a0, _binary_image_start
    li a1, 10088218
    li a2, MEM_START
    li a3, COPY_TO-MEM_START
    call fastlz_decompress

    li a0, DTB_ADDR
    la a1, _binary_dtb_start
    li a2, 1581
    call memcpy
    
    
    la a0, .message2
    call print

    fence.i
    fence.i

    li a0, 0
    li a1, DTB_ADDR
    li a2, 0
    li s0, MEM_START
    jr s0

.rodata:
.message: .string "Decompressing...\n"
.message2: .string "Decompressing done\n"
