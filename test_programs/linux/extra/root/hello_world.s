.section .rodata
.message: .ascii "Hello, World\n"
.set message_len, .-.message
.text
.globl _start
_start: 
	li a7, 64
	li a0, 1
	la a1, .message
	la a2, message_len
	ecall

	li a7, 82
	li a0, 1
	ecall

	li a7, 93
	li a0, 0
	ecall
