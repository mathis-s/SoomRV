.text
.globl main
main:
    
    c.li a0, 15
    call printdecu
    
    c.li a0, 15
    c.addi a0, 15
    call printdecu
    
    c.li a0, 15
    c.add a0, a0
    call printdecu
    
    c.li a0, 15
    c.sub a0, a0
    call printdecu
    
    c.li a0, 21
    c.slli a0, 1
    call printdecu
    
    li a0, 168
    c.srli a0, 2
    call printdecu
    
    c.li a0, 3
    c.andi a0, -2
    call printdecu
    
    c.addi4spn a0, sp, 64
    call printdecu
    
    c.addi16sp sp, 64
    c.mv a0, sp
    call printdecu
    
    
    li s0, 7
    .loop:
        mv a0, s0
        call printdecu
        addi s0, s0, -1
        bnez s0, .loop
    
    li s0, 123
    sw s0, 12(sp)
    lw a0, 12(sp)
    call printdecu
    
    li s0, 120
    sw s0, 0(s0)
    lw a0, 0(s0)
    call printdecu
    
    ebreak
