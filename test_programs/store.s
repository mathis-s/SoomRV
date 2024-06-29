.text
.globl main

main:

    li a0, 1024
    li a1, 0x80000000+0x10000
    li a2, 0xdeadbeef
    .align 4
    .loop:
        addi a0, a0, -1
        
        sw x0, 0(a1)
        sw x0, 4(a1)
        sw x0, 8(a1)
        sw x0, 12(a1)
        
        sw x0, 16+0(a1)
        sw x0, 16+4(a1)
        sw x0, 16+8(a1)
        sw x0, 16+12(a1)

        and a3, a2, 1
        srl a2, a2, 1
        bnez a3, .loop

        sw x0, 32+0(a1)
        sw x0, 32+4(a1)
        sw x0, 32+8(a1)
        sw x0, 32+12(a1)

        sw x0, 48+0(a1)
        sw x0, 48+4(a1)
        sw x0, 48+8(a1)
        sw x0, 48+12(a1)

        #addi a1, a1, 64
        bnez a0, .loop
    ret
