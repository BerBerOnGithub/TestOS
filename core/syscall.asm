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
;   AH=0x0B  uptime       -> CX:DX = 32-bit ticks since boot
;   AH=0x0C  delay        DX = ticks to wait
;   AH=0x0D  beep         BX = freq (Hz), CX = duration (ticks)
;   AH=0x0E  fexists      DS:SI = filename -> AL=1 if found
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
    cmp  ah, 0x0B
    je   .uptime
    cmp  ah, 0x0C
    je   .delay
    cmp  ah, 0x0D
    je   .beep
    cmp  ah, 0x0E
    je   .fexists
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

.uptime:
    xor  ah, ah
    int  0x1A                ; Get current ticks in CX:DX
    sub  dx, [boot_ticks_lo]
    sbb  cx, [boot_ticks_hi]
    mov  [sc_cx], cx         ; High word
    mov  [sc_dx], dx         ; Low word
    jmp  .done

.delay:
    mov  cx, [sc_dx]         ; ticks to wait
    xor  ah, ah
    int  0x1A
    add  dx, cx              ; target = current + duration
    ; Simple blocking wait (16-bit safe)
.delay_lp:
    push dx
    xor  ah, ah
    int  0x1A
    pop  bx                  ; BX = target
    cmp  dx, bx
    jb   .delay_lp           ; wait until current DX >= target
    jmp  .done

.beep:
    mov  bx, [sc_bx]         ; Frequency in Hz
    cmp  bx, 20
    jb   .done               ; Safety check
    mov  ax, 0x34DD          ; Divisor low (1193180)
    mov  dx, 0x0012          ; Divisor high
    div  bx                  ; AX = divisor
    mov  bx, ax              ; BX = divisor

    ; Set PIT Channel 2
    mov  al, 0xB6
    out  0x43, al
    mov  al, bl
    out  0x42, al
    mov  al, bh
    out  0x42, al

    ; Speaker ON
    in   al, 0x61
    or   al, 0x03
    out  0x61, al

    ; Wait for duration (CX ticks)
    xor  ah, ah
    int  0x1A
    mov  di, dx              ; di = start ticks (low)
    mov  cx, [sc_cx]         ; cx = duration
.beep_lp:
    xor  ah, ah
    int  0x1A
    mov  ax, dx
    sub  ax, di              ; ax = current - start
    cmp  ax, cx
    jb   .beep_lp

    ; Speaker OFF
    in   al, 0x61
    and  al, 0xFC
    out  0x61, al
    jmp  .done

.fexists:
    ; Search filesystem for name at [sc_ds:sc_si]
    mov  ax, [ss:sc_ds]      ; Use SS: to be safe
    mov  gs, ax              ; GS = app's segment
    mov  si, [ss:sc_si]      ; SI = app's offset
    
    mov  ax, 0x2000          ; FS_SEG
    mov  es, ax
    mov  cx, [es:4]          ; File count
    test cx, cx
    jz   .fe_none
    mov  di, 6               ; DIR_OFFSET

.fe_lp:
    push cx
    push di
    push si                  ; save start of app name

    mov  cx, 16              ; MAX_NAME_LEN
.fe_cmp:
    mov  al, [gs:si]         ; Read from app segment via GS
    mov  ah, [es:di]         ; Read from FS (ES=0x2000)
    
    cmp  al, ah
    jne  .fe_mismatch
    
    test al, al              ; hit null terminator in both?
    jz   .fe_found           ; match!
    
    inc  si
    inc  di
    loop .fe_cmp

.fe_found:
    pop  si
    pop  di
    pop  cx
    mov  byte [ss:sc_ax], 1  ; Found!
    jmp  .done

.fe_mismatch:
    pop  si
    pop  di
    pop  cx
    add  di, 24              ; ENTRY_SIZE
    loop .fe_lp

.fe_none:
    mov  byte [ss:sc_ax], 0  ; Not found
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
