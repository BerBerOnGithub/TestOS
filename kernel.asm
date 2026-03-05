; ===========================================================================
; kernel.asm - ClaudeOS Kernel v2.0
;
; Entry point only. Components are %included in two sections:
;
;   16-bit real mode (BIOS-based)
;   ├── core/        hardware abstractions (screen, keyboard, string, utils)
;   ├── drivers/     real-mode driver registry (screen, kbd, rtc, speaker)
;   ├── shell/       prompt, readline, command dispatcher
;   └── commands/    built-in commands + all string data
;
;   32-bit protected mode (no BIOS)
;   └── pm/          PM shell, VGA/kbd/PIT drivers, PM driver registry
;
; Boot flow:
;   kernel_main → drv_rm_init → real-mode shell
;   "pm" command → drv_rm_shutdown → [switch] → pm_drv_init → PM shell
;   "exit" in PM → pm_drv_shutdown → [switch] → drv_rm_init → real-mode shell
;
; Assemble: nasm -f bin -o kernel.bin kernel.asm
; ===========================================================================

[BITS 16]
[ORG 0x8000]

; ---------------------------------------------------------------------------
; Constants (available to all included files)
; ---------------------------------------------------------------------------
ATTR_NORMAL   equ 0x07
ATTR_BRIGHT   equ 0x0F
ATTR_GREEN    equ 0x0A
ATTR_YELLOW   equ 0x0E
ATTR_CYAN     equ 0x0B
ATTR_RED      equ 0x0C
ATTR_MAGENTA  equ 0x0D

FORTUNE_COUNT equ 10

; ---------------------------------------------------------------------------
; Kernel entry point
; ---------------------------------------------------------------------------
kernel_main:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7BF0
    sti

    ; Save boot tick count for uptime
    xor  ah, ah
    int  0x1A
    mov  [boot_ticks_hi], cx
    mov  [boot_ticks_lo], dx

    ; Initialise real-mode drivers
    call drv_rm_init

    call screen_clear
    call show_banner
    call show_motd

.shell:
    call shell_prompt
    call shell_readline
    call shell_exec
    jmp  .shell

    cli
    hlt

; ---------------------------------------------------------------------------
; 16-bit components  [BITS 16]
; ---------------------------------------------------------------------------
%include "core/screen.asm"
%include "core/string.asm"
%include "core/keyboard.asm"
%include "core/utils.asm"
%include "drivers/rm_drivers.asm"
%include "shell/shell.asm"
%include "commands/cmd_basic.asm"
%include "commands/cmd_system.asm"
%include "commands/cmd_tools.asm"
%include "commands/cmd_fun.asm"
%include "commands/data.asm"

; ---------------------------------------------------------------------------
; 32-bit components  [BITS 32]  (included last — never reached by 16-bit flow)
; ---------------------------------------------------------------------------
%include "pm/pm_shell.asm"