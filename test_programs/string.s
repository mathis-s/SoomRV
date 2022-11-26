.section .rodata
.string:
.string "this is a test string\n"

.text
.globl main

main:
    
    li s0, 24
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
    
    # Print mispreds and total branches
    li a0, 0xff0000a0
    lw s0, 8(a0)
    lw a0, 0(a0)
    call printdecu
    mv a0, s0
    call printdecu
    
    ebreak

    
print:
    li t1, 0xff000003
    .print_loop:
        lb t0, 0(a0)
        beqz t0, .print_end
        sb t0, 0(t1)
        addi a0, a0, 1
        j .print_loop
    .print_end:
    ret
