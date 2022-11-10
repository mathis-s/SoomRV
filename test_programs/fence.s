.text

return_42:
    li a0, 42
    ret


.globl main
main:
    
    sw ra, -4(sp)
    
    # Run function once
    call return_42
    call printhex
    
    
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
    
    lw ra, -4(sp)
    ret
    
