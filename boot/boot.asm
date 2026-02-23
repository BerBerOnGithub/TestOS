[BITS 16]
[ORG 0x7C00]

; ─────────────────────────────────────────────────────
;  ClaudeOS Stage-1 Bootloader
;  • Runs at 0x7C00 in real mode (placed there by BIOS)
;  • Loads the kernel (sectors 2-63) to 0x1000:0000
;  • Enters 32-bit protected mode
;  • Jumps to kernel entry point at 0x10000
; ─────────────────────────────────────────────────────

KERNEL_OFFSET equ 0x10000     ; physical load address of kernel
KERNEL_SECTOR equ 2           ; kernel starts at sector 2 on disk
KERNEL_COUNT  equ 62          ; number of sectors to read (31 KB)

start:
    ; ── Set up segments ──────────────────────────────
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00      ; stack grows down from bootloader
    sti

    ; ── Save boot drive ──────────────────────────────
    mov [boot_drive], dl

    ; ── Print banner ─────────────────────────────────
    mov si, msg_loading
    call print_str

    ; ── Load kernel from disk (INT 13h) ──────────────
    mov bx, KERNEL_OFFSET >> 4  ; ES = 0x1000
    mov es, bx
    xor bx, bx                  ; BX = 0x0000  → ES:BX = 0x10000

    mov ah, 0x02            ; BIOS read sectors
    mov al, KERNEL_COUNT    ; sectors to read
    mov ch, 0               ; cylinder 0
    mov dh, 0               ; head 0
    mov cl, KERNEL_SECTOR   ; starting sector
    mov dl, [boot_drive]
    int 0x13
    jc  disk_error

    ; ── Enter protected mode ──────────────────────────
    cli
    lgdt [gdt_descriptor]

    mov eax, cr0
    or  eax, 0x1
    mov cr0, eax

    jmp CODE_SEG:protected_mode_start   ; far jump flushes pipeline

disk_error:
    mov si, msg_disk_err
    call print_str
    hlt

; ── Real-mode print (SI = string, null-terminated) ───
print_str:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_str
.done:
    ret

; ── GDT ──────────────────────────────────────────────
gdt_start:
    dq 0                    ; null descriptor
gdt_code:
    dw 0xFFFF               ; limit low
    dw 0x0000               ; base low
    db 0x00                 ; base mid
    db 10011010b            ; access: present, ring0, code, exec/read
    db 11001111b            ; flags: 4KB gran, 32-bit + limit high nibble
    db 0x00                 ; base high
gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b            ; access: present, ring0, data, read/write
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start

boot_drive db 0

msg_loading  db 'ClaudeOS: Loading kernel...', 0x0D, 0x0A, 0
msg_disk_err db 'DISK ERROR - halting.', 0x0D, 0x0A, 0

; ── 32-bit protected mode entry ───────────────────────
[BITS 32]
protected_mode_start:
    mov ax, DATA_SEG
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov esp, 0x9FFFF            ; stack below kernel load

    jmp KERNEL_OFFSET           ; jump into kernel C entry point

; ── Boot signature ────────────────────────────────────
times 510-($-$$) db 0
dw 0xAA55
