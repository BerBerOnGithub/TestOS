[BITS 32]

; ─────────────────────────────────────────────────────
;  kernel_entry.asm
;  Linked first. Sets up a C-compatible stack and calls kmain().
; ─────────────────────────────────────────────────────

global _start
extern kmain

section .text
_start:
    mov esp, 0x9FFFF    ; top of usable low memory
    call kmain
    ; kmain should never return, but just in case:
.hang:
    cli
    hlt
    jmp .hang
