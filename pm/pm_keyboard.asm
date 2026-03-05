; ===========================================================================
; pm/pm_keyboard.asm - 32-bit PS/2 keyboard driver
;
; No BIOS. Polls port 0x64 (status) and reads port 0x60 (data).
; Translates scan codes to ASCII via pm_scancode_table.
; Handles two shift keys for uppercase/symbols.
;
; Public interface:
;   pm_getkey   → AL = ASCII (0 = ignore/non-printable)
;   pm_readline → reads line into pm_input_buf, sets pm_input_len
; ===========================================================================

[BITS 32]

; ---------------------------------------------------------------------------
; pm_getkey - wait for key press, return ASCII in AL (0 = unhandled)
; Handles shift for uppercase. Ignores key releases.
; ---------------------------------------------------------------------------
pm_getkey:
    push ebx
.wait:
    in   al, 0x64
    test al, 1               ; output buffer full?
    jz   .wait
    in   al, 0x60            ; read scan code

    ; track shift state (scan 0x2A = left shift, 0x36 = right shift)
    cmp  al, 0x2A
    je   .shift_on
    cmp  al, 0x36
    je   .shift_on
    cmp  al, 0xAA            ; left shift release
    je   .shift_off
    cmp  al, 0xB6            ; right shift release
    je   .shift_off

    test al, 0x80            ; any other release? ignore
    jnz  .ignore

    ; look up in appropriate table
    movzx ebx, al
    cmp  ebx, 58
    jae  .ignore

    cmp  byte [pm_shift], 0
    jne  .shifted
    mov  al, [pm_scancode_table + ebx]
    jmp  .done
.shifted:
    mov  al, [pm_scancode_shift + ebx]

.done:
    pop  ebx
    ret

.shift_on:
    mov  byte [pm_shift], 1
    jmp  .wait
.shift_off:
    mov  byte [pm_shift], 0
    jmp  .wait
.ignore:
    xor  al, al
    pop  ebx
    ret

; ---------------------------------------------------------------------------
; pm_readline - read line from keyboard into pm_input_buf
; Result: pm_input_buf = null-terminated string, pm_input_len = length
; ---------------------------------------------------------------------------
pm_readline:
    push eax
    push edi

    mov  edi, pm_input_buf
    mov  dword [pm_input_len], 0

.loop:
    call pm_getkey
    or   al, al
    jz   .loop

    cmp  al, 13              ; Enter
    je   .enter
    cmp  al, 8               ; Backspace
    je   .bs

    cmp  dword [pm_input_len], 127
    jge  .loop

    mov  [edi], al
    inc  edi
    inc  dword [pm_input_len]
    mov  bl, 0x0F
    call pm_putc
    jmp  .loop

.bs:
    cmp  dword [pm_input_len], 0
    je   .loop
    dec  edi
    mov  byte [edi], 0
    dec  dword [pm_input_len]
    dec  dword [pm_cursor_x]
    push eax
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    dec  dword [pm_cursor_x]
    call pm_update_cursor
    pop  eax
    jmp  .loop

.enter:
    mov  byte [edi], 0
    call pm_newline
    call pm_update_cursor
    pop  edi
    pop  eax
    ret
