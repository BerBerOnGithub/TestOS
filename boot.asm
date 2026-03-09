; ===========================================================================
; boot.asm - ClaudeOS Stage 1 Bootloader (MBR)
;
; Fits in 512 bytes. Only job: load Stage 2 (sectors 2-3) into
; 0x0000:0x7E00 and jump to it. Stage 2 handles loading the kernel.
; ===========================================================================

[BITS 16]
[ORG 0x7C00]

boot_start:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00
    sti

    mov  [boot_drive], dl

    ; Load Stage 2: 2 sectors from sector 2 → 0x0000:0x7E00
    mov  ah, 0x02
    mov  al, 2               ; 2 sectors = 1KB, plenty for stage 2
    mov  ch, 0               ; cylinder 0
    mov  cl, 2               ; sector 2
    mov  dh, 0               ; head 0
    mov  dl, [boot_drive]
    mov  bx, 0x7E00          ; ES:BX = 0x0000:0x7E00
    int  0x13
    jc   .error

    mov  dl, [boot_drive]
    jmp  0x0000:0x7E00

.error:
    mov  si, msg_error
    call bios_puts
    cli
    hlt

bios_puts:
    lodsb
    or   al, al
    jz   .done
    mov  ah, 0x0E
    xor  bx, bx
    int  0x10
    jmp  bios_puts
.done:
    ret

boot_drive: db 0
msg_error:  db 'Stage 1 error!', 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55