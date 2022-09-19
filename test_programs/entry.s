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

    
#.globl strcpy
strcpy:
    
    mv a2, a0
    andi t0, a2, 3
    beqz t0, .aligned
    
    .align_loop:
        lb t0, 0(a2)
        addi a2, a2, 1
        sb t0, 0(a1)
        addi a1, a1, 1
        beqz a2, .return
        andi t0, a2, 3
        bnez t0, .align_loop
        
    .aligned:
    li t2, -1
    .loop:
        lw t0, 0(a2)
        orc.b t1, t0
        bne t1, t2, .final
        sw t0, 0(a1)
        addi a2, a2, 4
        addi a1, a1, 4
        j .loop
        
    
    .final:
        lb t0, 0(a2)
        addi a2, a2, 1
        sb t0, 0(a1)
        addi a1, a1, 1
        bnez t0, .final

    .return:
    ret
#325971 cycles
