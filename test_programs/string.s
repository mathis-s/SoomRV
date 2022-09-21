.section .rodata
.string:
.string "this is a test string\n"

.text
.globl main


main:
    
    li s0, 8
    .main_loop:
        la a0, .string
        call print
        
        la a1, .string
        li a0, 0x800
        call strcpy
        li a0, 0x800
        call print
        
        li a0, 0x800
        la a1, .string
        call strcmp
        call printdecu
        
        li a0, 0x800
        la a1, .string
        li t0, 'T'
        sb t0, 10(a0)
        call strcmp
        call printdecu
        
        addi s0, s0, -1
        bnez s0, .main_loop
    
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
