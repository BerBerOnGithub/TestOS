; ===========================================================================
; boot.asm - ClaudeOS Stage 1 Bootloader
;
; Assembled with: nasm -f bin -o boot.bin boot.asm
;
; Fits in the 512-byte MBR. Loads the kernel (32 sectors = 16KB)
; from sector 2 of the disk into memory at 0x0000:0x8000, then
; jumps to it. Loads 40 sectors (20KB) to give room for growth.
; ===========================================================================

[BITS 16]
[ORG 0x7C00]

; ---------------------------------------------------------------------------
; Entry point
; ---------------------------------------------------------------------------
boot_start:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00         ; stack grows down from 0x7C00
    sti

    mov  [boot_drive], dl   ; BIOS passes boot drive number in DL

    ; Print "loading" message via BIOS teletype
    mov  si, msg_loading
    call bios_puts

    ; -----------------------------------------------------------------------
    ; Load kernel from disk using BIOS Int 13h (CHS mode)
    ;   Cylinder 0, Head 0, Sector 2  →  32 sectors (16 KB)
    ;   Destination: 0x0000:0x8000
    ; -----------------------------------------------------------------------
    mov  ah, 0x02           ; function: read sectors
    mov  al, 64             ; sector count
    mov  ch, 0              ; cylinder 0
    mov  cl, 2              ; sector 2  (BIOS sectors are 1-indexed)
    mov  dh, 0              ; head 0
    mov  dl, [boot_drive]   ; drive
    mov  bx, 0x8000         ; ES:BX destination  (ES=0 from above)
    int  0x13
    jc   .disk_error

    ; Pass boot drive number to kernel in DL, then hand control over
    mov  dl, [boot_drive]
    jmp  0x0000:0x8000      ; far jump to kernel entry point

.disk_error:
    mov  si, msg_error
    call bios_puts
    cli
    hlt

; ---------------------------------------------------------------------------
; bios_puts  –  print null-terminated string at DS:SI via BIOS teletype
; ---------------------------------------------------------------------------
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

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
boot_drive:   db 0
msg_loading:  db 'ClaudeOS v1.0 - Booting...', 13, 10, 0
msg_error:    db 13, 10, 'FATAL: Disk read error. System halted.', 13, 10, 0

; ---------------------------------------------------------------------------
; Pad to 510 bytes and append boot signature
; ---------------------------------------------------------------------------
times 510-($-$$) db 0
dw 0xAA55