; ===========================================================================
; core/keyboard.asm - PS/2 keyboard input and line editor
; ===========================================================================

cmd_buf:  times 128 db 0
cmd_len:  db 0

; -
; shell_readline - read a line of input into cmd_buf
; -
shell_readline:
    push ax
    push bx
    push cx
    push di
    lea  di, [cmd_buf]
    xor  cx, cx
.rl_loop:
    xor  ah, ah
    int  0x16
    cmp  al, 13
    je   .rl_enter
    cmp  al, 8
    je   .rl_bs
    or   al, al
    jz   .rl_loop
    cmp  cx, 127
    jge  .rl_loop
    stosb
    inc  cx
    mov  bl, [shell_attr]
    call putc_color
    jmp  .rl_loop
.rl_bs:
    or   cx, cx
    jz   .rl_loop
    dec  di
    dec  cx
    mov  byte [di], 0
    mov  al, 8
    mov  bl, [shell_attr]
    call putc_color
    mov  al, ' '
    call putc_color
    mov  al, 8
    call putc_color
    jmp  .rl_loop
.rl_enter:
    mov  byte [di], 0
    mov  [cmd_len], cl
    call nl
    pop  di
    pop  cx
    pop  bx
    pop  ax
    ret
