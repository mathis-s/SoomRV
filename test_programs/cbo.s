.text
.globl main

main: 
    
    li s0, 4
    .loop_main:
        li a0, 42
        li a1, 0x4000
        sw a0, 0(a1)
        
        # make sure clean works and value persists
        cbo.clean 0(a1)
        
        li a1, 0x4000
        lw a0, 0(a1)
        call printhex
        
        li a1, 0x4000
        cbo.clean 0(a1)
        
        li a1, 0x4000
        lw a0, 0(a1)
        call printhex
        
        
        # modify value
        li a1, 0x4000
        li a0, 0xdeadbeef
        sw a0, 0(a1)
        
        # print modified value
        li a1, 0x4000
        lw a0, 0(a1)
        call printhex
        
        # undo modification using cbo.inval
        cbo.inval 0(a1)
        
        # print original value
        li a1, 0x4000
        lw a0, 0(a1)
        call printhex
        
        # modify value again
        li a1, 0x4000
        li a0, 0xdeadbeef
        sw a0, 0(a1)
        
        # flush modification to main memory
        cbo.flush 0(a1)
        
        # print modified value
        li a1, 0x4000
        lw a0, 0(a1)
        call printhex
        
        
        li a0, 10
        li a1, 0xff000003
        sb a0, 0(a1)
        
        addi s0, s0, -1
        bnez s0, .loop_main
    
    
    
    li a0, 128
    .loop:
        addi a0, a0, -1
        bnez a0, .loop
    
    
    ebreak
