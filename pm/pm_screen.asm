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

; ---------------------------------------------------------------------------
; pm_cls - clear screen, reset cursor to 0,0
; ---------------------------------------------------------------------------
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

; ---------------------------------------------------------------------------
; pm_puts - print null-terminated string at ESI with attr BL
; ---------------------------------------------------------------------------
pm_puts:
    push eax
    push esi
.loop:
    mov  al, [esi]
    or   al, al
    jz   .done
    cmp  al, 13
    je   .cr
    cmp  al, 10
    je   .lf
    call pm_putc
    inc  esi
    jmp  .loop
.cr:
    mov  dword [pm_cursor_x], 0
    inc  esi
    jmp  .loop
.lf:
    call pm_newline
    inc  esi
    jmp  .loop
.done:
    pop  esi
    pop  eax
    ret

; ---------------------------------------------------------------------------
; pm_putc - write char AL with attr BL at cursor, advance cursor
; ---------------------------------------------------------------------------
pm_putc:
    push eax
    push ecx

    ; VGA address: (y*80 + x) * 2 + 0xB8000
    mov  ecx, [pm_cursor_y]
    imul ecx, 80
    add  ecx, [pm_cursor_x]
    shl  ecx, 1
    add  ecx, 0x000B8000
    mov  ah, bl
    mov  [ecx], ax

    inc  dword [pm_cursor_x]
    cmp  dword [pm_cursor_x], 80
    jl   .hw
    mov  dword [pm_cursor_x], 0
    call pm_newline

.hw:
    call pm_update_cursor
    pop  ecx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; pm_newline - advance to next line, scroll if at row 25
; Always resets X to 0 (CR+LF semantics).
; ---------------------------------------------------------------------------
pm_newline:
    push eax
    push ecx
    push esi
    push edi

    mov  dword [pm_cursor_x], 0
    inc  dword [pm_cursor_y]
    cmp  dword [pm_cursor_y], 25
    jl   .done

    ; scroll rows 1-24 up to rows 0-23
    mov  edi, 0x000B8000
    mov  esi, 0x000B80A0     ; row 1
    mov  ecx, 80 * 24
    rep  movsw

    ; blank last row
    mov  edi, 0x000B8000 + (80 * 24 * 2)
    mov  ecx, 80
    mov  eax, 0x07200720
    rep  stosd

    mov  dword [pm_cursor_y], 24

.done:
    pop  edi
    pop  esi
    pop  ecx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; pm_update_cursor - sync hardware cursor to pm_cursor_x, pm_cursor_y
; ---------------------------------------------------------------------------
pm_update_cursor:
    push eax
    push ecx
    push edx
    mov  ecx, [pm_cursor_y]
    imul ecx, 80
    add  ecx, [pm_cursor_x]
    mov  dx, 0x3D4
    mov  al, 0x0F
    out  dx, al
    mov  dx, 0x3D5
    mov  al, cl
    out  dx, al
    mov  dx, 0x3D4
    mov  al, 0x0E
    out  dx, al
    mov  dx, 0x3D5
    shr  ecx, 8
    mov  al, cl
    out  dx, al
    pop  edx
    pop  ecx
    pop  eax
    ret