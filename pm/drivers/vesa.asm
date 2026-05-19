; ===========================================================================
; pm/drivers/vesa.asm - Protected-Mode VESA driver
;
; Provides a PM-side interface to VESA/VBE, using pm_bios_call to drop
; to real mode for INT 10h when needed.  The VBE mode was already set
; in real mode by core/vbe.asm; this driver re-validates the framebuffer
; address and provides helpers for mode queries and palette programming.
;
; Two-tier design:
;   Tier 1 (primary)   - VESA: confirm LFB via pm_bios_call INT 10h 4F01h
;   Tier 2 (fallback)  - VBE:  use vbe_physbase set by core/vbe.asm
;
; After vesa_init the following variables are reliable from PM:
;   vesa_fb_phys  dd  physical address of linear framebuffer
;   vesa_pitch    dw  bytes per scan line
;   vesa_width    dw  horizontal resolution
;   vesa_height   dw  vertical resolution
;   vesa_bpp      db  bits per pixel
;   vesa_mode     dw  active VBE mode number (or 0xFFFF if unknown)
;   vesa_ok       db  1 = driver up, 0 = failed (text mode only)
;
; Public:
;   vesa_init            - call once after PM entry (before gfx_init)
;   vesa_set_palette     - program DAC; ESI=ptr to R,G,B bytes, ECX=count,
;                          EBX=start index
;   vesa_get_mode_info   - CX=mode -> fills vesa_mib buffer, CF=1 on fail
; ===========================================================================

[BITS 32]

; ---- Low-memory scratch for RM bounce buffer ----
; We reuse the ModeInfoBlock area core/vbe.asm left at 0x7200
; (256 bytes, already written but still readable).
VESA_MIB_PHYS   equ 0x7200      ; physical address of ModeInfoBlock in low RAM
VESA_MIB_LIN    equ 0x7200      ; same value (identity mapped below 1MB)

; ModeInfoBlock field offsets (VBE 2.0)
VMIB_ATTR       equ 0x00        ; word  - mode attributes
VMIB_PITCH      equ 0x10        ; word  - bytes per scan line
VMIB_XRES       equ 0x12        ; word  - X resolution
VMIB_YRES       equ 0x14        ; word  - Y resolution
VMIB_BPP        equ 0x19        ; byte  - bits per pixel
VMIB_MODEL      equ 0x1B        ; byte  - memory model
VMIB_PHYSBASE   equ 0x28        ; dword - LFB physical address

; RM_REGS_ADDR is defined in core/mode_switch.asm as 0x1000
; Layout: EAX+0 EBX+4 ECX+8 EDX+12 ESI+16 EDI+20 DS+24 ES+26 FLG+28 INT+30

; -
; vesa_init
; Tries to re-validate the framebuffer address via pm_bios_call.
; Falls back to vbe_physbase from core/vbe.asm if that fails.
; -
vesa_init:
    pusha

    ; - guard: if core/vbe.asm already failed, nothing we can do -
    cmp  byte [vbe_ok], 1
    jne  .tier2_fallback

    ; ---- Tier 1: Re-validate the mode found at boot (vbe_mode) ----
    movzx eax, word [vbe_mode]
    mov  [vesa_mode], eax

    mov  cx, [vbe_mode]
    call vesa_get_mode_info
    jc   .tier2_fallback

    ; validate LFB attribute (bit 7 of attributes word)

    mov  ax, [VESA_MIB_LIN + VMIB_ATTR]
    test ax, 0x0080
    jz   .tier2_fallback

    ; read fresh values from MIB
    movzx eax, word [VESA_MIB_LIN + VMIB_PITCH]
    mov  [vesa_pitch], eax

    movzx eax, word [VESA_MIB_LIN + VMIB_XRES]
    mov  [vesa_width], eax

    movzx eax, word [VESA_MIB_LIN + VMIB_YRES]
    mov  [vesa_height], eax

    mov  al, [VESA_MIB_LIN + VMIB_BPP]
    mov  [vesa_bpp], al

    mov  eax, [VESA_MIB_LIN + VMIB_PHYSBASE]
    mov  [vesa_fb_phys], eax

    ; sanity: physbase must be above 1MB
    cmp  eax, 0x100000
    jb   .tier2_fallback

    mov  byte [vesa_ok], 1
    mov  byte [vesa_tier], 1
    jmp  .done_success

    ; ---- Tier 2: fall back to values core/vbe.asm already set ----
.tier2_fallback:
    push esi
    mov  esi, vesa_str_unable
    call serial_print
    pop  esi

    cmp  byte [vbe_ok], 1
    jne  .hard_fail

    mov  eax, [vbe_physbase]
    cmp  eax, 0x100000
    jb   .hard_fail

    mov  [vesa_fb_phys], eax

    movzx eax, word [vbe_pitch]
    mov  [vesa_pitch], eax

    movzx eax, word [vbe_width]
    mov  [vesa_width], eax

    movzx eax, word [vbe_height]
    mov  [vesa_height], eax

    mov  al, [vbe_bpp]
    mov  [vesa_bpp], al

    mov  dword [vesa_mode], 0xFFFF   ; unknown mode number in fallback
    mov  byte [vesa_ok], 1
    mov  byte [vesa_tier], 2

.done_success:
.done:
    popa
    ret

.hard_fail:
    mov  byte [vesa_ok], 0
    mov  byte [vesa_tier], 0
    jmp  .done


; -
; vesa_get_mode_info
; In:  CX = VBE mode number
; Out: ModeInfoBlock written to VESA_MIB_LIN (0x7200)
;      CF=0 success, CF=1 fail
; Preserves all registers except flags.
; -
vesa_get_mode_info:
    pusha

    ; INT 10h, AX=4F01h, CX=mode, ES:DI -> ModeInfoBlock buffer
    ; ES:DI = 0x0720:0x0000 -> physical 0x7200
    mov  dword [0x1000 +  0], 0x00004F01    ; EAX
    mov  dword [0x1000 +  4], 0             ; EBX
    movzx eax, cx
    mov  dword [0x1000 +  8], eax           ; ECX = mode
    mov  dword [0x1000 + 12], 0             ; EDX
    mov  dword [0x1000 + 16], 0             ; ESI
    mov  dword [0x1000 + 20], 0             ; EDI = 0x0000
    mov  word  [0x1000 + 24], 0             ; DS  = 0
    mov  word  [0x1000 + 26], 0x0720        ; ES  = 0x0720 (phys 0x7200)
    mov  al, 0x10
    call pm_bios_call

    ; check AX == 0x004F
    mov  eax, [0x1000 + 0]
    and  eax, 0xFFFF
    cmp  eax, 0x004F
    jne  .gmi_fail

    popa
    clc
    ret
.gmi_fail:
    popa
    stc
    ret

; -
; vesa_set_palette
; Programs DAC entries via direct VGA ports (no BIOS needed, works in PM).
; In:  ESI = pointer to palette data (triplets: R, G, B each 0-63)
;      ECX = number of entries
;      EBX = start index (0-255)
; Preserves all registers.
; -
vesa_set_palette:
    push eax
    push ecx
    push edx
    push esi

    mov  dx, 0x3C8
    mov  al, bl             ; start index
    out  dx, al
    mov  dx, 0x3C9
.vsp_loop:
    test ecx, ecx
    jz   .vsp_done
    outsb                   ; R
    outsb                   ; G
    outsb                   ; B
    dec  ecx
    jmp  .vsp_loop
.vsp_done:
    pop  esi
    pop  edx
    pop  ecx
    pop  eax
    ret

; -
; vesa_print_info
; Prints VESA driver status to the PM text console (uses pm_print_string).
; -
vesa_print_info:
    pusha
    cmp  byte [vesa_ok], 1
    jne  .fail

    movzx eax, byte [vesa_tier]
    cmp  al, 1
    je   .t1
    mov  esi, vesa_str_tier2
    jmp  .print_tier
.t1:
    mov  esi, vesa_str_tier1
.print_tier:
    mov  bl, 0x0F
    call pm_puts

    ; print resolution: WxHxBPP
    mov  eax, [vesa_width]
    call pm_print_uint
    mov  esi, vesa_str_x
    mov  bl, 0x0F
    call pm_puts
    mov  eax, [vesa_height]
    call pm_print_uint
    mov  esi, vesa_str_x
    mov  bl, 0x0F
    call pm_puts
    movzx eax, byte [vesa_bpp]
    call pm_print_uint
    mov  esi, vesa_str_bpp
    mov  bl, 0x0F
    call pm_puts

    ; print framebuffer physical address
    mov  esi, vesa_str_fb
    mov  bl, 0x0F
    call pm_puts
    mov  eax, [vesa_fb_phys]
    call pm_print_hex32
    mov  esi, vesa_str_nl
    mov  bl, 0x0F
    call pm_puts
    jmp  .done
.fail:
    mov  esi, vesa_str_fail
    mov  bl, 0x0C
    call pm_puts
.done:
    popa
    ret

; ---- driver variables ----
vesa_ok:       db 0
vesa_tier:     db 0         ; 1=VESA re-validated, 2=VBE fallback, 0=none
vesa_bpp:      db 0
vesa_mode:     dd 0xFFFF
vesa_width:    dd 0
vesa_height:   dd 0
vesa_pitch:    dd 0
vesa_fb_phys:  dd 0

; ---- strings ----
vesa_str_tier1: db '[VESA] Tier-1 (BIOS re-validated LFB)  ', 0
vesa_str_tier2: db '[VESA] Tier-2 (VBE boot-time fallback)  ', 0
vesa_str_fail:  db '[VESA] No framebuffer available!', 13, 10, 0
vesa_str_x:     db 'x', 0
vesa_str_bpp:   db 'bpp  ', 0
vesa_str_fb:    db 'FB @ 0x', 0
vesa_str_nl:    db 13, 10, 0
vesa_str_unable: db 'unable to use vesa', 13, 10, 0
