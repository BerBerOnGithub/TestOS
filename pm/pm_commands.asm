; ===========================================================================
; pm/pm_commands.asm - 32-bit PM shell command implementations
;   help, ver, clear, echo, calc
;
; Mirrors commands/ structure for the PM environment.
; Calls pm_screen, pm_string helpers. No BIOS.
; ===========================================================================

[BITS 32]

; ---------------------------------------------------------------------------
; pm_cmd_help
; ---------------------------------------------------------------------------
pm_cmd_help:
    push esi
    push ebx
    mov  esi, pm_str_help_text
    mov  bl, 0x0B            ; cyan
    call pm_puts
    pop  ebx
    pop  esi
    ret

; ---------------------------------------------------------------------------
; pm_cmd_ver
; ---------------------------------------------------------------------------
pm_cmd_ver:
    push esi
    push ebx
    mov  esi, pm_str_ver_text
    mov  bl, 0x0B
    call pm_puts
    pop  ebx
    pop  esi
    ret

; ---------------------------------------------------------------------------
; pm_cmd_clear
; ---------------------------------------------------------------------------
pm_cmd_clear:
    call pm_cls
    ret

; ---------------------------------------------------------------------------
; pm_cmd_echo  -  print everything after "echo "
; ---------------------------------------------------------------------------
pm_cmd_echo:
    push esi
    push ebx
    mov  esi, pm_input_buf
    add  esi, 5              ; skip "echo "
    mov  bl, 0x0F
    call pm_puts
    call pm_newline
    pop  ebx
    pop  esi
    ret

; ---------------------------------------------------------------------------
; pm_cmd_calc  -  calc <num> <op> <num>
; Signed 32-bit integers. Operators: + - * /
; Multiplication result capped at 32 bits (overflow flagged).
; ---------------------------------------------------------------------------
pm_cmd_calc:
    push eax
    push ebx
    push ecx
    push edx
    push esi

    mov  esi, pm_input_buf
    add  esi, 5              ; skip "calc "
    call pm_skip_spaces
    mov  al, [esi]
    or   al, al
    jz   .usage

    ; parse operand 1
    call pm_parse_int
    mov  [pm_calc_n1], eax

    call pm_skip_spaces
    mov  al, [esi]
    or   al, al
    jz   .usage
    mov  [pm_calc_op], al
    inc  esi

    call pm_skip_spaces

    ; parse operand 2
    call pm_parse_int
    mov  [pm_calc_n2], eax

    ; echo expression
    call pm_newline
    mov  eax, [pm_calc_n1]
    call pm_print_int
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    mov  al, [pm_calc_op]
    mov  bl, 0x0E
    call pm_putc
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    mov  eax, [pm_calc_n2]
    call pm_print_int
    mov  esi, pm_str_eq
    mov  bl, 0x0E
    call pm_puts

    ; dispatch
    cmp  byte [pm_calc_op], '+'
    je   .add
    cmp  byte [pm_calc_op], '-'
    je   .sub
    cmp  byte [pm_calc_op], '*'
    je   .mul
    cmp  byte [pm_calc_op], '/'
    je   .div
    jmp  .badop

.add:
    mov  eax, [pm_calc_n1]
    mov  ebx, [pm_calc_n2]
    add  eax, ebx
    jo   .overflow
    call pm_print_int
    jmp  .nl

.sub:
    mov  eax, [pm_calc_n1]
    mov  ebx, [pm_calc_n2]
    sub  eax, ebx
    jo   .overflow
    call pm_print_int
    jmp  .nl

.mul:
    ; 32x32 signed: use imul which gives 64-bit in EDX:EAX
    mov  eax, [pm_calc_n1]
    mov  ebx, [pm_calc_n2]
    imul ebx                 ; EDX:EAX = result
    ; overflow if EDX != sign-extension of EAX
    mov  ecx, eax
    sar  ecx, 31             ; ECX = all sign bits of EAX
    cmp  edx, ecx
    jne  .overflow
    call pm_print_int
    jmp  .nl

.div:
    mov  ebx, [pm_calc_n2]
    test ebx, ebx
    jz   .divzero
    mov  eax, [pm_calc_n1]
    cdq                      ; sign-extend EAX into EDX:EAX
    idiv ebx                 ; EAX=quotient, EDX=remainder
    call pm_print_int
    ; show remainder if nonzero
    test edx, edx
    jz   .nl
    push eax
    push edx
    mov  esi, pm_str_rem
    mov  bl, 0x0B
    call pm_puts
    pop  eax                 ; remainder was in EDX
    call pm_print_int
    mov  al, ')'
    mov  bl, 0x0B
    call pm_putc
    pop  eax
    jmp  .nl

.overflow:
    mov  esi, pm_str_overflow
    mov  bl, 0x0C
    call pm_puts
    jmp  .end

.divzero:
    mov  esi, pm_str_divzero
    mov  bl, 0x0C
    call pm_puts
    jmp  .end

.badop:
    mov  esi, pm_str_badop
    mov  bl, 0x0C
    call pm_puts
    jmp  .end

.usage:
    mov  esi, pm_str_calc_usage
    mov  bl, 0x0E
    call pm_puts
    jmp  .end

.nl:
    call pm_newline
.end:
    call pm_newline
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; pm_cmd_exit - switch back to 16-bit real mode
;
; Sequence (per OSDev wiki / tutorial):
;   1. Print message
;   2. Disable interrupts
;   3. Far jump to 16-bit PM code selector (0x18) — still PM, but 16-bit
;   4. Load 16-bit data selectors (0x20)
;   5. Clear CR0.PE (and CR0.PG just in case)
;   6. Far jump to real-mode segment 0x0000 to flush prefetch queue
;   7. Reload all real-mode segments to zero
;   8. Restore saved SP
;   9. Reload real-mode IDT (BIOS IVT at 0x0000)
;  10. STI — BIOS interrupts live again
;  11. Clear screen so BIOS cursor is at a known position
;  12. Jump back into the 16-bit shell loop
; ---------------------------------------------------------------------------
pm_cmd_exit:
    ; print farewell while we still have PM screen
    mov  esi, pm_str_exit_msg
    mov  bl, 0x0E
    call pm_puts

    ; Shut down PM drivers before handing back to real mode
    call pm_drv_shutdown

    cli

    ; ── Step 3: far jump to 16-bit code selector (0x18) ─────────────────
    ; This loads CS with a 16-bit descriptor while still in PM.
    ; From this point the assembler switches to [BITS 16].
    jmp  0x18:pm_exit_16bit

[BITS 16]
pm_exit_16bit:
    ; ── Step 4: load 16-bit data selectors ───────────────────────────────
    mov  ax, 0x20
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
    mov  ss, ax

    ; ── Step 5: clear CR0.PE and CR0.PG ──────────────────────────────────
    mov  eax, cr0
    and  eax, 0x7FFFFFFE     ; clear bit 0 (PE) and bit 31 (PG)
    mov  cr0, eax

    ; ── Step 6: far jump to flush prefetch queue, enter real mode ─────────
    jmp  0x0000:pm_exit_realmode

pm_exit_realmode:
    ; ── Step 7: reload real-mode segments ────────────────────────────────
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
    mov  ss, ax

    ; ── Step 8: restore saved stack pointer ──────────────────────────────
    mov  sp, [rm_sp_save]

    ; ── Step 9: reload real-mode IDT (BIOS IVT at 0x0000:0x03FF) ────────
    lidt [rm_idtr]

    ; ── Step 10: re-enable interrupts ────────────────────────────────────
    sti

    ; ── Step 11: reinitialise real-mode drivers ───────────────────────────
    call drv_rm_init

    ; ── Step 12: clear screen and reset BIOS cursor ──────────────────────
    call screen_clear

    ; ── Step 12: far jump back into the 16-bit shell loop ────────────────
    db  0xEA                 ; far jump opcode (16-bit form)
    dw  kernel_main    ; 16-bit offset (already includes 0x8000)
    dw  0x0000               ; segment

; Real-mode IDT descriptor: limit=0x03FF (1024 bytes), base=0x00000000
rm_idtr:
    dw 0x03FF
    dd 0x00000000

[BITS 32]

; ---------------------------------------------------------------------------
; pm_cmd_probe - 32-bit mode prover
;
; Writes 0xDEADBEEF to 0x00100000 (above 1MB) then reads it back.
; Uses EDI exclusively for the address — avoids ECX conflict with loop/print.
; ---------------------------------------------------------------------------
pm_cmd_probe:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

    call pm_newline
    mov  esi, pm_str_probe_hdr
    mov  bl, 0x0B
    call pm_puts

    ; ── Write 0xDEADBEEF x16 to 0x100000 ────────────────────────────────
    mov  edi, 0x00100000
    mov  ecx, 16
    mov  eax, 0xDEADBEEF
.write:
    mov  [edi], eax
    add  edi, 4
    loop .write

    ; ── Read back and print using EDI as address ──────────────────────────
    mov  esi, pm_str_probe_written
    mov  bl, 0x07
    call pm_puts

    mov  edi, 0x00100000
    mov  dword [pm_probe_rows], 4

.row:
    mov  eax, edi
    call pm_print_hex32
    mov  al, ':'
    mov  bl, 0x07
    call pm_putc
    mov  al, ' '
    call pm_putc

    mov  dword [pm_probe_cols], 4
.col:
    mov  eax, [edi]
    call pm_print_hex32
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    add  edi, 4
    dec  dword [pm_probe_cols]
    jnz  .col

    call pm_newline
    dec  dword [pm_probe_rows]
    jnz  .row

    ; ── Verify ────────────────────────────────────────────────────────────
    call pm_newline
    mov  eax, [0x00100000]
    cmp  eax, 0xDEADBEEF
    jne  .fail

    mov  esi, pm_str_probe_pass
    mov  bl, 0x0A
    call pm_puts
    jmp  .done

.fail:
    mov  esi, pm_str_probe_fail
    mov  bl, 0x0C
    call pm_puts
    mov  eax, [0x00100000]
    call pm_print_hex32
    call pm_newline

.done:
    call pm_newline
    pop  esi
    pop  edi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; pm_print_hex32 - print EAX as 8 hex digits
; ---------------------------------------------------------------------------
pm_print_hex32:
    push eax
    push ebx
    push ecx
    push edx
    mov  ecx, 8
.loop:
    rol  eax, 4
    mov  edx, eax
    and  edx, 0x0F
    cmp  edx, 10
    jl   .digit
    add  dl, 'A' - 10
    jmp  .out
.digit:
    add  dl, '0'
.out:
    push eax
    mov  al, dl
    mov  bl, 0x0F
    call pm_putc
    pop  eax
    loop .loop
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret