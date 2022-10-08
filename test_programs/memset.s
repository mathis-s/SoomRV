.text
.globl main
main:
    
    li a0, 0x1000
    li a1, 'A'
    li a2, 10
    call memset
    li a0, 0x1000
    li a1, '\n'
    sb a1, 10(a0)
    sb zero, 11(a0)    
    call print
    
    li a0, 0x1100
    li a1, 0x1000
    li a2, 12
    call memcpy
    
    li a0, 0x1100
    call print
    
    ebreak

    
print:
    li t1, 0xfe000000
    .print_loop:
        lb t0, 0(a0)
        beqz t0, .print_end
        sb t0, 0(t1)
        addi a0, a0, 1
        j .print_loop
    .print_end:
    ret
