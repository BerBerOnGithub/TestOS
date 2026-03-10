; ===========================================================================
; core/vbe.asm - VESA/VBE framebuffer initialisation
;
; Must be called in real mode, BEFORE entering protected mode.
; Probes VBE 2.0, scans the mode list for 640x480x8bpp with LFB,
; sets the mode, and saves the framebuffer address + pitch for PM use.
;
; Memory used (below kernel, above BIOS data area):
;   0x7000 - 0x71FF   VbeInfoBlock  (512 bytes)
;   0x7200 - 0x72FF   ModeInfoBlock (256 bytes)
;
; Outputs (readable from PM via flat 32-bit addressing):
;   [vbe_physbase]   dd   physical address of linear framebuffer
;   [vbe_pitch]      dw   bytes per scanline
;   [vbe_width]      dw   horizontal resolution (640)
;   [vbe_height]     dw   vertical resolution   (480)
;   [vbe_bpp]        db   bits per pixel         (8)
;   [vbe_ok]         db   1 = success, 0 = failed (text mode fallback)
;
; ModeInfoBlock offsets (VBE 2.0, OSDev wiki confirmed):
;   +0x00  attributes   (word)  - bit 0x80 = LFB supported
;   +0x10  pitch        (word)  - bytes per scan line
;   +0x12  Xres         (word)
;   +0x14  Yres         (word)
;   +0x19  bpp          (byte)
;   +0x1B  memory_model (byte)  - 4=packed pixel, 6=direct
;   +0x28  physbase     (dword) - LFB physical address
; ===========================================================================

[BITS 16]

VBE_INFO_SEG    equ 0x0700      ; segment for VbeInfoBlock  (phys 0x7000)
VBE_INFO_OFF    equ 0x0000
VBE_MODE_SEG    equ 0x0720      ; segment for ModeInfoBlock (phys 0x7200)
VBE_MODE_OFF    equ 0x0000

VBE_TARGET_W    equ 640
VBE_TARGET_H    equ 480
VBE_TARGET_BPP  equ 8

; ModeInfoBlock field offsets
VBEM_ATTR       equ 0x00
VBEM_PITCH      equ 0x10
VBEM_XRES       equ 0x12
VBEM_YRES       equ 0x14
VBEM_BPP        equ 0x19
VBEM_MODEL      equ 0x1B
VBEM_PHYSBASE   equ 0x28

; ---------------------------------------------------------------------------
; vbe_init
; Call once at boot in real mode.
; Sets vbe_ok=1 and populates vbe_* vars on success.
; Sets vbe_ok=0 and leaves video in text mode on failure.
; Trashes AX, BX, CX, DX, SI, DI, ES. Preserves DS.
; ---------------------------------------------------------------------------
vbe_init:
    push ds

    ; ── Step 1: Get VBE Controller Info (INT 10h AX=4F00h) ───────────────
    ; Write "VBE2" into the buffer first to request VBE 2.0 data
    mov  ax, VBE_INFO_SEG
    mov  es, ax
    mov  di, VBE_INFO_OFF
    mov  word [es:di+0], 'VE'   ; 'VBE2' signature split across two words
    mov  word [es:di+2], 'B2'   ; so NASM doesn't complain about dword imm

    mov  ax, 0x4F00
    int  0x10
    cmp  ax, 0x004F
    jne  .fail

    ; Verify returned signature is 'VESA'
    cmp  word [es:di+0], 'VE'
    jne  .fail
    cmp  word [es:di+2], 'SA'
    jne  .fail

    ; Check version >= 2.0 (at offset 4, word, e.g. 0x0200)
    cmp  word [es:di+4], 0x0200
    jb   .fail

    ; ── Step 2: Get mode list pointer (far ptr at offset 0x0E) ───────────
    ; VideoModePtr is a 32-bit far pointer: low word = offset, high word = segment
    mov  si, [es:di+0x0E]       ; offset
    mov  ax, [es:di+0x10]       ; segment
    mov  ds, ax                 ; DS:SI = mode list

    ; ── Step 3: Walk the mode list ────────────────────────────────────────
.scan_loop:
    lodsw                       ; AX = next mode number, SI advances
    cmp  ax, 0xFFFF             ; end of list sentinel
    je   .fail

    mov  cx, ax                 ; save mode number in CX

    ; Get mode info: INT 10h AX=4F01h, CX=mode, ES:DI=ModeInfoBlock buffer
    push si
    push ds
    mov  ax, VBE_MODE_SEG
    mov  es, ax
    mov  di, VBE_MODE_OFF
    mov  ax, 0x4F01
    int  0x10
    pop  ds
    pop  si

    cmp  ax, 0x004F
    jne  .scan_loop

    ; Check attributes: bit 0 (supported) + bit 3 (colour) +
    ;                   bit 4 (graphics)  + bit 7 (LFB available)
    ; We need 0x80 (LFB) at minimum; OSDev confirms 0x90 = graphics+LFB
    mov  ax, [es:di + VBEM_ATTR]
    and  ax, 0x0090
    cmp  ax, 0x0090
    jne  .scan_loop

    ; Check memory model: 4=packed pixel (256 color), 6=direct color
    mov  al, [es:di + VBEM_MODEL]
    cmp  al, 4
    je   .model_ok
    cmp  al, 6
    je   .model_ok
    jmp  .scan_loop
.model_ok:

    ; Check resolution and bpp
    cmp  word [es:di + VBEM_XRES], VBE_TARGET_W
    jne  .scan_loop
    cmp  word [es:di + VBEM_YRES], VBE_TARGET_H
    jne  .scan_loop
    cmp  byte [es:di + VBEM_BPP],  VBE_TARGET_BPP
    jne  .scan_loop

    ; ── Step 4: Found our mode — save info before setting ─────────────────
    ; Restore DS=0 so we can write to kernel variables
    pop  ds
    push ds                     ; keep DS on stack for final pop

    xor  ax, ax
    mov  ds, ax

    mov  ax, [es:di + VBEM_PITCH]
    mov  [vbe_pitch], ax

    mov  ax, [es:di + VBEM_XRES]
    mov  [vbe_width], ax

    mov  ax, [es:di + VBEM_YRES]
    mov  [vbe_height], ax

    mov  al, [es:di + VBEM_BPP]
    mov  [vbe_bpp], al

    ; physbase is a 32-bit value — read as two words
    mov  ax, [es:di + VBEM_PHYSBASE]
    mov  [vbe_physbase], ax
    mov  ax, [es:di + VBEM_PHYSBASE + 2]
    mov  [vbe_physbase + 2], ax

    ; ── Step 5: Set the mode (INT 10h AX=4F02h, BX=mode|0x4000) ─────────
    ; OR with 0x4000 to select linear framebuffer, bit 15 clear = clear VRAM
    mov  bx, cx
    or   bx, 0x4000
    mov  ax, 0x4F02
    int  0x10
    cmp  ax, 0x004F
    jne  .fail_nodspop
    mov  byte [vbe_ok], 1
    pop  ds
    ret

.fail:
    ; Restore DS=0 (was modified by mode list walk)
    xor  ax, ax
    mov  ds, ax
    pop  ds                     ; pop the original DS push
.fail_nodspop:
    ; VBE failed — fall back to text mode 3
    mov  ax, 0x0003
    int  0x10
    mov  byte [vbe_ok], 0

    ; Print a warning in text mode
    mov  si, vbe_str_fail
    mov  bl, ATTR_RED
    call puts_c
    call nl

    pop  ds
    ret

; ---------------------------------------------------------------------------
; Data — written here, read by PM shell via flat 32-bit physical addressing
; ---------------------------------------------------------------------------
vbe_ok:       db 0
vbe_bpp:      db 0
vbe_width:    dw 0
vbe_height:   dw 0
vbe_pitch:    dw 0
vbe_physbase: dd 0

vbe_str_fail: db ' [VBE] No 640x480x8 LFB mode found. Falling back to text mode.', 0