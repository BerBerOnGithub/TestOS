; ===========================================================================
; core/syscall.asm - NatureOS syscall handler
;
; Entry point is at fixed address 0x0000:0x8100 (trampoline in kernel.asm).
; Apps call it via far call " no IVT, no interrupt, no BIOS conflicts.
;
;   AH=0x00  print_str    DS:SI = string, BL = color
;   AH=0x01  print_char   AL = char, BL = color
;   AH=0x02  print_uint   CX = uint16
;   AH=0x03  newline
;   AH=0x04  rand         -> AL = random byte
;   AH=0x05  readline     DI = buffer offset in app's DS
;   AH=0x06  clear
;   AH=0x07  print_int    CX = signed int16
;   AH=0x09  print_int32  CX = high word, DX = low word
;   AH=0x0A  getkey       -> AL = ASCII key
; ===========================================================================

syscall_handler:
    ; Save regs using SS: override (SS=0 always, safe regardless of app DS)
    mov  [ss:sc_ax], ax
    mov  [ss:sc_bx], bx
    mov  [ss:sc_cx], cx
    mov  [ss:sc_dx], dx
    mov  [ss:sc_si], si
    mov  [ss:sc_di], di
    mov  [ss:sc_bp], bp
    mov  ax, ds
    mov  [ss:sc_ds], ax
    mov  ax, es
    mov  [ss:sc_es], ax

    xor  ax, ax
    mov  ds, ax
    mov  es, ax

    mov  ax, [sc_ax]
    mov  si, [sc_si]
    mov  bl, [sc_bx]

    cmp  ah, 0x00
    je   .print_str
    cmp  ah, 0x01
    je   .print_char
    cmp  ah, 0x02
    je   .print_uint
    cmp  ah, 0x03
    je   .newline
    cmp  ah, 0x04
    je   .rand
    cmp  ah, 0x05
    je   .readline
    cmp  ah, 0x06
    je   .clear
    cmp  ah, 0x07
    je   .print_int
    cmp  ah, 0x09
    je   .print_int32
    cmp  ah, 0x0A
    je   .getkey
    jmp  .done

.print_str:
    mov  ds, [sc_ds]
    call puts_c
    xor  ax, ax
    mov  ds, ax
    jmp  .done

.print_char:
    call putc_color
    jmp  .done

.print_uint:
    mov  ax, [sc_cx]
    call print_uint
    jmp  .done

.newline:
    call nl
    jmp  .done

.rand:
    call get_rand_byte
    mov  [sc_ax], al
    jmp  .done

.readline:
    mov  di, [sc_di]
    sti
    xor  cx, cx
.rl_lp:
    xor  ah, ah
    int  0x16
    cmp  al, 13
    je   .rl_cr
    cmp  al, 8
    je   .rl_bk
    or   al, al
    jz   .rl_lp
    cmp  cx, 63
    jge  .rl_lp
    push ax
    mov  ax, [sc_ds]
    mov  ds, ax
    pop  ax
    mov  [di], al
    push ax
    xor  ax, ax
    mov  ds, ax
    pop  ax
    inc  di
    inc  cx
    mov  bl, 0x07
    call putc_color
    jmp  .rl_lp
.rl_bk:
    or   cx, cx
    jz   .rl_lp
    dec  di
    dec  cx
    push ax
    mov  ax, [sc_ds]
    mov  ds, ax
    mov  byte [di], 0
    xor  ax, ax
    mov  ds, ax
    pop  ax
    mov  al, 8
    mov  bl, 0x07
    call putc_color
    mov  al, ' '
    call putc_color
    mov  al, 8
    call putc_color
    jmp  .rl_lp
.rl_cr:
    push ax
    mov  ax, [sc_ds]
    mov  ds, ax
    mov  byte [di], 0
    xor  ax, ax
    mov  ds, ax
    pop  ax
    call nl
    jmp  .done

.clear:
    call screen_clear
    jmp  .done

.print_int:
    mov  ax, [sc_cx]
    call print_int
    jmp  .done

.print_int32:
    mov  dx, [sc_cx]
    mov  ax, [sc_dx]
    call print_int32
    jmp  .done

.getkey:
    xor  ah, ah
    int  0x16
    mov  [sc_ax], al
    jmp  .done

.done:
    mov  ax, [sc_ax]
    mov  bx, [sc_bx]
    mov  cx, [sc_cx]
    mov  dx, [sc_dx]
    mov  si, [sc_si]
    mov  di, [sc_di]
    mov  bp, [sc_bp]
    mov  es, [sc_es]
    mov  ds, [sc_ds]
    retf                     ; far return to app (far call from app)

sc_ax: dw 0
sc_bx: dw 0
sc_cx: dw 0
sc_dx: dw 0
sc_si: dw 0
sc_di: dw 0
sc_bp: dw 0
sc_ds: dw 0
sc_es: dw 0
