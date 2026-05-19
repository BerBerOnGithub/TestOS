; ===========================================================================
; pm/pm_screen.asm - 32-bit VGA text mode driver
;
; No BIOS calls. All output goes directly to 0xB8000.
; Hardware cursor updated via CRT controller ports 0x3D4/0x3D5.
;
; Public interface:
;   pm_puts   ESI=string, BL=attr
;   pm_putc   AL=char,    BL=attr
;   pm_newline
;   pm_cls
; ===========================================================================

[BITS 32]
%define TERM_BG 0x00

; -
; pm_cls - clear screen, reset cursor to 0,0
; -
pm_cls:
    push eax
    push ecx
    push edi
    mov  edi, 0x000B8000
    mov  ecx, 80 * 25
    mov  eax, 0x07200720     ; two spaces, attr 0x07
    rep  stosd
    mov  dword [pm_cursor_x], 0
    mov  dword [pm_cursor_y], 0
    pop  edi
    pop  ecx
    pop  eax
    ret

; -
; pm_puts - print null-terminated string at ESI with attr BL
; -
pm_puts:
    push edx
    mov  dl, bl
    mov  dh, TERM_BG
    call term_puts_colour
    pop  edx
    ret

; -
; pm_putc - write char AL with attr BL at cursor, advance cursor
; -
pm_putc:
    call term_putchar    ; AL=char, uses term_col/term_row
    ret

; -
; pm_newline - advance to next line, scroll if at row 25
; Always resets X to 0 (CR+LF semantics).
; -
pm_newline:
    call term_newline
    ret
; -
; pm_update_cursor - sync hardware cursor to pm_cursor_x, pm_cursor_y
; -
pm_update_cursor:
    ret                  ; no-op, terminal has no hardware cursor

; serial_print " print ESI string to COM1 (shows in QEMU -serial stdio)
serial_print:
    push eax
    push edx
.loop:
    mov  al, [esi]
    test al, al
    jz   .done
    call serial_putchar
    inc  esi
    jmp  .loop
.done:
    pop  edx
    pop  eax
    ret

; serial_putchar - print AL to COM1
serial_putchar:
    push edx
    push eax
.wait:
    mov  dx, 0x3FD
    in   al, dx
    test al, 0x20
    jz   .wait
    mov  dx, 0x3F8
    pop  eax
    out  dx, al
    pop  edx
    ret

; serial_print_hex32 - print EAX as 8 hex digits to COM1
serial_print_hex32:
    pusha
    mov  ecx, 8
.loop:
    rol  eax, 4
    mov  ebx, eax
    and  ebx, 0x0F
    cmp  ebx, 10
    jl   .digit
    add  bl, 'A' - 10
    jmp  .out
.digit:
    add  bl, '0'
.out:
    push eax
    mov  al, bl
    call serial_putchar
    pop  eax
    loop .loop
    popa
    ret

