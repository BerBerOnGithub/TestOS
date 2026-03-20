; ===========================================================================
; commands/cmd_fun.asm - Entertainment commands
;   fortune, guess, ascii, colors
; ===========================================================================

; -
; fortune - display a random quote
; -
cmd_fortune:
    push ax
    push bx
    push dx
    push si

    call get_rand_byte
    xor  ah, ah
    xor  dx, dx
    mov  bx, FORTUNE_COUNT
    div  bx                  ; DX = random % FORTUNE_COUNT

    mov  bx, dx
    shl  bx, 1
    mov  si, [fortune_table + bx]

    call nl
    push si
    mov  si, str_fortune_hdr
    mov  bl, ATTR_YELLOW
    call puts_c
    pop  si
    mov  bl, ATTR_BRIGHT
    call puts_c
    mov  al, '"'
    mov  bl, ATTR_YELLOW
    call putc_color
    call nl
    call nl

    pop  si
    pop  dx
    pop  bx
    pop  ax
    jmp  shell_exec.done

; -
; colors - display all 16 foreground color swatches
; -
cmd_colors:
    push ax
    push bx
    push cx
    push si

    call nl
    mov  si, str_colors_hdr
    mov  bl, ATTR_BRIGHT
    call puts_c
    call nl

    xor  cx, cx
.cl_lp:
    cmp  cx, 16
    jge  .cl_done

    mov  bl, ATTR_NORMAL
    mov  al, ' '
    call putc_color
    call putc_color
    mov  al, '0'
    call putc_color
    mov  al, 'x'
    call putc_color
    mov  al, '0'
    call putc_color
    mov  al, cl
    cmp  al, 10
    jl   .cl_dig
    add  al, 'A' - 10
    jmp  .cl_hex_out
.cl_dig:
    add  al, '0'
.cl_hex_out:
    call putc_color
    mov  al, ' '
    call putc_color
    call putc_color

    mov  bl, cl
    mov  si, str_clr_sample
    call puts_c
    call nl

    inc  cx
    jmp  .cl_lp

.cl_done:
    call nl
    pop  si
    pop  cx
    pop  bx
    pop  ax
    jmp  shell_exec.done

; -
; guess - number guessing game (1-100)
; -
cmd_guess:
    push ax
    push bx
    push cx
    push dx
    push si

    call get_rand_byte
    xor  ah, ah
    xor  dx, dx
    mov  bx, 100
    div  bx
    inc  dx
    mov  [guess_secret], dl
    mov  byte [guess_tries], 0

    mov  si, str_guess_intro
    mov  bl, ATTR_CYAN
    call puts_c

.g_loop:
    mov  si, str_guess_prompt
    mov  bl, ATTR_YELLOW
    call puts_c
    call shell_readline

    mov  si, str_quit
    call strcmp_buf
    je   .g_quit

    lea  si, [cmd_buf]
    call parse_uint16

    cmp  ax, 1
    jl   .g_invalid
    cmp  ax, 100
    jg   .g_invalid

    inc  byte [guess_tries]

    xor  bh, bh
    mov  bl, [guess_secret]
    cmp  ax, bx
    je   .g_correct
    jb   .g_low

    mov  si, str_too_high
    mov  bl, ATTR_RED
    call puts_c
    jmp  .g_loop

.g_low:
    mov  si, str_too_low
    mov  bl, ATTR_RED
    call puts_c
    jmp  .g_loop

.g_correct:
    mov  si, str_g_correct
    mov  bl, ATTR_GREEN
    call puts_c
    xor  ah, ah
    mov  al, [guess_tries]
    call print_uint
    mov  si, str_g_tries
    mov  bl, ATTR_GREEN
    call puts_c
    call nl
    call nl
    jmp  .g_end

.g_invalid:
    mov  si, str_g_invalid
    mov  bl, ATTR_YELLOW
    call puts_c
    jmp  .g_loop

.g_quit:
    mov  si, str_g_quit
    mov  bl, ATTR_YELLOW
    call puts_c
    xor  ah, ah
    mov  al, [guess_secret]
    call print_uint
    call nl
    call nl

.g_end:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    jmp  shell_exec.done

; -
; ascii - print ASCII table (chars 32-126)
; -
cmd_ascii:
    push ax
    push bx
    push cx
    push si

    call nl
    mov  si, str_ascii_hdr
    mov  bl, ATTR_CYAN
    call puts_c

    mov  cx, 32
.asc_lp:
    cmp  cx, 127
    jge  .asc_done

    mov  ax, cx
    sub  ax, 32
    test ax, 0x000F
    jnz  .asc_norow

    call nl
    mov  ax, cx
    call print_uint_3
    mov  al, ':'
    mov  bl, ATTR_YELLOW
    call putc_color
    mov  al, ' '
    mov  bl, ATTR_NORMAL
    call putc_color

.asc_norow:
    mov  al, cl
    mov  bl, ATTR_BRIGHT
    call putc_color
    mov  al, ' '
    mov  bl, ATTR_NORMAL
    call putc_color

    inc  cx
    jmp  .asc_lp

.asc_done:
    call nl
    call nl
    pop  si
    pop  cx
    pop  bx
    pop  ax
    jmp  shell_exec.done
