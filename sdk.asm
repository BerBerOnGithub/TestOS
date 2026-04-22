; ===========================================================================
; sdk.asm - NatureOS App SDK
; ===========================================================================

%include "include/version.inc"

; syscall numbers (passed in AH)
SYS_PRINT_STR   equ 0x00
SYS_PRINT_CHAR  equ 0x01
SYS_PRINT_UINT  equ 0x02
SYS_NEWLINE     equ 0x03
SYS_RAND        equ 0x04
SYS_READLINE    equ 0x05
SYS_CLEAR       equ 0x06
SYS_PRINT_INT   equ 0x07
SYS_PRINT_INT32 equ 0x09
SYS_GETKEY      equ 0x0A

; color constants
CLR_NORMAL  equ 0x07
CLR_BRIGHT  equ 0x0F
CLR_GREEN   equ 0x0A
CLR_YELLOW  equ 0x0E
CLR_CYAN    equ 0x0B
CLR_RED     equ 0x0C

; far call to fixed kernel syscall entry at 0x0000:0x8100
%macro syscall 0
    db 0x9A              ; far call opcode
    dw 0x8100            ; offset
    dw 0x0000            ; segment
%endmacro

%macro print_str 2
    mov  si, %1
    mov  bl, %2
    mov  ah, SYS_PRINT_STR
    syscall
%endmacro

%macro print_char 2
    mov  al, %1
    mov  bl, %2
    mov  ah, SYS_PRINT_CHAR
    syscall
%endmacro

%macro newline 0
    mov  ah, SYS_NEWLINE
    syscall
%endmacro

%macro print_uint_ax 0
    mov  cx, ax
    mov  ah, SYS_PRINT_UINT
    syscall
%endmacro

%macro print_int_ax 0
    mov  cx, ax
    mov  ah, SYS_PRINT_INT
    syscall
%endmacro

%macro print_int32_dxax 0
    push ax
    mov  cx, dx
    pop  dx
    mov  ah, SYS_PRINT_INT32
    syscall
%endmacro

%macro rand_byte 0
    mov  ah, SYS_RAND
    syscall
%endmacro

%macro readline 1
    mov  di, %1
    mov  ah, SYS_READLINE
    syscall
%endmacro

%macro getkey 0
    mov  ah, SYS_GETKEY
    syscall
%endmacro

%macro app_exit 0
    retf
%endmacro
