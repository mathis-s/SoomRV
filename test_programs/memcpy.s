.text
.globl main
main:
    li a0, 0x80000000
    li a1, 0x80020000
    li a2, 0x80008000
    
    .align 4
    .loop:
        lw a3, 0(a0)
        sw a3, 0(a1)
        lw a4, 4(a0)
        sw a4, 4(a1)

        addi a0, a0, 8
        addi a1, a1, 8
        bne a0, a2, .loop

    ret
