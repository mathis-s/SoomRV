.text
.align 4
return_42:
    li a0, 42
    ret


.globl main
main:
    
    sw ra, -4(sp)
    
    # Run function once
    call return_42
    call printhex


    # write a bunch of garbage
    li a0, 0x80040000
    li a1, 100
    .loop:
        sb s0, 0(a0)
        add a0, a0, a1
        addi a1, a1, -1
        bnez a1, .loop

    # Overwrite function to return 43
    la a0, return_42
    li a1, 0x02b00513
    sw a1, 0(a0)

    # Re-run once, should still print 42
    call return_42
    call printhex

    fence.i
    
    # Should now print 43
    call return_42
    call printhex
    
    # return 44
    li a0, 0x80040000
    li a1, 0x02c00513
    sw a1, 0(a0)
    li a1, 0x8082
    sh a1, 4(a0)
    
    fence.i

    jalr a0
    call printhex
    
    lw ra, -4(sp)
    ret
    
