; ===========================================================================
; apps/calc.asm - Signed 16-bit calculator
; ===========================================================================
[BITS 16]
[ORG 0x0000]

%include "sdk.asm"

    mov  ax, cs
    mov  ds, ax

    print_str str_intro, CLR_CYAN

.loop:
    print_str str_prompt, CLR_YELLOW
    readline cmd_buf

    ; check quit
    mov  si, cmd_buf
    mov  di, str_quit
.cmp:
    mov  al, [si]
    mov  ah, [di]
    cmp  al, ah
    jne  .not_quit
    test al, al
    jz   .done
    inc  si
    inc  di
    jmp  .cmp
.not_quit:

    mov  si, cmd_buf
    call skip_sp
    call parse_int
    mov  [n1], ax
    call skip_sp
    mov  al, [si]
    mov  [op], al
    inc  si
    call skip_sp
    call parse_int
    mov  [n2], ax

    newline
    mov  ax, [n1]
    print_int_ax
    print_char ' ', CLR_NORMAL
    mov  al, [op]
    mov  bl, CLR_YELLOW
    mov  ah, SYS_PRINT_CHAR
    syscall
    print_char ' ', CLR_NORMAL
    mov  ax, [n2]
    print_int_ax
    print_str str_eq, CLR_YELLOW

    mov  ax, [n1]
    mov  bx, [n2]
    cmp  byte [op], '+'
    je   .add
    cmp  byte [op], '-'
    je   .sub
    cmp  byte [op], '*'
    je   .mul
    cmp  byte [op], '/'
    je   .div
    print_str str_badop, CLR_RED
    jmp  .nl

.add: add ax, bx
      jo  .overflow
      print_int_ax
      jmp .nl
.sub: sub ax, bx
      jo  .overflow
      print_int_ax
      jmp .nl
.mul: imul bx               ; DX:AX = full 32-bit signed result
      print_int32_dxax
      jmp .nl
.div: test bx, bx
      jz   .divzero
      cwd
      idiv bx
      print_int_ax
      test dx, dx
      jz   .nl
      print_str str_rem, CLR_NORMAL
      mov  ax, dx
      print_int_ax
      print_char ')', CLR_NORMAL
      jmp  .nl
.overflow: print_str str_ov, CLR_RED
           jmp .nl
.divzero:  print_str str_dz, CLR_RED
.nl:
    newline
    newline
    jmp  .loop
.done:
    retf

skip_sp:
    cmp  byte [si], ' '
    jne  .r
    inc  si
    jmp  skip_sp
.r: ret

parse_int:
    push bx
    xor  bx, bx
    cmp  byte [si], '-'
    jne  .pos
    mov  bx, 1
    inc  si
.pos:
    xor  ax, ax
    mov  cx, 10
.lp:
    mov  dl, [si]
    cmp  dl, '0'
    jb   .d
    cmp  dl, '9'
    ja   .d
    sub  dl, '0'        ; digit in DL
    push dx             ; save digit before mul trashes DX
    mul  cx             ; AX = AX * 10  (DX:AX, but DX=0 for small values)
    pop  dx             ; restore digit into DL
    xor  dh, dh
    add  ax, dx         ; AX = AX + digit
    inc  si
    jmp  .lp
.d: test bx, bx
    jz   .r2
    neg  ax
.r2:
    pop  bx
    ret

n1:  dw 0
n2:  dw 0
op:  db 0
cmd_buf: times 64 db 0

str_intro:  db 13, 10, ' Calc: "10 + 5", ops: + - * /  quit to exit', 13, 10, 0
str_prompt: db ' > ', 0
str_eq:     db ' = ', 0
str_rem:    db '  (rem: ', 0
str_ov:     db 'Overflow', 0
str_dz:     db 'Division by zero', 0
str_badop:  db 'Unknown operator', 0
str_quit:   db 'quit', 0
