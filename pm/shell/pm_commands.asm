; ===========================================================================
; pm/pm_commands.asm - 32-bit PM shell command implementations
;   help, ver, clear, echo, calc
;
; Mirrors commands/ structure for the PM environment.
; Calls pm_screen, pm_string helpers. No BIOS.
; ===========================================================================
SCR_CAPTURE equ 0x1500000
SCR_BUF     equ 0x300000
SCR_W       equ 640
SCR_H       equ 480
SCR_PIX     equ 307200
BMP_HDR_SZ  equ 1078
BMP_FILE_SZ equ 308278


[BITS 32]

; -
; pm_cmd_help
; -
pm_cmd_help:
    push esi
    push ebx
    mov  esi, pm_str_help_text
    mov  bl, 0x0B            ; cyan
    call pm_puts
    pop  ebx
    pop  esi
    ret

; -
; pm_cmd_clear
; -
pm_cmd_clear:
    pusha
    mov  ecx, [term_active_id]
    shl  ecx, 2
    mov  edi, [term_buf_ptrs + ecx]
    test edi, edi
    jz   .done
    
    mov  ecx, (TERM_BUF_COLS * TERM_BUF_ROWS * 2 + 3) / 4
    xor  eax, eax
    rep  stosd
    
    ; reset cursor for active terminal
    mov  ebx, [term_active_id]
    shl  ebx, 2
    mov  dword [term_col + ebx], 0
    mov  dword [term_row + ebx], 0
    
    ; redraw terminal window
    mov  ecx, [term_active_id]
    call term_redraw
.done:
    popa
    ret

; -
; pm_cmd_echo  -  print everything after "echo "
; -
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

; -
; pm_cmd_calc  -  calc <num> <op> <num>
; Signed 32-bit integers. Operators: + - * /
; Multiplication result capped at 32 bits (overflow flagged).
; -
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

; -
; pm_cmd_exit - switch back to 16-bit real mode
;
; Sequence (per OSDev wiki / tutorial):
;   1. Print message
;   2. Disable interrupts
;   3. Far jump to 16-bit PM code selector (0x18) - still PM, but 16-bit
;   4. Load 16-bit data selectors (0x20)
;   5. Clear CR0.PE (and CR0.PG just in case)
;   6. Far jump to real-mode segment 0x0000 to flush prefetch queue
;   7. Reload all real-mode segments to zero
;   8. Restore saved SP
;   9. Reload real-mode IDT (BIOS IVT at 0x0000)
;  10. STI - BIOS interrupts live again
;  11. Clear screen so BIOS cursor is at a known position
;  12. Jump back into the 16-bit shell loop
; -
pm_cmd_exit:
    ; print farewell while we still have PM screen
    mov  esi, pm_str_exit_msg
    mov  bl, 0x0E
    call pm_puts

    ; Shut down PM drivers before handing back to real mode
    call pm_drv_shutdown

    cli

    ; - Step 3: far jump to 16-bit code selector (0x18) -
    ; This loads CS with a 16-bit descriptor while still in PM.
    ; From this point the assembler switches to [BITS 16].
    jmp  0x18:pm_exit_16bit

[BITS 16]
pm_exit_16bit:
    ; - Step 4: load 16-bit data selectors -
    mov  ax, 0x20
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
    mov  ss, ax

    ; - Step 5: clear CR0.PE and CR0.PG -
    mov  eax, cr0
    and  eax, 0x7FFFFFFE     ; clear bit 0 (PE) and bit 31 (PG)
    mov  cr0, eax

    ; - Step 6: far jump to flush prefetch queue, enter real mode -
    jmp  0x0000:pm_exit_realmode

pm_exit_realmode:
    ; - Step 7: reload real-mode segments -
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
    mov  ss, ax

    ; - Step 8: restore saved stack pointer -
    mov  sp, [rm_sp_save]

    ; - Step 9: reload real-mode IDT (BIOS IVT at 0x0000:0x03FF) -
    lidt [rm_idtr]

    ; - Step 10: re-enable interrupts -
    sti

    ; - Step 11: reinitialise real-mode drivers -
    call drv_rm_init

    ; - Step 12: clear screen and reset BIOS cursor -
    call screen_clear

    ; - Step 12: far jump back into the 16-bit shell loop -
    db  0xEA                 ; far jump opcode (16-bit form)
    dw  kernel_main    ; 16-bit offset (already includes 0x8000)
    dw  0x0000               ; segment

; Real-mode IDT descriptor: limit=0x03FF (1024 bytes), base=0x00000000
rm_idtr:
    dw 0x03FF
    dd 0x00000000

[BITS 32]

; -
; pm_cmd_probe - 32-bit mode prover
;
; Writes 0xDEADBEEF to 0x00100000 (above 1MB) then reads it back.
; Uses EDI exclusively for the address - avoids ECX conflict with loop/print.
; -
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

    ; - Write 0xDEADBEEF x16 to 0x100000 -
    mov  edi, 0x00100000
    mov  ecx, 16
    mov  eax, 0xDEADBEEF
.write:
    mov  [edi], eax
    add  edi, 4
    loop .write

    ; - Read back and print using EDI as address -
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

    ; - Verify -
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

; -
; pm_print_hex32 - print EAX as 8 hex digits
; -
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

; -
; pm_cmd_savescr - build BMP from 0x600000 and write to data disk
; 0x600000 was filled by wm_screenshot_capture from GFX_SHADOW (shadow buf)
; BMP is bottom-up: row 479 first (screen top), row 0 last (screen bottom)
; -
pm_cmd_savescr:
    pusha

    cmp  byte [scr_pending], 1
    jne  .no_pending
    mov  byte [scr_pending], 0

    ; Allocate BMP processing buffer
    mov  ecx, 308278
    mov  edx, scr_proc_tag
    call kmalloc
    jc   .mem_fail
    mov  [scr_buf_ptr], eax

    ; BMP file header (14 bytes)
    mov  edi, [scr_buf_ptr]
    mov  word  [edi+0],  0x4D42
    mov  dword [edi+2],  308278
    mov  dword [edi+6],  0
    mov  dword [edi+10], 1078
    add  edi, 14

    ; BITMAPINFOHEADER (40 bytes)
    mov  dword [edi+0],  40
    mov  dword [edi+4],  640
    mov  dword [edi+8],  480
    mov  word  [edi+12], 1
    mov  word  [edi+14], 8
    mov  dword [edi+16], 0
    mov  dword [edi+20], 307200
    mov  dword [edi+24], 2835
    mov  dword [edi+28], 2835
    mov  dword [edi+32], 256
    mov  dword [edi+36], 256
    add  edi, 40

    ; Palette: 256 entries from VGA DAC, B G R 0 order
    cli
    mov  dx, 0x3C6
    mov  al, 0xFF
    out  dx, al
    xor  al, al
    mov  dx, 0x3C7
    out  dx, al
    xor  ecx, ecx
.pal:
    mov  dx, 0x3C9
    in   al, dx
    shl  al, 2
    mov  [edi+2], al
    in   al, dx
    shl  al, 2
    mov  [edi+1], al
    in   al, dx
    shl  al, 2
    mov  [edi+0], al
    mov  byte [edi+3], 0
    add  edi, 4
    inc  ecx
    cmp  ecx, 256
    jl   .pal
    sti

    mov  ecx, 480
.row:
    dec  ecx
    mov  eax, 640
    imul eax, ecx
    mov  esi, [scr_capture_ptr]   ; read from dynamic capture buffer
    add  esi, eax
    push ecx
    mov  ecx, 160
    rep  movsd
    pop  ecx
    test ecx, ecx
    jnz  .row

    ; generate filename scr0001..scr9999
    inc  dword [scr_counter]
    mov  eax, [scr_counter]
    cmp  eax, 9999
    jle  .nc
    mov  eax, 9999
    mov  dword [scr_counter], 9999
.nc:
    mov  ebx, 1000
    mov  edi, scr_name + 3
    xor  edx, edx
    div  ebx
    add  al, '0'
    mov  [edi], al
    inc  edi
    mov  eax, edx
    mov  ebx, 100
    xor  edx, edx
    div  ebx
    add  al, '0'
    mov  [edi], al
    inc  edi
    mov  eax, edx
    mov  ebx, 10
    xor  edx, edx
    div  ebx
    add  al, '0'
    mov  [edi], al
    inc  edi
    add  dl, '0'
    mov  [edi], dl

    ; write to disk
    mov  esi, scr_name
    mov  eax, [scr_buf_ptr]
    mov  [fsd_create_data], eax
    mov  ecx, 308278
    call fsd_create
    jc   .full

    mov  esi, scr_msg_ok_save
    call wm_notify
    jmp  .done

.full:
    mov  esi, scr_msg_full
    call wm_notify
    jmp  .done

.no_pending:
    mov  esi, savescr_str_none
    mov  bl, 0x0C
    call term_puts
    call term_newline
    popa
    ret

.mem_fail:
    mov  esi, .msg_mem_fail
    call term_puts
    call term_newline
    popa
    ret
.msg_mem_fail: db 'Out of memory for screenshot processing!', 0

.done:
    ; Free both dynamic buffers
    mov  eax, [scr_capture_ptr]
    test eax, eax
    jz   .no_cap_free
    mov  edx, tag_scr_cap_shell
    call kfree
    mov  dword [scr_capture_ptr], 0
.no_cap_free:

    mov  eax, [scr_buf_ptr]
    test eax, eax
    jz   .no_buf_free
    mov  edx, scr_proc_tag
    call kfree
    mov  dword [scr_buf_ptr], 0
.no_buf_free:

    popa
    ret

savescr_str_none: db 'No screenshot pending. Press PrtSc first!', 13, 10, 0

; -
; pm_cmd_ls  -  list files on data disk and ISO FS
; -
pm_cmd_ls:
    pusha

    call term_newline
    mov  esi, ls_str_hdr
    call term_puts

    ; - ISO (read-only) -
    mov  esi, ls_str_iso_sec
    call term_puts

    cmp  dword [FS_PM_BASE], FS_MAGIC_VAL
    jne  .iso_no

    movzx ecx, word [FS_PM_BASE + 4]
    test ecx, ecx
    jz   .iso_empty


    mov  esi, FS_PM_BASE + 6     ; first directory entry
.iso_row:
    test ecx, ecx
    jz   .iso_done
    ; name (null-terminated up to 16 bytes)
    push esi
    push ecx
    mov  dl, 0x07
    call term_puts_colour
    ; size
    pop  ecx
    pop  esi
    mov  eax, [esi + 20]
    push esi
    push ecx
    mov  esi, ls_str_tab
    call term_puts
    call ls_print_size
    call term_newline
    pop  ecx
    pop  esi
    add  esi, 24             ; FS_ENT_SZ
    dec  ecx
    jmp  .iso_row
.iso_empty:
    mov  esi, ls_str_empty
    call term_puts
    call term_newline
.iso_no:
    cmp  dword [FS_PM_BASE], FS_MAGIC_VAL
    je   .iso_done
    mov  esi, ls_str_no_iso
    call term_puts

    call term_newline
.iso_done:

    ; - DATA disk -
    call term_newline
    mov  esi, ls_str_data_sec
    call term_puts

    cmp  byte [fsd_ready], 1
    jne  .data_no

    cmp  dword [fsd_used], 0
    je   .data_empty

    mov  esi, fsd_dir_buf
    mov  ecx, FSD_MAX_ENT
.data_row:
    test ecx, ecx
    jz   .data_done
    cmp  dword [esi + 24], FSD_FLAG_USED
    jne  .data_skip

    push esi
    push ecx
    mov  dl, 0x0F
    call term_puts_colour
    mov  eax, [esi + 20]
    mov  esi, ls_str_tab
    call term_puts
    call ls_print_size
    call term_newline
    pop  ecx
    pop  esi

.data_skip:
    add  esi, FSD_ENT_SZ
    dec  ecx
    jmp  .data_row
.data_empty:
    mov  esi, ls_str_empty
    call term_puts
    call term_newline
    jmp  .data_done
.data_no:
    mov  esi, ls_str_no_data
    call term_puts
    call term_newline
.data_done:

    call term_newline
    popa
    ret

; ls_print_size - print EAX as size string to terminal
ls_print_size:
    push eax
    push esi
    cmp  eax, 1024
    jl   .bytes
    xor  edx, edx
    mov  ecx, 1024
    div  ecx
    call ls_print_dec
    mov  esi, ls_str_kb
    call term_puts
    jmp  .done
.bytes:
    call ls_print_dec
    mov  esi, ls_str_b
    call term_puts
.done:
    pop  esi
    pop  eax
    ret

ls_print_dec:
    push eax
    push ecx
    push edx
    mov  ecx, 0
    mov  edx, 10
    test eax, eax
    jnz  .push
    push dword 0
    inc  ecx
    jmp  .pop
.push:
    xor  edx, edx
    div  dword [ls_ten]
    push edx
    inc  ecx
    test eax, eax
    jnz  .push
.pop:
    pop  edx
    add  dl, '0'
    mov  al, dl
    call term_putchar
    loop .pop
    pop  edx
    pop  ecx
    pop  eax
    ret

ls_ten: dd 10

; -
; pm_cmd_beep - Play a tone using the PC Speaker
; Usage: beep <freq> <ticks>
; -
pm_cmd_beep:
    pusha
    
    mov  esi, pm_input_buf
    add  esi, 5              ; skip "beep "
    call pm_skip_spaces
    
    mov  al, [esi]
    or   al, al
    jz   .usage
    
    call pm_parse_int
    push eax                 ; safe-store frequency
    
    call pm_skip_spaces
    mov  al, [esi]
    or   al, al
    jz   .usage_pop
    
    call pm_parse_int
    mov  ebx, eax            ; EBX = duration_ticks
    pop  eax                 ; EAX = frequency
    
    call speaker_beep
    jmp  .done
    
.usage_pop:
    pop  eax
.usage:
    mov  esi, pm_str_beep_usage
    mov  bl, 0x0E
    call pm_puts
    call pm_newline
    
.done:
    popa
    ret

; -
; pm_cmd_cat  -  print text file to terminal
; Usage: cat <name>
; -
pm_cmd_cat:
    pusha

    mov  esi, pm_input_buf
    add  esi, 4              ; skip "cat "
    call pm_skip_spaces

    ; look in data disk first
    cmp  byte [fsd_ready], 1
    jne  .try_iso

    call fsd_find            ; ESI=name -> CF=0: EAX=entry ptr
    jc   .try_iso

    ; found on data disk - read into dynamic buffer
    mov  ecx, 32768
    mov  edx, cat_buf_tag
    call kmalloc
    jc   .mem_fail
    mov  [cat_buf_ptr], eax
    mov  edi, eax
    call fsd_read_file       ; EAX=entry, EDI=dest -> ECX=bytes
    jmp  .print_buf

.try_iso:
    ; look in ISO FS
    cmp  dword [FS_PM_BASE], FS_MAGIC_VAL
    jne  .not_found

    mov  ecx, 32768
    call kmalloc
    jc   .mem_fail
    mov  [cat_buf_ptr], eax

    mov  esi, pm_input_buf
    add  esi, 4
    call pm_skip_spaces
    call fs_pm_find          ; ESI=name -> CF=0: EAX=data ptr, ECX=size
    jc   .not_found_free

    ; copy from ISO into cat_buf (max 32KB)
    push eax
    push ecx
    mov  esi, eax
    mov  edi, [cat_buf_ptr]
    cmp  ecx, 32768
    jle  .iso_copy_ok
    mov  ecx, 32768
.iso_copy_ok:
    mov  [cat_bytes], ecx
    rep  movsb
    pop  ecx
    pop  eax
    mov  ecx, [cat_bytes]
    jmp  .print_buf

.print_buf:
    ; ECX = bytes to print
    call term_newline
    mov  esi, [cat_buf_ptr]
    xor  edx, edx            ; byte index
.print_loop:
    cmp  edx, ecx
    jge  .print_done
    mov  al, [esi + edx]
    cmp  al, 0               ; stop at null (text files)
    je   .print_done
    call term_putchar
    inc  edx
    jmp  .print_loop
.print_done:
    call term_newline
    call term_newline
    jmp  .done

.not_found_free:
    mov  eax, [cat_buf_ptr]
    mov  edx, cat_buf_tag
    call kfree
    mov  dword [cat_buf_ptr], 0
.not_found:
    call term_newline
    mov  esi, cat_str_notfound
    call term_puts
    call term_newline
    jmp  .done

.mem_fail:
    mov  esi, cat_str_memfail
    call term_puts
    call term_newline
    jmp  .done

.done:
    mov  eax, [cat_buf_ptr]
    test eax, eax
    jz   .no_free
    mov  edx, cat_buf_tag
    call kfree
    mov  dword [cat_buf_ptr], 0
.no_free:
    popa
    ret

; -
; pm_cmd_rm  -  delete a file from data disk
; Usage: rm <name>
; -
pm_cmd_rm:
    pusha

    cmp  byte [fsd_ready], 1
    jne  .no_disk

    mov  esi, pm_input_buf
    add  esi, 3              ; skip "rm "
    call pm_skip_spaces

    call fsd_delete          ; ESI=name -> CF=0 ok, CF=1 not found
    jc   .not_found

    call term_newline
    mov  esi, rm_str_ok
    call term_puts
    call term_newline
    ; refresh files window if open
    call wm_draw_all
    jmp  .done

.not_found:
    call term_newline
    mov  esi, rm_str_notfound
    call term_puts
    call term_newline
    jmp  .done
.no_disk:
    call term_newline
    mov  esi, rm_str_nodisk
    call term_puts
    call term_newline
.done:
    popa
    ret

; -
; pm_cmd_hexdump  -  hex + ASCII dump of a file
; Usage: hexdump <name>
; -
pm_cmd_hexdump:
    pusha

    mov  esi, pm_input_buf
    add  esi, 8              ; skip "hexdump "
    call pm_skip_spaces

    ; look in data disk first
    cmp  byte [fsd_ready], 1
    jne  .try_iso_hex

    call fsd_find
    jc   .try_iso_hex

    mov  ecx, 32768
    mov  edx, cat_buf_tag
    call kmalloc
    jc   .mem_fail_hex
    mov  [cat_buf_ptr], eax
    mov  edi, eax
    call fsd_read_file       ; ECX = bytes
    jmp  .dump

.try_iso_hex:
    cmp  dword [FS_PM_BASE], FS_MAGIC_VAL
    jne  .hex_notfound

    mov  ecx, 32768
    call kmalloc
    jc   .mem_fail_hex
    mov  [cat_buf_ptr], eax

    mov  esi, pm_input_buf
    add  esi, 8
    call pm_skip_spaces
    call fs_pm_find
    jc   .hex_notfound_free
    push eax
    push ecx
    mov  esi, eax
    mov  edi, [cat_buf_ptr]
    cmp  ecx, 32768
    jle  .hex_iso_ok
    mov  ecx, 32768
.hex_iso_ok:
    mov  [cat_bytes], ecx
    rep  movsb
    pop  ecx
    pop  eax
    mov  ecx, [cat_bytes]

.dump:
    ; limit to 512 bytes for terminal space
    cmp  ecx, 512
    jle  .dump_sz_ok
    mov  ecx, 512
.dump_sz_ok:
    call term_newline
    xor  edx, edx            ; byte offset
.row:
    cmp  edx, ecx
    jge  .dump_done

    ; print offset
    mov  eax, edx
    call hex_print_word
    mov  al, ':'
    call term_putchar
    mov  al, ' '
    call term_putchar

    ; print 16 hex bytes
    push edx
    mov  [hex_row_off], edx
    mov  ebx, 0
.hex_bytes:
    cmp  ebx, 16
    jge  .hex_ascii
    mov  eax, [hex_row_off]
    add  eax, ebx
    cmp  eax, ecx
    jge  .hex_pad
    push esi
    mov  esi, [cat_buf_ptr]
    movzx eax, byte [esi + eax]
    pop  esi
    call hex_print_byte
    jmp  .hex_cont
.hex_pad:
    mov  al, ' '
    call term_putchar
    call term_putchar
.hex_cont:
    mov  al, ' '
    call term_putchar
    inc  ebx
    jmp  .hex_bytes
.hex_ascii:
    ; print ASCII representation
    mov  al, '|'
    call term_putchar
    mov  ebx, 0
.ascii_bytes:
    cmp  ebx, 16
    jge  .ascii_done
    mov  eax, [hex_row_off]
    add  eax, ebx
    cmp  eax, ecx
    jge  .ascii_pad
    push esi
    mov  esi, [cat_buf_ptr]
    movzx eax, byte [esi + eax]
    pop  esi
    cmp  al, 32
    jl   .ascii_dot
    cmp  al, 126
    jg   .ascii_dot
    call term_putchar
    jmp  .ascii_next
.ascii_dot:
    mov  al, '.'
    call term_putchar
.ascii_next:
    inc  ebx
    jmp  .ascii_bytes
.ascii_pad:
    mov  al, ' '
    call term_putchar
    inc  ebx
    jmp  .ascii_bytes
.ascii_done:
    mov  al, '|'
    call term_putchar
    call term_newline

    pop  edx
    add  edx, 16
    jmp  .row
.dump_done:
    call term_newline
.dump_exit:
    mov  eax, [cat_buf_ptr]
    test eax, eax
    jz   .no_free_hex
    mov  edx, cat_buf_tag
    call kfree
    mov  dword [cat_buf_ptr], 0
.no_free_hex:
    popa
    ret

.hex_notfound_free:
    mov  eax, [cat_buf_ptr]
    mov  edx, cat_buf_tag
    call kfree
    mov  dword [cat_buf_ptr], 0
.hex_notfound:
    call term_newline
    mov  esi, cat_str_notfound
    call term_puts
    call term_newline
    jmp  .dump_exit

.mem_fail_hex:
    mov  esi, cat_str_memfail
    call term_puts
    call term_newline
    jmp  .dump_exit

; hex helpers
hex_print_byte:
    push eax
    push ecx
    mov  ecx, 2
.loop:
    rol  al, 4
    push eax
    and  al, 0x0F
    cmp  al, 10
    jl   .digit
    add  al, 'A' - 10
    jmp  .out
.digit:
    add  al, '0'
.out:
    call term_putchar
    pop  eax
    loop .loop
    pop  ecx
    pop  eax
    ret

hex_print_word:
    push eax
    shr  eax, 8
    call hex_print_byte
    pop  eax
    call hex_print_byte
    ret

hex_row_off:    dd 0

; -
; Shared data
; -
; CAT_BUF_ADDR lives at 0x180000 (fixed RAM)
; This saves 32KB from the kernel binary.
; cat_buf_ptr replaces fixed CAT_BUF_ADDR equ 0x180000
cat_buf_ptr:   dd 0

cat_bytes:     dd 0

ls_str_hdr:      db 'Files', 13, 10, '-', 13, 10, 0
ls_str_iso_sec:  db '[ISO - read only]', 13, 10, 0
ls_str_data_sec: db '[DATA - writable]', 13, 10, 0
ls_str_empty:    db '  (empty)', 0
ls_str_no_iso:   db '  No ISO filesystem', 0
ls_str_no_data:  db '  No data disk', 0
ls_str_tab:      db '  ', 0
ls_str_kb:       db ' KB', 0
ls_str_b:        db ' B', 0

cat_str_notfound: db 'File not found', 13, 10, 0
rm_str_ok:        db 'File deleted.', 13, 10, 0
rm_str_notfound:  db 'File not found.', 13, 10, 0
rm_str_nodisk:    db 'No data disk.', 13, 10, 0
cat_str_memfail:  db 'Memory allocation failed!', 0
; -
; pm_cmd_bioscall - demo of the 16-bit to 32-bit bridge
; Calls BIOS INT 1Ah (AH=04h) to read RTC date.
; -
pm_cmd_bioscall:
    pusha
    call pm_newline
    mov  esi, bioscall_str_starting
    mov  bl, 0x0E ; yellow
    call pm_puts

    ; Call INT 12h (Get Memory Size)
    mov  edi, RM_REGS_ADDR
    mov  ecx, 8
    xor  eax, eax
    rep  stosd
    
    mov  al, 0x12
    call pm_bios_call
    
    ; Result in AX
    mov  eax, [RM_REGS_ADDR + 0]
    mov  [bioscall_tmp_ecx], eax

    mov  esi, bioscall_str_ok
    mov  bl, 0x0A ; green
    call pm_puts

    ; Formatted result
    mov  esi, bioscall_str_mem_lbl
    mov  bl, 0x0B
    call pm_puts
    mov  eax, [bioscall_tmp_ecx]
    and  eax, 0xFFFF
    call pm_print_hex16
    mov  esi, bioscall_str_kb_hex
    call pm_puts
    call pm_newline

    jmp  .done

.err:
    mov  esi, bioscall_str_err
    mov  bl, 0x0C ; red
    call pm_puts
    call pm_newline

.done:
    popa
    ret

.print_bcd:
    push eax
    push ebx
    mov  bl, al
    shr  al, 4
    and  al, 0x0F
    add  al, '0'
    call pm_putc
    mov  al, bl
    and  al, 0x0F
    add  al, '0'
    call pm_putc
    pop  ebx
    pop  eax
    ret

bioscall_str_starting: db ' [BRIDGE] Querying BIOS for Memory Size (INT 12h)...', 13, 10, 0
bioscall_str_ok:       db ' [OK] BIOS sequence complete.', 13, 10, 0
bioscall_str_mem_lbl:  db ' [OK] Base Memory Size (Hex): 0x', 0
bioscall_str_kb_hex:   db ' KB', 0
bioscall_str_err:      db ' [ERR] BIOS call failed.', 0
bioscall_tmp_ecx:      dd 0
bioscall_tmp_edx:      dd 0

; ===========================================================================
; pm_cmd_browser - Open the simple web browser
; ===========================================================================
pm_cmd_browser:
    pusha
    mov  al,  WM_BROWSER
    mov  ebx, 50            ; x
    mov  ecx, 50            ; y
    mov  edx, 400           ; w
    mov  esi, 300           ; h
    call wm_open
    jc   .full
    push ecx
    call wm_draw_all
    pop  ecx
    call browser_init
    jmp  .done
.full:
    mov  esi, pm_str_wm_full
    call term_puts
    call term_newline
.done:
    popa
    ret

; ===========================================================================
; pm_cmd_wp - Set desktop wallpaper
; Usage: wp <filename>
; ===========================================================================
pm_cmd_wp:
    pusha
    mov  esi, pm_input_buf
    add  esi, 3              ; skip "wp "
    call pm_skip_spaces
    
    mov  al, [esi]
    test al, al
    jz   .usage

    ; Copy filename to wallpaper's buffer
    mov  edi, wp_filename
    mov  ecx, 31
.copy:
    mov  al, [esi]
    cmp  al, ' '
    jbe  .done_copy
    mov  [edi], al
    inc  esi
    inc  edi
    loop .copy
.done_copy:
    mov  byte [edi], 0

    ; Call wallpaper loader
    call wallpaper_load
    call wm_draw_all        ; refresh desktop
    jmp  .done

.usage:
    mov  esi, wp_str_usage
    mov  bl, 0x0E
    call pm_puts
.done:
    popa
    ret

wp_str_usage: db 'Usage: wp <filename.bmp>', 13, 10, 0

; ===========================================================================
; pm_cmd_notepad - Open GUI Notepad
; ===========================================================================
pm_cmd_notepad:
    pusha
    mov  al,  WM_NOTEPAD
    mov  ebx, 130
    mov  ecx, 70
    mov  edx, 480
    mov  esi, 320
    call wm_open
    jc   .full
    push ecx
    call wm_draw_all
    pop  ecx
    call notepad_init
    jmp  .done
.full:
    mov  esi, pm_str_wm_full
    call term_puts
    call term_newline
.done:
    popa
    ret

; ===========================================================================
; pm_cmd_taskman - Open GUI Task Manager
; ===========================================================================
pm_cmd_taskman:
    pusha
    mov  al,  WM_TASKMAN
    mov  ebx, 100
    mov  ecx, 100
    mov  edx, 500
    mov  esi, 160
    call wm_open
    popa
    ret

; ===========================================================================
; pm_cmd_shutdown - Power off the system via ACPI
; ===========================================================================
pm_cmd_shutdown:
    pusha
    mov  esi, pm_str_shutdown_msg
    mov  bl, 0x0E
    call pm_puts
    call pm_newline
    
    call acpi_shutdown
    
    ; if we reach here, ACPI shutdown failed
    mov  esi, pm_str_shutdown_fail
    mov  bl, 0x0C
    call pm_puts
    call pm_newline
    popa
    ret

pm_str_shutdown_msg:  db 'Shutting down via ACPI...', 0
pm_str_shutdown_fail: db 'ACPI shutdown failed or not supported by hardware.', 0

; ===========================================================================
; pm_cmd_paint - Open GUI Paint
; ===========================================================================
pm_cmd_paint:
    pusha
    mov  al,  WM_PAINT
    mov  ebx, 100
    mov  ecx, 60
    mov  edx, PAINT_W
    mov  esi, PAINT_H
    call wm_open
    jc   .full
    push ecx
    call wm_draw_all
    pop  ecx
    call paint_init
    jmp  .done
.full:
    mov  esi, pm_str_wm_full
    call term_puts
    call term_newline
.done:
    popa
    ret

; ===========================================================================
; pm_cmd_crash - Trigger a Page Fault (0x0E)
; ===========================================================================
pm_cmd_crash:
    pusha
    mov  esi, .str_crash
    call term_puts
    call term_newline

    ; Intentionally trigger a Page Fault (0x0E) 
    ; by writing to an unmapped address (above 256MB).
    mov  eax, 0x80000000
    mov  [eax], eax

    popa
    ret
.str_crash: db "Triggering Page Fault for BSOD verification...", 0

scr_proc_tag:       db 'screenshot_proc', 0
tag_scr_cap_shell:  db 'screenshot_cap', 0
cat_buf_tag:        db 'shell_cat_buf', 0

; ===========================================================================
; pm_cmd_vesatest - Switch VESA mode to test arbitrary resolutions
; ===========================================================================
pm_cmd_vesatest:
    pusha
    mov  esi, pm_input_buf
    add  esi, 9              ; skip "vesatest "
    call pm_skip_spaces
    call pm_parse_uint
    
    test eax, eax
    jnz  .got_mode
    mov  eax, 0x0103       ; Default to 800x600x8
.got_mode:
    mov  cx, ax            ; Save mode without LFB bit in CX
    mov  bx, ax
    or   bx, 0x4000        ; Request LFB

    ; Set Mode (AX=4F02h)
    mov  dword [0x1000 +  0], 0x00004F02    
    mov  dword [0x1000 +  4], ebx           
    mov  dword [0x1000 +  8], 0             
    mov  dword [0x1000 + 12], 0             
    mov  dword [0x1000 + 16], 0             
    mov  dword [0x1000 + 20], 0             
    mov  word  [0x1000 + 24], 0             
    mov  word  [0x1000 + 26], 0             
    mov  al, 0x10
    call pm_bios_call

    ; Re-query mode info to find LFB (AX=4F01h, CX=mode)
    mov  dword [0x1000 +  0], 0x00004F01    
    mov  dword [0x1000 +  4], 0             
    movzx eax, cx
    mov  dword [0x1000 +  8], eax           
    mov  dword [0x1000 + 12], 0             
    mov  dword [0x1000 + 16], 0             
    mov  dword [0x1000 + 20], 0             
    mov  word  [0x1000 + 24], 0             
    mov  word  [0x1000 + 26], 0x0720        
    mov  al, 0x10
    call pm_bios_call

    ; Check if LFB is available at offset 0x28 in MIB (0x7200)
    mov  edi, [0x7228]
    test edi, edi
    jz   .hang

    ; Get width, height and BPP to calculate pixel count
    movzx eax, word [0x7212] ; XRES
    movzx ebx, word [0x7214] ; YRES
    movzx edx, byte [0x7219] ; BPP
    
    ; Output debug info over serial
    push esi
    mov  esi, .str_dbg_res
    call serial_print
    call serial_print_hex32
    mov  esi, .str_dbg_x
    call serial_print
    mov  eax, ebx
    call serial_print_hex32
    mov  esi, .str_dbg_bpp
    call serial_print
    mov  eax, edx
    call serial_print_hex32
    mov  esi, .str_dbg_nl
    call serial_print
    pop  esi

    movzx eax, word [0x7212] ; XRES
    movzx ebp, word [0x7210] ; PITCH
    
    ; adjust pixel count based on BPP
    cmp edx, 8
    je  .bpp8
    cmp edx, 15
    je  .bpp16
    cmp edx, 16
    je  .bpp16
    cmp edx, 24
    je  .bpp24
    cmp edx, 32
    je  .bpp32
    jmp .hang ; Unknown BPP
    
.bpp8:
    mov  ecx, ebx       ; ecx = YRES
    xor  esi, esi       ; esi = Y
.draw8_row:
    push eax            ; save XRES
    push ecx
    push edi
    mov  ecx, eax       ; ecx = XRES
    xor  edx, edx       ; edx = X
.draw8_col:
    mov  eax, edx
    xor  eax, esi
    mov  [edi], al
    inc  edi
    inc  edx
    loop .draw8_col
    pop  edi
    add  edi, ebp       ; next row
    pop  ecx
    pop  eax            ; restore XRES
    inc  esi            ; Y++
    loop .draw8_row
    jmp  .hang

.bpp16:
    mov  ecx, ebx
    xor  esi, esi
.draw16_row:
    push eax            ; save XRES
    push ecx
    push edi
    mov  ecx, eax       ; ecx = XRES
    xor  edx, edx       ; edx = X
.draw16_col:
    ; R (5 bits) = X[7:3]
    mov  eax, edx
    and  eax, 0xF8
    shl  eax, 8         ; R in [15:11]

    ; G (6 bits) = Y[7:2]
    mov  ebx, esi
    and  ebx, 0xFC
    shl  ebx, 3         ; G in [10:5]
    or   eax, ebx

    ; B (5 bits) = (X+Y)[7:3]
    mov  ebx, edx
    add  ebx, esi
    and  ebx, 0xF8
    shr  ebx, 3         ; B in [4:0]
    or   eax, ebx

    mov  [edi], ax
    add  edi, 2
    inc  edx
    loop .draw16_col
    pop  edi
    add  edi, ebp
    pop  ecx
    pop  eax            ; restore XRES
    inc  esi            ; Y++
    loop .draw16_row
    jmp  .hang
    
.bpp24:
    mov  ecx, ebx
    xor  esi, esi
.draw24_row:
    push eax            ; save XRES
    push ecx
    push edi
    mov  ecx, eax       ; ecx = XRES
    xor  edx, edx       ; edx = X
.draw24_col:
    ; B = (X+Y)
    mov  ebx, edx
    add  ebx, esi
    mov  [edi], bl
    
    ; G = Y
    mov  eax, esi
    mov  [edi+1], al
    
    ; R = X
    mov  eax, edx
    mov  [edi+2], al

    add  edi, 3
    inc  edx
    loop .draw24_col
    pop  edi
    add  edi, ebp
    pop  ecx
    pop  eax            ; restore XRES
    inc  esi            ; Y++
    loop .draw24_row
    jmp  .hang

.bpp32:
    mov  ecx, ebx
    xor  esi, esi
.draw32_row:
    push eax            ; save XRES
    push ecx
    push edi
    mov  ecx, eax       ; ecx = XRES
    xor  edx, edx       ; edx = X
.draw32_col:
    ; R = X
    mov  eax, edx
    and  eax, 0xFF
    shl  eax, 16        ; EAX = [00 | R | 00 | 00]
    
    ; G = Y
    mov  ebx, esi
    and  ebx, 0xFF
    shl  ebx, 8         ; EBX = [00 | 00 | G | 00]
    or   eax, ebx
    
    ; B = X + Y
    mov  ebx, edx
    add  ebx, esi
    and  ebx, 0xFF
    or   eax, ebx       ; EAX = [00 | R | G | B]
    
    mov  [edi], eax
    add  edi, 4
    inc  edx
    loop .draw32_col
    pop  edi
    add  edi, ebp
    pop  ecx
    pop  eax            ; restore XRES
    inc  esi            ; Y++
    loop .draw32_row
    jmp  .hang

.hang:
    cli
    hlt
    jmp  .hang

.str_dbg_res: db '[VESATest] Set Resolution: ', 0
.str_dbg_x:   db ' x ', 0
.str_dbg_bpp: db ' BPP: ', 0
.str_dbg_nl:  db 13, 10, 0

; ===========================================================================
; pm_cmd_vesamodes - List all VESA modes supported by the BIOS
; ===========================================================================
pm_cmd_vesamodes:
    pusha
    
    ; The VbeInfoBlock was saved at 0x7000 during boot.
    ; Offset 0x0E contains a far pointer to the mode list (offset, segment).
    movzx eax, word [0x7010] ; segment
    shl   eax, 4
    movzx ebx, word [0x700E] ; offset
    add   eax, ebx           ; EAX = physical address of mode list array
    mov   ebp, eax           ; use EBP as mode pointer

.loop:
    movzx ecx, word [ebp]    ; read mode number
    cmp   cx, 0xFFFF         ; end of list?
    je    .done
    
    add   ebp, 2             ; advance pointer
    
    ; Query this mode via 4F01h
    mov  dword [0x1000 +  0], 0x00004F01    
    mov  dword [0x1000 +  4], 0             
    mov  dword [0x1000 +  8], ecx           
    mov  dword [0x1000 + 12], 0             
    mov  dword [0x1000 + 16], 0             
    mov  dword [0x1000 + 20], 0             
    mov  word  [0x1000 + 24], 0             
    mov  word  [0x1000 + 26], 0x0720        
    mov  al, 0x10
    call pm_bios_call
    
    mov  eax, [0x1000 + 0]
    and  eax, 0xFFFF
    cmp  eax, 0x004F
    jne  .loop
    
    ; Read MIB at 0x7200
    mov  ax, [0x7200]       ; attributes
    test ax, 0x0080         ; LFB available?
    jz   .loop
    test ax, 0x0010         ; Graphics mode?
    jz   .loop
    
    ; Print "Mode: 0xXXXX = 1280x720x32"
    mov  esi, .str_mode
    call term_puts
    
    mov  eax, ecx
    call pm_print_hex16
    
    mov  esi, .str_eq
    call term_puts
    
    movzx eax, word [0x7212] ; width
    call pm_print_uint
    mov  esi, .str_x
    call term_puts
    
    movzx eax, word [0x7214] ; height
    call pm_print_uint
    mov  esi, .str_x
    call term_puts
    
    movzx eax, byte [0x7219] ; bpp
    call pm_print_uint
    call term_newline

    jmp   .loop

.done:
    popa
    ret

.str_mode: db 'Mode: 0x', 0
.str_eq:   db ' = ', 0
.str_x:    db 'x', 0


