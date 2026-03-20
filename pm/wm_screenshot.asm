; ===========================================================================
; pm/wm_screenshot.asm  -  PrtSc screenshot to BMP on data disk
;
; Uses shadow framebuffer (GFX_SHADOW at 0x500000) - no MMIO reads needed.
;
; Phase 1 (PrtSc keypress):
;   wm_screenshot_capture - copies GFX_SHADOW -> 0x600000, sets scr_pending=1
;
; Phase 2 (user types "savescr"):
;   pm_cmd_savescr in pm_commands.asm - builds BMP from 0x600000, writes to disk
;
; BMP format (8bpp indexed):
;   14 bytes  BITMAPFILEHEADER
;   40 bytes  BITMAPINFOHEADER
; 1024 bytes  256-colour palette (from VGA DAC)
; 307200 bytes pixel data (BMP bottom-up = reverse row order)
; Total: 308278 bytes
; ===========================================================================

[BITS 32]
SCR_BUF     equ 0x300000
SCR_CAPTURE equ 0x600000
SCR_W       equ 640
SCR_H       equ 480
SCR_PIX     equ 307200
BMP_HDR_SZ  equ 1078
BMP_FILE_SZ equ 308278

; -
; wm_screenshot_capture
; Called on PrtSc. Copies GFX_SHADOW (RAM) -> 0x600000.
; Fast RAM->RAM copy. No MMIO involved.
; -
wm_screenshot_capture:
    pusha

    ; capture shadow -> 0x600000
    mov  esi, GFX_SHADOW
    mov  edi, 0x600000
    mov  ecx, 76800
    rep  movsd

    mov  byte [scr_pending], 1

    cmp  byte [bd_ready], 1
    jne  .done
    mov  esi, scr_msg_ok_cap
    call wm_notify
.done:
    popa
    ret

wm_notify:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    pop  esi
    push esi
    mov  [notify_msg], esi
    mov  eax, [pit_ticks]
    add  eax, 300
    mov  [notify_expire], eax
    mov  eax, 4
    mov  ebx, WM_TASKBAR_Y - 20
    mov  ecx, 220
    mov  edx, 16
    mov  esi, 0x01
    call fb_fill_rect
    mov  esi, [notify_msg]
    mov  ebx, 8
    mov  ecx, WM_TASKBAR_Y - 16
    mov  dl,  0x0F
    mov  dh,  0x01
    call fb_draw_string
    call gfx_flush
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; -
; wm_notify_tick - call from wm_update_contents each tick
; -
wm_notify_tick:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    cmp  dword [notify_expire], 0
    je   .done
    mov  eax, [pit_ticks]
    cmp  eax, [notify_expire]
    jl   .done
    mov  dword [notify_expire], 0
    mov  dword [notify_msg], 0
    mov  eax, 4
    mov  ebx, WM_TASKBAR_Y - 20
    mov  ecx, 220
    mov  edx, 16
    mov  esi, WM_C_BODY
    call fb_fill_rect
    call wm_draw_all
.done:
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; -
; Data
; -
notify_expire:   dd 0
notify_msg:      dd 0
; -
; scr_counter_init - scan fsd_dir_buf for highest scrNNNN and seed counter
; -
scr_counter_init:
    push eax
    push ebx
    push ecx
    push esi

    mov  dword [scr_counter], 0
    cmp  byte [fsd_ready], 1
    jne  .done

    mov  esi, fsd_dir_buf
    mov  ecx, FSD_MAX_ENT
.scan:
    test ecx, ecx
    jz   .done
    cmp  dword [esi + 24], FSD_FLAG_USED
    jne  .next

    ; check if name starts with "scr" and has 4 digits after
    cmp  byte [esi + 0], 0x73   ; s
    jne  .next
    cmp  byte [esi + 1], 0x63   ; c
    jne  .next
    cmp  byte [esi + 2], 0x72   ; r
    jne  .next

    ; parse 4-digit number from bytes 3-6
    movzx eax, byte [esi + 3]
    sub  eax, 0x30
    imul eax, 1000
    movzx ebx, byte [esi + 4]
    sub  ebx, 0x30
    imul ebx, 100
    add  eax, ebx
    movzx ebx, byte [esi + 5]
    sub  ebx, 0x30
    imul ebx, 10
    add  eax, ebx
    movzx ebx, byte [esi + 6]
    sub  ebx, 0x30
    add  eax, ebx

    cmp  eax, [scr_counter]
    jle  .next
    mov  [scr_counter], eax

.next:
    add  esi, FSD_ENT_SZ
    dec  ecx
    jmp  .scan

.done:
    pop  esi
    pop  ecx
    pop  ebx
    pop  eax
    ret

scr_counter:     dd 0
scr_name:        db 'scr0001', 0
scr_msg_ok_cap:  db 'Screenshot captured! Type savescr to save.', 0
scr_msg_ok_save: db 'Screenshot saved!', 0
scr_msg_full:    db 'Data disk full!', 0
scr_msg_nodisk:  db 'No data disk attached', 0
