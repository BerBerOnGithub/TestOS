; ===========================================================================
; commands/cmd_basic.asm - Core shell commands
;   help, clear, echo, hello, reboot, halt
; ===========================================================================

; -
; help  (paged: page 1 +' any key +' page 2)
; Screen is 80x25. Each page is sized to fit without scrolling.
; -
cmd_help:
    push ax
    push bx
    push si

    ; - Page 1 -
    call screen_clear
    mov  si, str_help_pg1
    mov  bl, ATTR_CYAN
    call puts_c

    ; prompt then wait for any key
    mov  si, str_help_more
    mov  bl, ATTR_YELLOW
    call puts_c
    xor  ah, ah
    int  0x16               ; wait for keypress (discarded)

    ; - Page 2 -
    call screen_clear
    mov  si, str_help_pg2
    mov  bl, ATTR_CYAN
    call puts_c

    pop  si
    pop  bx
    pop  ax
    jmp  shell_exec.done

; -
; clear
; -
cmd_clear:
    call screen_clear
    jmp  shell_exec.done

; -
; echo <text>
; -
cmd_echo:
    push si
    push bx
    lea  si, [cmd_buf + 5]   ; skip "echo "
    call puts
    call nl
    pop  bx
    pop  si
    jmp  shell_exec.done

; -
; hello - built-in Hello World program
; -
cmd_hello:
    push si
    push bx
    mov  si, str_exec_pre
    mov  bl, ATTR_YELLOW
    call puts_c
    call nl
    mov  si, str_hello_out
    mov  bl, ATTR_GREEN
    call puts_c
    mov  si, str_exec_post
    mov  bl, ATTR_YELLOW
    call puts_c
    call nl
    pop  bx
    pop  si
    jmp  shell_exec.done

; -
; reboot
; -
cmd_reboot:
    push si
    push bx
    mov  si, str_rebooting
    mov  bl, ATTR_YELLOW
    call puts_c
    call nl
    pop  bx
    pop  si
    mov  al, 0xFE
    out  0x64, al
    cli
    hlt

; -
; halt
; -
cmd_halt:
    push si
    push bx
    mov  si, str_halting
    mov  bl, ATTR_YELLOW
    call puts_c
    call nl
    pop  bx
    pop  si
    cli
    hlt
