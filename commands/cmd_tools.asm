; ===========================================================================
; commands/cmd_tools.asm - Utility commands
;   calc  (signed 16-bit: -32768 to 32767)
;   color
;   beep
; ===========================================================================

; ---------------------------------------------------------------------------
; calc <num> <op> <num>  — signed 16-bit arithmetic
;
; Operands  : -32768 .. 32767  (parsed with parse_int16)
; Operations: +  -  *  /
; Results   : printed signed
;
; Overflow detection:
;   Add/Sub : native add/sub + jo (overflow flag)
;   Mul     : imul → DX:AX; overflow if DX != sign-extension of AX
;   Div     : cwd + idiv; overflow if quotient out of 16-bit signed range
; ---------------------------------------------------------------------------
cmd_calc:
    push ax
    push bx
    push cx
    push dx
    push si

    lea  si, [cmd_buf + 5]       ; skip "calc "
    call skip_spaces
    mov  al, [si]
    or   al, al
    jz   .calc_usage

    ; ── Parse operand 1 (signed) ─────────────────────────────────────────
    call parse_int16
    mov  [calc_n1_lo], ax

    call skip_spaces
    mov  al, [si]
    or   al, al
    jz   .calc_usage
    mov  [calc_op], al
    inc  si

    call skip_spaces

    ; ── Parse operand 2 (signed) ─────────────────────────────────────────
    call parse_int16
    mov  [calc_n2_lo], ax

    ; ── Echo the expression ──────────────────────────────────────────────
    call nl
    mov  ax, [calc_n1_lo]
    call print_int
    mov  al, ' '
    mov  bl, ATTR_NORMAL
    call putc_color
    mov  al, [calc_op]
    mov  bl, ATTR_YELLOW
    call putc_color
    mov  al, ' '
    mov  bl, ATTR_NORMAL
    call putc_color
    mov  ax, [calc_n2_lo]
    call print_int
    mov  si, str_eq
    mov  bl, ATTR_YELLOW
    call puts_c

    ; ── Dispatch ─────────────────────────────────────────────────────────
    mov  ax, [calc_n1_lo]
    mov  bx, [calc_n2_lo]

    cmp  byte [calc_op], '+'
    je   .c_add
    cmp  byte [calc_op], '-'
    je   .c_sub
    cmp  byte [calc_op], '*'
    je   .c_mul
    cmp  byte [calc_op], '/'
    je   .c_div
    jmp  .calc_badop

; ── Addition ─────────────────────────────────────────────────────────────
.c_add:
    add  ax, bx
    jo   .calc_overflow
    call print_int
    jmp  .calc_nl

; ── Subtraction ──────────────────────────────────────────────────────────
.c_sub:
    sub  ax, bx
    jo   .calc_overflow
    call print_int
    jmp  .calc_nl

; ── Multiplication ───────────────────────────────────────────────────────
; imul BX → signed 32-bit result in DX:AX
; We print the full 32-bit signed result, so 500*500=250000 works fine.
; Only overflow if the result doesn't fit in 32 bits — impossible with two
; 16-bit inputs (max: -32768 * -32768 = 1,073,741,824 which fits in 32 bits)
; so multiplication never overflows here.
.c_mul:
    imul bx                  ; DX:AX = AX * BX  (signed 32-bit result)
    call print_int32         ; print signed 32-bit DX:AX
    jmp  .calc_nl

; ── Division ─────────────────────────────────────────────────────────────
; cwd sign-extends AX into DX:AX, idiv divides by BX
; Quotient in AX, remainder in DX
.c_div:
    test bx, bx
    jz   .calc_divzero
    cwd
    idiv bx
    jo   .calc_overflow
    call print_int
    test dx, dx
    jz   .calc_nl
    push ax
    mov  si, str_rem
    mov  bl, ATTR_CYAN
    call puts_c
    mov  ax, dx
    call print_int
    mov  al, ')'
    mov  bl, ATTR_CYAN
    call putc_color
    pop  ax
    jmp  .calc_nl

; ── Error paths ───────────────────────────────────────────────────────────
.calc_overflow:
    mov  si, str_overflow
    mov  bl, ATTR_RED
    call puts_c
    jmp  .calc_end

.calc_divzero:
    mov  si, str_divzero
    mov  bl, ATTR_RED
    call puts_c
    jmp  .calc_end

.calc_badop:
    mov  si, str_badop
    mov  bl, ATTR_RED
    call puts_c
    jmp  .calc_end

.calc_usage:
    mov  si, str_calc_usage
    mov  bl, ATTR_YELLOW
    call puts_c
    jmp  .calc_end

.calc_nl:
    call nl
.calc_end:
    call nl
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    jmp  shell_exec.done

; ---------------------------------------------------------------------------
; color [XX] - no arg: show palette. With arg: set shell color + repaint bg.
; If high nibble (bg) == low nibble (fg), warn and confirm before applying.
; ---------------------------------------------------------------------------
cmd_color:
    push ax
    push bx
    push cx
    push dx
    push si
    lea  si, [cmd_buf + 6]   ; skip "color "
    mov  al, [cmd_buf + 5]   ; byte after "color" — space or null
    or   al, al
    jz   .show_palette
    mov  al, [si]
    or   al, al
    jz   .show_palette

    ; ── Parse two hex digits into BL ──────────────────────────────────────
    call parse_hex_digit
    jc   .color_usage
    mov  bl, al
    shl  bl, 4               ; BL = bg nibble in high
    inc  si
    call parse_hex_digit
    jc   .color_usage
    or   bl, al              ; BL = full attribute byte

    ; ── Check bg == fg (text would merge into background) ─────────────────
    mov  al, bl
    shr  al, 4               ; AL = background nibble
    and  al, 0x07            ; mask blink bit for comparison
    mov  ah, bl
    and  ah, 0x0F            ; AH = foreground nibble
    cmp  al, ah
    jne  .apply              ; different — safe, skip warning

    ; ── Warn: fg == bg ────────────────────────────────────────────────────
    call nl
    mov  si, str_color_merge_warn
    mov  bl, ATTR_RED
    call puts_c
    mov  si, str_color_merge_prompt
    mov  bl, ATTR_YELLOW
    call puts_c

    xor  ah, ah
    int  0x16                ; wait for keypress → AL = ASCII
    mov  cl, al              ; save answer (BL about to be reloaded)

    ; re-parse the attribute (BL was clobbered by puts_c)
    lea  si, [cmd_buf + 6]
    call parse_hex_digit
    mov  bl, al
    shl  bl, 4
    inc  si
    call parse_hex_digit
    or   bl, al

    ; echo the key the user pressed
    mov  al, cl
    call putc_color
    call nl

    cmp  cl, 'y'
    je   .apply
    cmp  cl, 'Y'
    je   .apply

    ; aborted
    call nl
    mov  si, str_color_merge_abort
    mov  bl, ATTR_GREEN
    call puts_c
    call nl
    jmp  .color_end

    ; ── Apply: save attr, repaint entire screen background ────────────────
.apply:
    mov  [shell_attr], bl

    ; INT 10h AH=06h: scroll window (AL=0 → clear entire window)
    ; BH = fill attribute, CX = top-left (0,0), DX = bottom-right (24,79)
    mov  ah, 0x06
    xor  al, al              ; clear entire region
    mov  bh, [shell_attr]    ; fill with new attribute
    xor  cx, cx              ; row 0, col 0
    mov  dx, 0x184F          ; row 24, col 79
    int  0x10

    ; home the cursor
    mov  ah, 0x02
    xor  bh, bh
    xor  dx, dx
    int  0x10

    call nl
    mov  si, str_color_ok
    mov  bl, [shell_attr]
    call puts_c
    call nl
    call nl
    jmp  .color_end

.show_palette:
    push cx
    call nl
    mov  si, str_colors_hdr
    mov  bl, ATTR_BRIGHT
    call puts_c
    call nl
    xor  cx, cx
.cp_lp:
    cmp  cx, 16
    jge  .cp_done
    mov  bl, ATTR_NORMAL
    mov  al, ' '
    call putc_color
    call putc_color
    mov  al, '0'
    call putc_color
    mov  al, 'x'
    call putc_color
    mov  al, '0'
    call putc_color
    mov  al, cl
    cmp  al, 10
    jl   .cp_dig
    add  al, 'A' - 10
    jmp  .cp_hex
.cp_dig:
    add  al, '0'
.cp_hex:
    call putc_color
    mov  al, ' '
    call putc_color
    call putc_color
    mov  bl, cl
    mov  si, str_clr_sample
    call puts_c
    call nl
    inc  cx
    jmp  .cp_lp
.cp_done:
    call nl
    pop  cx
    jmp  .color_end

.color_usage:
    mov  si, str_color_usage
    mov  bl, ATTR_YELLOW
    call puts_c
    call nl
.color_end:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    jmp  shell_exec.done

; ---------------------------------------------------------------------------
; beep - sound PC speaker at ~1000 Hz for ~300 ms
; ---------------------------------------------------------------------------
cmd_beep:
    push ax
    push bx
    push cx
    push si

    ; Set PIT channel 2: divisor 1193 ≈ 1000 Hz
    mov  al, 0xB6
    out  0x43, al
    mov  al, 0xA9           ; low byte of 1193
    out  0x42, al
    mov  al, 0x04           ; high byte
    out  0x42, al

    ; Enable speaker via port 0x61 bits 0+1
    in   al, 0x61
    or   al, 0x03
    out  0x61, al

    ; Delay ~300 ms via INT 15h AH=86h (CX:DX = microseconds)
    mov  ah, 0x86
    mov  cx, 0x0004
    mov  dx, 0x93E0
    int  0x15
    jnc  .beep_done
    ; Fallback busy-wait if INT 15h unavailable
    xor  ax, ax
.bfb1:
    mov  cx, 0
.bfb2:
    loop .bfb2
    dec  ax
    jnz  .bfb1

.beep_done:
    in   al, 0x61
    and  al, 0xFC
    out  0x61, al

    mov  si, str_beeped
    mov  bl, ATTR_GREEN
    call puts_c
    call nl

    pop  si
    pop  cx
    pop  bx
    pop  ax
    jmp  shell_exec.done