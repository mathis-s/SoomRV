.text
.globl main
main:
    
    li s0, 100
    .loopOuter:
    li a0, 0x80000000
    li a1, 0x80000000+4096

    li a2, 0
    li a3, 0
    
    .align 4
    .loop:
        lw a4, 0(a0)
        lw a5, 4(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 8(a0)
        lw a5, 12(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 16(a0)
        lw a5, 20(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 24(a0)
        lw a5, 28(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 0(a0)
        lw a5, 4(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 8(a0)
        lw a5, 12(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 16(a0)
        lw a5, 20(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 24(a0)
        lw a5, 28(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 0(a0)
        lw a5, 4(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 8(a0)
        lw a5, 12(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 16(a0)
        lw a5, 20(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 24(a0)
        lw a5, 28(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 0(a0)
        lw a5, 4(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 8(a0)
        lw a5, 12(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 16(a0)
        lw a5, 20(a0)
        add a2, a2, a4
        add a3, a3, a5

        lw a4, 24(a0)
        lw a5, 28(a0)
        add a2, a2, a4
        add a3, a3, a5

        add a0, a0, 32
        bne a0, a1, .loop
    
    addi s0, s0, -1
    bnez s0, .loopOuter
    add a0, a2, a3
    ret
        
