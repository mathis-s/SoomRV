.text
.globl main
main:

    mv s0, ra

    li a0, 32
    li a1, 16
    sh2add a0, a1, a0
    call printhex

    li a0, 0xFF
    li a1, 0xFFFFFFFF
    xnor a0, a1, a0
    call printhex

    li a0, 0xFF
    li a1, 0xFFFFFFFF
    andn a0, a1, a0
    call printhex

    li a0, 0xFF
    li a1, 0xFFFFFFFF
    orn a0, a0, a1
    call printhex

    li a0, 0xFF
    sext.b a0, a0
    call printhex

    li a0, -1
    zext.h a0, a0
    call printhex

    li a0, 32767
    sext.h a0, a0
    call printhex


	li a0, 0x00010000
    clz a0, a0
    call printhex

	li a0, 0x00010000
    ctz a0, a0
    call printhex

	li a0, 0xdeadbeef
    cpop a0, a0
    call printhex

	li a0, 0xabcedf0
    orc.b a0, a0
    call printhex

	li a0, 0xabcedf00
    rev8 a0, a0
    call printhex

    mv ra, s0
    ret
