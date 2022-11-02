.text
.globl main
main:
    
    sw ra, -4(sp)
    
    li a0, 0x1000
    li a1, 0
    li a2, 0x5000
    
    .loop_store:
        sw a1, 0(a0)
        addi a1, a1, 1
        addi a0, a0, 4
        ble a0, a2, .loop_store
    
    li a0, 0x1000
    li a1, 0
    .loop_load:
        lw a3, 0(a0)
        add a1, a1, a3
        addi a0, a0, 4
        ble a0, a2, .loop_load
    
    li a0, 8390656
    sub a0, a1, a0
    call printdecu
    
    lw ra, -4(sp)
    ret

# 33102 cycles
