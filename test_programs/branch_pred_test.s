.text
.globl main
main:
    li a1, 10
    .loop:
        addi a0, a0, 1
        beq a0, a1, .end
        j .loop
    .end:
    ebreak
