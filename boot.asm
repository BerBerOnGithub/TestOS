; ===========================================================================
; boot.asm - ClaudeOS Stage 1 Bootloader
;
; El Torito no-emulation with boot-load-size 4 loads 4x512=2048 bytes,
; covering sectors 0-3. Stage2 (at sector 1) is already in memory at
; 0x7E00 when we execute — just save DL and jump.
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

    ; DL = boot drive — pass it to stage2 and jump
    ; Stage2 is already loaded at 0x7E00 by El Torito
    jmp  0x0000:0x7E00

times 510-($-$$) db 0
dw 0xAA55