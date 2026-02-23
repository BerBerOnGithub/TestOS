.code32
.section .text
.globl _start
.extern kmain
_start:
    movl $0x9FFFF, %esp
    call kmain
.hang:
    cli
    hlt
    jmp .hang
