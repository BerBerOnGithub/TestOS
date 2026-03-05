; ===========================================================================
; core/string.asm - String and number printing/comparison utilities
; ===========================================================================

; ---------------------------------------------------------------------------
; print_uint - print 16-bit AX as unsigned decimal
; ---------------------------------------------------------------------------
print_uint:
    push ax
    push bx
    push cx
    push dx
    push si
    mov  cx, 0
    mov  bx, 10
    test ax, ax
    jnz  .div_loop
    mov  al, '0'
    mov  bl, ATTR_BRIGHT
    call putc_color
    jmp  .pu_done
.div_loop:
    xor  dx, dx
    div  bx
    push dx
    inc  cx
    test ax, ax
    jnz  .div_loop
.print_loop:
    pop  ax
    add  al, '0'
    mov  bl, ATTR_BRIGHT
    call putc_color
    loop .print_loop
.pu_done:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; print_int - print signed 16-bit AX as decimal
; ---------------------------------------------------------------------------
print_int:
    push ax
    push bx
    test ax, ax
    jns  .pi_pos
    push ax
    mov  al, '-'
    mov  bl, ATTR_BRIGHT
    call putc_color
    pop  ax
    neg  ax
.pi_pos:
    call print_uint
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; print_uint32  -  print 32-bit unsigned integer in DX:AX (decimal)
;
; Uses repeated division by 10 via two native 16-bit divides:
;   Step 1:  DX / 10  -> quotient_hi (AX), remainder_hi (DX)
;   Step 2:  DX:orig_AX / 10  -> quotient_lo (AX), final_remainder (DX)
;
; Because remainder_hi (0-9) fits easily in 16 bits, the combined dividend
; for step 2 is at most 9*65536 + 65535 = 655359, and quotient_lo is
; therefore at most 65535, safely within 16 bits -- so no #DE fault.
;
; Digits are pushed on the stack and then popped to print in order.
; ---------------------------------------------------------------------------
print_uint32:
    push ax
    push bx
    push cx
    push dx
    push si

    ; Quick path: if DX==0 the number fits in 16 bits, reuse print_uint
    test dx, dx
    jnz  .p32_full
    call print_uint
    jmp  .p32_done

.p32_full:
    mov  bx, 10
    xor  cx, cx              ; digit counter

.p32_div_loop:
    ; Is DX:AX == 0? (done when both are zero)
    test ax, ax
    jnz  .p32_do_div
    test dx, dx
    jz   .p32_print

.p32_do_div:
    ; Step 1: high word DX / 10 -> AX=quotient_hi, DX=remainder_hi
    push ax                  ; save low word
    mov  ax, dx
    xor  dx, dx
    div  bx                  ; AX = DX_old/10, DX = DX_old%10
    mov  si, ax              ; SI = quotient_hi
    ; DX = remainder_hi (0-9)

    ; Step 2: DX:orig_AX / 10 -> AX=quotient_lo, DX=final_digit
    pop  ax                  ; restore original low word
    div  bx                  ; DX:AX / 10; AX=quotient_lo, DX=digit

    push dx                  ; push digit onto stack
    inc  cx
    mov  dx, si              ; restore quotient_hi into DX (high of new value)
    ; AX already holds quotient_lo
    jmp  .p32_div_loop

.p32_print:
    jcxz .p32_done           ; if no digits pushed (input was 0, handled above)
.p32_print_loop:
    pop  ax
    add  al, '0'
    mov  bl, ATTR_BRIGHT
    call putc_color
    loop .p32_print_loop

.p32_done:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; print_uint_3 - print AX as 3-char decimal, space-padded on left
; ---------------------------------------------------------------------------
print_uint_3:
    push ax
    push bx
    push dx
    xor  dx, dx
    mov  bx, 10
    div  bx
    push dx                  ; save ones
    xor  dx, dx
    div  bx                  ; AX=hundreds, DX=tens
    cmp  ax, 0
    je   .u3_sp
    add  al, '0'
    mov  bl, ATTR_YELLOW
    call putc_color
    jmp  .u3_tens
.u3_sp:
    mov  al, ' '
    mov  bl, ATTR_NORMAL
    call putc_color
.u3_tens:
    mov  al, dl
    add  al, '0'
    mov  bl, ATTR_YELLOW
    call putc_color
    pop  ax
    add  al, '0'
    mov  bl, ATTR_YELLOW
    call putc_color
    pop  dx
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; print_bcd - print BCD byte AL as two decimal digits
; ---------------------------------------------------------------------------
print_bcd:
    push ax
    push bx
    push cx
    mov  cl, al
    shr  al, 4
    add  al, '0'
    mov  bl, ATTR_BRIGHT
    call putc_color
    mov  al, cl
    and  al, 0x0F
    add  al, '0'
    call putc_color
    pop  cx
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; print_hex_byte - print AL as two uppercase hex digits, color in BL
; ---------------------------------------------------------------------------
print_hex_byte:
    push ax
    push bx
    push cx
    mov  cl, al
    shr  al, 4
    call .phb_nib
    mov  al, cl
    and  al, 0x0F
    call .phb_nib
    pop  cx
    pop  bx
    pop  ax
    ret
.phb_nib:
    cmp  al, 10
    jl   .phb_dig
    add  al, 'A' - 10
    jmp  .phb_out
.phb_dig:
    add  al, '0'
.phb_out:
    call putc_color
    ret

; ---------------------------------------------------------------------------
; print_int32 - print signed 32-bit value in DX:AX as decimal
; Handles negatives by checking sign bit of DX, negating DX:AX, printing '-'
; then delegating to print_uint32
; ---------------------------------------------------------------------------
print_int32:
    push ax
    push bx
    push dx
    ; Check sign: if DX bit 15 set, number is negative
    test dx, dx
    jns  .p32_pos
    ; Negate DX:AX (two's complement: invert + 1)
    not  dx
    neg  ax
    jnz  .p32_no_carry
    inc  dx
.p32_no_carry:
    push ax
    push dx
    mov  al, '-'
    mov  bl, ATTR_BRIGHT
    call putc_color
    pop  dx
    pop  ax
.p32_pos:
    call print_uint32
    pop  dx
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; strcmp_buf - compare cmd_buf with string at SI; ZF=1 if equal
; ---------------------------------------------------------------------------
strcmp_buf:
    push ax
    push si
    push di
    lea  di, [cmd_buf]
.sb_lp:
    mov  al, [si]
    cmp  al, [di]
    jne  .sb_neq
    or   al, al
    jz   .sb_eq
    inc  si
    inc  di
    jmp  .sb_lp
.sb_eq:
    pop  di
    pop  si
    pop  ax
    xor  ax, ax
    ret
.sb_neq:
    pop  di
    pop  si
    pop  ax
    or   ax, 1
    ret

; ---------------------------------------------------------------------------
; startswith - ZF=1 if cmd_buf starts with string at SI
; ---------------------------------------------------------------------------
startswith:
    push ax
    push si
    push di
    lea  di, [cmd_buf]
.sw_lp:
    mov  al, [si]
    or   al, al
    jz   .sw_yes
    cmp  al, [di]
    jne  .sw_no
    inc  si
    inc  di
    jmp  .sw_lp
.sw_yes:
    pop  di
    pop  si
    pop  ax
    xor  ax, ax
    ret
.sw_no:
    pop  di
    pop  si
    pop  ax
    or   ax, 1
    ret