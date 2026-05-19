; ===========================================================================
; pm/drivers/usb.asm - USB Controller Detection and UHCI Initialization
; ===========================================================================

[BITS 32]

usb_ctrl_found: db 0
usb_ctrl_bus:   db 0
usb_ctrl_dev:   db 0
usb_ctrl_func:  db 0
usb_ctrl_bar4:  dd 0
usb_ctrl_irq:   db 0
usb_running:    db 0

; -
; usb_pci_find: Scans PCI bus for Class 0x0C, Subclass 0x03, ProgIF 0x00 (UHCI).
; Out: AL = 1 if found, 0 if not.
; -
usb_pci_find:
    push ebx
    push ecx
    push edx
    push esi

    mov  byte [usb_ctrl_found], 0
    mov  byte [usb_ctrl_bus], 0
.bus_loop:
    mov  byte [usb_ctrl_dev], 0
.dev_loop:
    mov  byte [usb_ctrl_func], 0
.func_loop:

    ; Check if device exists
    mov  bl, [usb_ctrl_bus]
    mov  bh, [usb_ctrl_dev]
    mov  cl, [usb_ctrl_func]
    mov  ch, 0x00            ; VENDDEV
    call pci_make_addr
    call pci_read32
    cmp  eax, 0xFFFFFFFF
    je   .next_func

    ; Check Class (Offset 0x08)
    mov  bl, [usb_ctrl_bus]
    mov  bh, [usb_ctrl_dev]
    mov  cl, [usb_ctrl_func]
    mov  ch, 0x08
    call pci_make_addr
    call pci_read32
    shr  eax, 8
    and  eax, 0x00FFFFFF     ; EAX = Class:Subclass:ProgIF
    cmp  eax, 0x000C0300     ; 0C=USB, 03=Host Controller, 00=UHCI
    jne  .next_func

    ; Found UHCI
    mov  byte [usb_ctrl_found], 1

    ; Read IRQ (Offset 0x3C)
    mov  bl, [usb_ctrl_bus]
    mov  bh, [usb_ctrl_dev]
    mov  cl, [usb_ctrl_func]
    mov  ch, 0x3C
    call pci_make_addr
    call pci_read32
    mov  [usb_ctrl_irq], al

    ; Read BAR4 (Offset 0x20)
    mov  bl, [usb_ctrl_bus]
    mov  bh, [usb_ctrl_dev]
    mov  cl, [usb_ctrl_func]
    mov  ch, 0x20
    call pci_make_addr
    call pci_read32
    and  eax, 0xFFFFFFFC     ; clear I/O space flag bits
    mov  [usb_ctrl_bar4], eax

    ; Proceed to Init
    call usb_uhci_init
    mov  al, 1
    jmp  .done

.next_func:
    inc  byte [usb_ctrl_func]
    cmp  byte [usb_ctrl_func], 8
    jl   .func_loop

    inc  byte [usb_ctrl_dev]
    cmp  byte [usb_ctrl_dev], 32
    jl   .dev_loop
    inc  byte [usb_ctrl_bus]
    jnz  .bus_loop

    xor  al, al
.done:
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret

; -
; usb_uhci_init: Initialise the controller with an empty frame list.
; -
usb_uhci_init:
    pusha

    mov  dx, word [usb_ctrl_bar4]
    
    ; 1. Global Reset (USBCMD = 0x0004)
    mov  ax, 0x0004
    out  dx, ax

    ; Delay 12ms
    mov  eax, 12
    call pm_delay_ms

    ; Deassert reset
    mov  dx, word [usb_ctrl_bar4]
    mov  ax, 0x0000
    out  dx, ax

    ; 2. Allocate Frame List at 0x250000 and fill with terminate bit (1)
    mov  edi, 0x250000
    mov  ecx, 1024
    mov  eax, 0x00000001
    rep  stosd

    ; 3. Clear Status (USBSTS = 0x001F)
    add  dx, 2
    mov  ax, 0x001F
    out  dx, ax

    ; 4. Set Frame Number to 0 (FRNUM = 0x0000)
    add  dx, 4
    mov  ax, 0x0000
    out  dx, ax

    ; 5. Set Frame List Base (FLBASEADD = 0x00250000)
    add  dx, 2
    mov  eax, 0x00250000
    out  dx, eax

    ; 6. Disable Interrupts (USBINTR = 0x0000)
    sub  dx, 4
    mov  ax, 0x0000
    out  dx, ax

    ; 7. Run/Stop (USBCMD = 0x0001)
    sub  dx, 4
    mov  ax, 0x0001
    out  dx, ax

    ; 8. Verify running
    add  dx, 2
    in   ax, dx
    test ax, 0x0020
    jnz  .halted
    
    mov  byte [usb_running], 1
.halted:
    popa
    ret

; -
; cmd_usbinfo - dump controller info to shell
; -
cmd_usbinfo:
    pusha
    call pm_newline

    cmp  byte [usb_ctrl_found], 1
    je   .found
    
    mov  esi, str_no_usb
    mov  bl, 0x0C
    call pm_puts
    call pm_newline
    popa
    ret

.found:
    mov  esi, str_usb_inf1
    mov  bl, 0x0B
    call pm_puts

    mov  al, [usb_ctrl_bus]
    call pm_print_hex8
    mov  al, ':'
    mov  bl, 0x07
    call pm_putc
    mov  al, [usb_ctrl_dev]
    call pm_print_hex8

    mov  esi, str_usb_inf2
    mov  bl, 0x07
    call pm_puts

    mov  eax, [usb_ctrl_bar4]
    call pm_print_hex32

    mov  esi, str_usb_inf3
    call pm_puts

    mov  al, [usb_ctrl_irq]
    call pm_print_hex8

    mov  esi, str_usb_run
    mov  bl, 0x0A
    cmp  byte [usb_running], 1
    je   .print_state
    mov  esi, str_usb_halt
    mov  bl, 0x0C
.print_state:
    call pm_puts
    call pm_newline
    popa
    ret

str_no_usb:   db ' No USB controller found.', 0
str_usb_inf1: db ' USB Controller: UHCI  Bus:', 0
str_usb_inf2: db '  I/O base: 0x', 0
str_usb_inf3: db '  IRQ: 0x', 0
str_usb_run:  db '  [RUNNING]', 0
str_usb_halt: db '  [HALTED]', 0
