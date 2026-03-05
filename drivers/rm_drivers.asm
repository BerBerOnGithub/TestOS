; ===========================================================================
; drivers/rm_drivers.asm - Real-mode driver registry
;
; Provides:
;   drv_rm_init      - called at boot, initialises all RM drivers
;   drv_rm_shutdown  - called before switching to PM, shuts down RM drivers
;   cmd_drivers      - shell command: list loaded drivers and status
;
; RM drivers:
;   [0] Screen   - BIOS INT 10h VGA text output
;   [1] Keyboard - BIOS INT 16h PS/2 input
;   [2] RTC      - BIOS INT 1Ah real-time clock
;   [3] Speaker  - PIT channel 2 + port 0x61 PC speaker
; ===========================================================================

[BITS 16]

; ---------------------------------------------------------------------------
; Driver status table  (1 byte per driver: 1=loaded, 0=unloaded)
; ---------------------------------------------------------------------------
drv_rm_status:
    db 0    ; 0 Screen
    db 0    ; 1 Keyboard
    db 0    ; 2 RTC
    db 0    ; 3 Speaker

DRV_RM_COUNT equ 4

; ---------------------------------------------------------------------------
; drv_rm_init - initialise all real-mode drivers at boot
; ---------------------------------------------------------------------------
drv_rm_init:
    push ax
    push bx
    push dx

    ; ── Driver 0: Screen ─────────────────────────────────────────────────
    ; Set VGA text mode 3 (80x25, 16 colour) to ensure clean state
    mov  ah, 0x00
    mov  al, 0x03
    int  0x10
    ; home cursor
    mov  ah, 0x02
    xor  bh, bh
    xor  dx, dx
    int  0x10
    mov  byte [drv_rm_status + 0], 1

    ; ── Driver 1: Keyboard ───────────────────────────────────────────────
    ; Flush any stale keystrokes from the BIOS buffer
.kbd_flush:
    mov  ah, 0x01
    int  0x16
    jz   .kbd_done
    xor  ah, ah
    int  0x16
    jmp  .kbd_flush
.kbd_done:
    mov  byte [drv_rm_status + 1], 1

    ; ── Driver 2: RTC ────────────────────────────────────────────────────
    ; Just verify INT 1Ah responds — nothing to program
    mov  ah, 0x02
    int  0x1A
    mov  byte [drv_rm_status + 2], 1

    ; ── Driver 3: Speaker ────────────────────────────────────────────────
    ; Ensure speaker gate is off (bits 0+1 of port 0x61 cleared)
    in   al, 0x61
    and  al, 0xFC
    out  0x61, al
    mov  byte [drv_rm_status + 3], 1

    pop  dx
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; drv_rm_shutdown - cleanly shut down all real-mode drivers before PM switch
; ---------------------------------------------------------------------------
drv_rm_shutdown:
    push ax

    ; ── Driver 3: Speaker — ensure it's off ──────────────────────────────
    in   al, 0x61
    and  al, 0xFC
    out  0x61, al
    mov  byte [drv_rm_status + 3], 0

    ; ── Driver 2: RTC — nothing to teardown ──────────────────────────────
    mov  byte [drv_rm_status + 2], 0

    ; ── Driver 1: Keyboard — flush buffer ────────────────────────────────
.flush:
    mov  ah, 0x01
    int  0x16
    jz   .flush_done
    xor  ah, ah
    int  0x16
    jmp  .flush
.flush_done:
    mov  byte [drv_rm_status + 1], 0

    ; ── Driver 0: Screen — mark unloaded (PM will take over VGA directly) ─
    mov  byte [drv_rm_status + 0], 0

    pop  ax
    ret

; ---------------------------------------------------------------------------
; cmd_drivers - display real-mode driver status table
; ---------------------------------------------------------------------------
cmd_drivers:
    push ax
    push bx
    push si

    call nl
    mov  si, str_drv_hdr
    mov  bl, ATTR_CYAN
    call puts_c

    ; Screen
    mov  si, str_drv_screen
    mov  bl, ATTR_YELLOW
    call puts_c
    mov  al, [drv_rm_status + 0]
    call .print_status

    ; Keyboard
    mov  si, str_drv_kbd
    mov  bl, ATTR_YELLOW
    call puts_c
    mov  al, [drv_rm_status + 1]
    call .print_status

    ; RTC
    mov  si, str_drv_rtc
    mov  bl, ATTR_YELLOW
    call puts_c
    mov  al, [drv_rm_status + 2]
    call .print_status

    ; Speaker
    mov  si, str_drv_spk
    mov  bl, ATTR_YELLOW
    call puts_c
    mov  al, [drv_rm_status + 3]
    call .print_status

    mov  si, str_drv_footer
    mov  bl, ATTR_CYAN
    call puts_c
    call nl

    pop  si
    pop  bx
    pop  ax
    jmp  shell_exec.done

.print_status:
    cmp  al, 1
    je   .loaded
    mov  si, str_drv_unloaded
    mov  bl, ATTR_RED
    call puts_c
    ret
.loaded:
    mov  si, str_drv_loaded
    mov  bl, ATTR_GREEN
    call puts_c
    ret

; ---------------------------------------------------------------------------
; Strings
; ---------------------------------------------------------------------------
str_drv_hdr:
    db 13, 10
    db ' +--------------------+----------+', 13, 10
    db ' | Driver             | Status   |', 13, 10
    db ' +--------------------+----------+', 13, 10, 0
str_drv_footer:
    db ' +--------------------+----------+', 0
str_drv_screen:   db ' | Screen (INT 10h)   | ', 0
str_drv_kbd:      db ' | Keyboard (INT 16h) | ', 0
str_drv_rtc:      db ' | RTC (INT 1Ah)      | ', 0
str_drv_spk:      db ' | Speaker (PIT ch.2) | ', 0
str_drv_loaded:   db 'LOADED   |', 13, 10, 0
str_drv_unloaded: db 'UNLOADED |', 13, 10, 0