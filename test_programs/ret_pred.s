.text
.globl main

func2:
    ret

func:
    mv s2, ra
    call func2
    call func2
    mv ra, s2
    ret
main:
    li s0, 32
    mv s1, ra
    .loop:
        
        call func
        call func
        call func
        call func
        call func

        addi s0, s0, -1
        bnez s0, .loop
    
    mv ra, s1
    ret
