; ===========================================================================
; core/utils.asm - Miscellaneous parsing and utility routines
; ===========================================================================

; -
; skip_spaces - advance SI past space characters
; -
skip_spaces:
    push ax
.ss_lp:
    mov  al, [si]
    cmp  al, ' '
    jne  .ss_done
    inc  si
    jmp  .ss_lp
.ss_done:
    pop  ax
    ret

; -
; parse_uint16 - parse decimal digits at [SI] into AX; SI advances past them
; -
parse_uint16:
    push bx
    push cx
    xor  ax, ax
    mov  bx, 10
.p16_lp:
    mov  cl, [si]
    cmp  cl, '0'
    jb   .p16_done
    cmp  cl, '9'
    ja   .p16_done
    sub  cl, '0'
    push cx
    mul  bx
    pop  cx
    add  al, cl
    adc  ah, 0
    inc  si
    jmp  .p16_lp
.p16_done:
    pop  cx
    pop  bx
    ret

; -
; parse_int16 - parse optional '-' then digits at [SI] into AX (signed 16-bit)
;               SI advances past the number
; -
parse_int16:
    push bx
    xor  bx, bx              ; BX=0 means positive
    cmp  byte [si], '-'
    jne  .pi16_parse
    mov  bx, 1               ; BX=1 means negative
    inc  si
.pi16_parse:
    call parse_uint16        ; AX = absolute value
    test bx, bx
    jz   .pi16_done
    neg  ax                  ; apply sign
.pi16_done:
    pop  bx
    ret

; -
; parse_uint32  -  parse decimal string at [SI] into DX:AX (32-bit unsigned)
;                  SI is advanced past all consumed digit characters.
;                  Saves/restores BX, CX.
;
; Algorithm per digit:  DX:AX = DX:AX * 10 + digit
;
; Multiply DX:AX by 10:
;   native "mul bx" (bx=10) gives AX*10 -> DX_tmp:AX   (32-bit product)
;   new high word = old_DX * 10 + DX_tmp
;   This is valid as long as DX < 6554, i.e. the value fits in ~32 bits,
;   which is guaranteed for any 10-digit decimal input <= 4,294,967,295.
; -
parse_uint32:
    push bx
    push cx
    xor  ax, ax
    xor  dx, dx
    mov  bx, 10

.p32_lp:
    mov  cl, [si]
    cmp  cl, '0'
    jb   .p32_done
    cmp  cl, '9'
    ja   .p32_done
    sub  cl, '0'             ; digit in CL

    ; - multiply DX:AX by 10 -
    push cx                  ; save digit
    push dx                  ; save old high word

    mul  bx                  ; AX * 10 -> DX:AX  (DX = carry from lo word)
    mov  cx, dx              ; CX = carry

    pop  dx                  ; restore old high word
    push ax                  ; save new low word
    mov  ax, dx
    mul  bx                  ; old_DX * 10 -> DX:AX  (DX will be 0 for valid inputs)
    add  ax, cx              ; add carry from low multiply
    mov  dx, ax              ; DX = new high word
    pop  ax                  ; AX = new low word

    ; - add digit -
    pop  cx
    xor  ch, ch
    add  ax, cx
    adc  dx, 0

    inc  si
    jmp  .p32_lp

.p32_done:
    pop  cx
    pop  bx
    ret

; -
; parse_hex_digit  -  parse one hex char at [SI]; nibble->AL, CF=1 on error
;                     SI is NOT advanced
; -
parse_hex_digit:
    push si
    mov  al, [si]
    cmp  al, 'a'
    jb   .phd_nolc
    cmp  al, 'f'
    ja   .phd_nolc
    sub  al, 32              ; to upper
.phd_nolc:
    cmp  al, '0'
    jb   .phd_inv
    cmp  al, '9'
    ja   .phd_alpha
    sub  al, '0'
    clc
    pop  si
    ret
.phd_alpha:
    cmp  al, 'A'
    jb   .phd_inv
    cmp  al, 'F'
    ja   .phd_inv
    sub  al, 'A' - 10
    clc
    pop  si
    ret
.phd_inv:
    stc
    pop  si
    ret

; -
; get_rand_byte  -  pseudo-random byte in AL via BIOS timer low byte
; -
get_rand_byte:
    push cx
    push dx
    xor  ah, ah
    int  0x1A
    mov  al, dl
    pop  dx
    pop  cx
    ret

; -
; divmod32  -  exact 32-bit unsigned division via binary long division
;
;   In:   DX:AX = dividend,  BX:CX = divisor
;   Out:  DX:AX = quotient,  BX:CX = remainder
;   CF=1 if divisor was zero (all outputs undefined).
;
; Uses 32 memory locations for scratch to avoid register pressure.
; 32 iterations of shift-and-subtract, ~1000 cycles total - imperceptible.
; -
divmod32:
    ; zero divisor check
    test bx, bx
    jnz  .dv_start
    test cx, cx
    jz   .dv_zero

.dv_start:
    ; stash everything into scratchpad
    mov  [dv_dvd_lo], ax
    mov  [dv_dvd_hi], dx
    mov  [dv_dvs_lo], cx
    mov  [dv_dvs_hi], bx

    ; remainder = 0, quotient = 0
    mov  word [dv_rem_lo], 0
    mov  word [dv_rem_hi], 0
    mov  word [dv_quo_lo], 0
    mov  word [dv_quo_hi], 0

    mov  cx, 32              ; 32 bit-iterations

.dv_loop:
    ; 1. Shift quotient left 1 (make room for the new bit)
    shl  word [dv_quo_lo], 1
    rcl  word [dv_quo_hi], 1

    ; 2. Shift dividend left 1; the evicted MSB goes to CF
    shl  word [dv_dvd_lo], 1
    rcl  word [dv_dvd_hi], 1   ; MSB of dvd_hi now in CF

    ; 3. Shift remainder left 1, inserting that MSB (from CF)
    rcl  word [dv_rem_lo], 1
    rcl  word [dv_rem_hi], 1

    ; 4. If remainder >= divisor, subtract and set quotient bit
    mov  ax, [dv_rem_hi]
    cmp  ax, [dv_dvs_hi]
    ja   .dv_sub             ; rem_hi > dvs_hi
    jb   .dv_no_sub          ; rem_hi < dvs_hi
    ; rem_hi == dvs_hi; compare lo words
    mov  ax, [dv_rem_lo]
    cmp  ax, [dv_dvs_lo]
    jb   .dv_no_sub

.dv_sub:
    mov  ax, [dv_rem_lo]
    sub  ax, [dv_dvs_lo]
    mov  [dv_rem_lo], ax
    mov  ax, [dv_rem_hi]
    sbb  ax, [dv_dvs_hi]
    mov  [dv_rem_hi], ax
    or   word [dv_quo_lo], 1  ; set LSB of quotient

.dv_no_sub:
    loop .dv_loop

    ; Return quotient in DX:AX, remainder in BX:CX
    mov  ax, [dv_quo_lo]
    mov  dx, [dv_quo_hi]
    mov  cx, [dv_rem_lo]
    mov  bx, [dv_rem_hi]
    clc
    ret

.dv_zero:
    stc
    ret

; Scratchpad for divmod32 (all in BSS-style data in the kernel segment)
dv_dvd_lo: dw 0
dv_dvd_hi: dw 0
dv_dvs_lo: dw 0
dv_dvs_hi: dw 0
dv_rem_lo: dw 0
dv_rem_hi: dw 0
dv_quo_lo: dw 0
dv_quo_hi: dw 0
