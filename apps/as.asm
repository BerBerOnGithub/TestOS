; ===========================================================================
; apps/ascii.asm - ASCII table (32-126)
; ===========================================================================
[BITS 16]
[ORG 0x0000]

%include "sdk.asm"

    mov  ax, cs
    mov  ds, ax

    newline
    print_str str_hdr, CLR_CYAN

    mov  cx, 32
.loop:
    cmp  cx, 127
    jge  .done

    ; new row every 16 chars
    mov  ax, cx
    sub  ax, 32
    and  ax, 0x000F
    jnz  .no_row

    newline
    mov  ax, cx
    call print3             ; print 3-digit decimal
    print_char ':', CLR_YELLOW
    print_char ' ', CLR_NORMAL

.no_row:
    mov  al, cl
    mov  bl, CLR_BRIGHT
    mov  ah, SYS_PRINT_CHAR
    syscall
    print_char ' ', CLR_NORMAL

    inc  cx
    jmp  .loop

.done:
    newline
    newline
    retf

; print AX as 3-digit decimal (always 3 digits)
print3:
    push ax
    push bx
    push dx
    xor  dx, dx
    mov  bx, 100
    div  bx              ; AX=hundreds DX=remainder
    add  al, '0'
    mov  bl, CLR_YELLOW
    mov  ah, SYS_PRINT_CHAR
    syscall
    mov  ax, dx
    xor  dx, dx
    mov  bx, 10
    div  bx              ; AX=tens DX=ones
    add  al, '0'
    mov  bl, CLR_YELLOW
    mov  ah, SYS_PRINT_CHAR
    syscall
    mov  al, dl
    add  al, '0'
    mov  bl, CLR_YELLOW
    mov  ah, SYS_PRINT_CHAR
    syscall
    pop  dx
    pop  bx
    pop  ax
    ret

str_hdr: db ' ASCII Table (32-126)', 13, 10, 0