; ===========================================================================
; apps/fortune.asm - Random fortune cookie
; ===========================================================================
[BITS 16]
[ORG 0x0000]

%include "sdk.asm"

    mov  ax, cs
    mov  ds, ax

    rand_byte                ; AL = random (AH = leftover syscall# 0x04)
    xor  ah, ah              ; clear AH before division
    mov  cl, 10
    div  cl                  ; AH = AX % 10
    mov  al, ah              ; AL = index 0-9
    xor  ah, ah
    shl  ax, 1               ; AX = index * 2 (word table)
    mov  bx, ax
    mov  si, [fortune_table + bx]

    newline
    push si              ; save fortune string offset
    print_str str_open, CLR_YELLOW
    pop si               ; restore fortune string offset
    mov  bl, CLR_BRIGHT
    mov  ah, SYS_PRINT_STR
    syscall
    print_str str_close, CLR_YELLOW
    newline
    newline
    retf

str_open:  db ' "', 0
str_close: db '"', 0

fortune_table:
    dw fort0, fort1, fort2, fort3, fort4
    dw fort5, fort6, fort7, fort8, fort9

fort0: db 'The best way to predict the future is to invent it.', 13, 10
       db '   - Alan Kay', 0
fort1: db 'Any sufficiently advanced technology is indistinguishable from magic.', 13, 10
       db '   - Arthur C. Clarke', 0
fort2: db 'First, solve the problem. Then, write the code.', 13, 10
       db '   - John Johnson', 0
fort3: db 'Programs must be written for people to read, and only incidentally', 13, 10
       db '   for machines to execute.  - Abelson & Sussman', 0
fort4: db 'It is not enough to do your best; you must know what to do,', 13, 10
       db '   and then do your best.  - W. Edwards Deming', 0
fort5: db 'The only way to go fast is to go well.', 13, 10
       db '   - Robert C. Martin', 0
fort6: db 'Simplicity is the soul of efficiency.', 13, 10
       db '   - Austin Freeman', 0
fort7: db 'Good code is its own best documentation.', 13, 10
       db '   - Steve McConnell', 0
fort8: db 'In theory there is no difference between theory and practice.', 13, 10
       db '   In practice there is.  - Jan L.A. van de Snepscheut', 0
fort9: db 'The computer was born to solve problems that did not exist before.', 13, 10
       db '   - Bill Gates', 0
