; ===========================================================================
; apps/tm.asm - Timer and Music Demo (SDK v1.1 Test)
; ===========================================================================
[BITS 16]
[ORG 0x0000]

%include "sdk.asm"

    mov  ax, cs
    mov  ds, ax

    newline
    print_str str_hdr, CLR_CYAN
    newline

    ; 1. Test Uptime
    print_str str_up, CLR_NORMAL
    get_uptime           ; Returns CX:DX
    mov  ah, SYS_PRINT_INT32
    syscall
    print_str str_ticks, CLR_NORMAL
    newline

    ; 2. Test File Existence
    print_str str_fe, CLR_NORMAL
    file_exists str_f_tm
    cmp  al, 1
    je   .fe_ok
    print_str str_not_found, CLR_RED
    jmp  .beep_test
.fe_ok:
    print_str str_found, CLR_GREEN
.beep_test:
    newline

    ; 2b. Test 32-bit Print (High:Low)
    print_str str_hex32, CLR_NORMAL
    mov  cx, 0x1234
    mov  dx, 0x5678
    mov  ah, SYS_PRINT_INT32
    syscall
    newline
    newline

    ; 3. Test Melody (C4, E4, G4, C5)
    print_str str_music, CLR_YELLOW
    newline
    
    beep 262, 8          ; C4 (approx 8 ticks = 440ms)
    delay 4
    beep 330, 8          ; E4
    delay 4
    beep 392, 8          ; G4
    delay 4
    beep 523, 16         ; C5
    
    newline
    print_str str_done, CLR_CYAN
    newline
    app_exit

str_hdr:       db ' --- SDK v1.1 Hardware Test ---', 0
str_up:        db ' Uptime: ', 0
str_ticks:     db ' ticks', 0
str_fe:        db ' Checking for self (tm)... ', 0
str_found:     db 'FOUND!', 0
str_not_found: db 'MISSING!', 0
str_f_tm:      db 'tm', 0
str_hex32:     db ' Hex32 Test: ', 0
str_music:     db ' Playing startup melody...', 0
str_done:      db ' Test Complete.', 0
