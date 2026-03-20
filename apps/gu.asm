; ===========================================================================
; apps/guess.asm - Number guessing game (1-100)
; ===========================================================================
[BITS 16]
[ORG 0x0000]

%include "sdk.asm"

    mov  ax, cs
    mov  ds, ax

    rand_byte                ; AL = random (AH = leftover syscall# 0x04)
    xor  ah, ah              ; AX = 0x00xx  " clear AH before division
    mov  cl, 100
    div  cl                  ; AL = quotient, AH = remainder (0-99)
    mov  al, ah              ; AL = remainder
    xor  ah, ah
    inc  ax                  ; AX = 1-100
    mov  [secret], ax
    mov  word [tries], 0

    print_str str_intro, CLR_CYAN

.loop:
    print_str str_prompt, CLR_YELLOW
    readline cmd_buf

    ; check quit inline
    mov  si, cmd_buf
    mov  di, str_quit
.cmp:
    mov  al, [si]
    mov  ah, [di]
    cmp  al, ah
    jne  .not_quit
    test al, al
    jz   .quit
    inc  si
    inc  di
    jmp  .cmp
.not_quit:

    ; parse number from cmd_buf
    mov  si, cmd_buf
    xor  ax, ax
.parse:
    mov  bl, [si]
    cmp  bl, '0'
    jb   .parsed
    cmp  bl, '9'
    ja   .parsed
    sub  bl, '0'
    mov  dx, 10
    mul  dx
    xor  bh, bh
    add  ax, bx
    inc  si
    jmp  .parse
.parsed:
    cmp  ax, 1
    jl   .invalid
    cmp  ax, 100
    jg   .invalid

    inc  word [tries]

    mov  bx, [secret]
    cmp  ax, bx
    je   .correct
    jb   .low

    print_str str_high, CLR_RED
    jmp  .loop
.low:
    print_str str_low, CLR_RED
    jmp  .loop

.correct:
    print_str str_correct, CLR_GREEN
    mov  ax, [tries]
    print_uint_ax
    print_str str_tries, CLR_GREEN
    newline
    newline
    retf

.invalid:
    print_str str_invalid, CLR_YELLOW
    jmp  .loop

.quit:
    print_str str_quit_msg, CLR_YELLOW
    mov  ax, [secret]
    print_uint_ax
    newline
    newline
    retf

secret:  dw 0
tries:   dw 0
cmd_buf: times 64 db 0

str_intro:    db 13, 10, ' Guess the Number! (1-100)', 13, 10
              db ' Type "quit" to give up.', 13, 10, 13, 10, 0
str_prompt:   db ' Your guess: ', 0
str_high:     db ' Too high!', 13, 10, 0
str_low:      db ' Too low!', 13, 10, 0
str_correct:  db 13, 10, ' Correct! Got it in ', 0
str_tries:    db ' tries!', 13, 10, 0
str_invalid:  db ' Enter 1-100.', 13, 10, 0
str_quit:     db 'quit', 0
str_quit_msg: db ' The number was: ', 0
