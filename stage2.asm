; ===========================================================================
; stage2.asm - ClaudeOS Stage 2 Bootloader
;
; Loaded by Stage 1 at 0x0000:0x7E00.
; Loads:
;   Kernel  (sectors 4..4+KERNEL_SECTORS-1)  → 0x0000:0x8000
;   FS blob (sectors after kernel)            → 0x2000:0x0000 = 0x20000
;
; Kernel is told the FS segment in DX before the far jump.
;
; Memory layout:
;   Sector 1            = Stage 1 (MBR)
;   Sectors 2-3         = Stage 2 (this file)
;   Sectors 4..4+K-1    = Kernel  (KERNEL_SECTORS)
;   Sectors 4+K..       = FS blob (fs.bin)
; ===========================================================================

[BITS 16]
[ORG 0x7E00]

KERNEL_SECTORS   equ 200     ; 100KB  — bump if kernel grows
FS_SECTORS       equ 64      ; 32KB   — bump if apps folder grows
KERNEL_START_LBA equ 3       ; LBA 3  = physical sector 4
FS_START_LBA     equ KERNEL_START_LBA + KERNEL_SECTORS

stage2_start:
    mov  [boot_drive], dl

    mov  si, msg_load_kernel
    call puts

    ; --- load kernel into 0x0000:0x8000 ---
    mov  ax, 0x0800
    mov  es, ax
    mov  word [lba],    KERNEL_START_LBA
    mov  word [remain], KERNEL_SECTORS
    call load_sectors
    jc   .error

    mov  si, msg_load_fs
    call puts

    ; --- load fs.bin into 0x2000:0x0000 = physical 0x20000 ---
    mov  ax, 0x2000
    mov  es, ax
    mov  word [lba],    FS_START_LBA
    mov  word [remain], FS_SECTORS
    call load_sectors
    jc   .error

    mov  si, msg_ok
    call puts

    ; pass boot drive in DL, FS segment in AX (kernel reads from [fs_seg])
    mov  dl, [boot_drive]
    mov  ax, 0x2000          ; FS segment — kernel saves this
    jmp  0x0000:0x8000

.error:
    mov  [err_code], ah
    mov  si, msg_error
    call puts
    mov  al, [err_code]
    call print_hex
    mov  si, msg_crlf
    call puts
    mov  si, msg_lba
    call puts
    mov  ax, [lba]
    call print_dec
    mov  si, msg_c
    call puts
    mov  al, [cyl]
    xor  ah, ah
    call print_dec
    mov  si, msg_h
    call puts
    mov  al, [hd]
    xor  ah, ah
    call print_dec
    mov  si, msg_s
    call puts
    mov  al, [sec]
    xor  ah, ah
    call print_dec
    mov  si, msg_crlf
    call puts
    cli
    hlt

; ---------------------------------------------------------------------------
; load_sectors — read [remain] sectors starting at [lba] into ES:0
;                one sector at a time (bulletproof vs DMA boundary)
; Returns: CF=0 ok, CF=1 error (AH=BIOS error code)
; Trashes: AX BX CX DX
; ---------------------------------------------------------------------------
load_sectors:
.loop:
    cmp  word [remain], 0
    je   .ok

    ; LBA to CHS
    mov  ax, [lba]
    xor  dx, dx
    mov  bx, 18
    div  bx
    inc  dx
    mov  [sec], dl
    xor  dx, dx
    mov  bx, 2
    div  bx
    mov  [cyl], al
    mov  [hd],  dl

    ; read one sector
    xor  bx, bx
    mov  ah, 0x02
    mov  al, 1
    mov  ch, [cyl]
    mov  cl, [sec]
    mov  dh, [hd]
    mov  dl, [boot_drive]
    int  0x13
    jc   .err

    add  word [lba],    1
    sub  word [remain], 1

    ; advance ES by 32 paragraphs (512 bytes)
    mov  ax, es
    add  ax, 32
    mov  es, ax

    jmp  .loop
.ok:
    clc
    ret
.err:
    stc
    ret

; ---------------------------------------------------------------------------
; print_hex — print AL as two hex digits
; ---------------------------------------------------------------------------
print_hex:
    push ax
    push bx
    push cx
    mov  ch, al
    shr  al, 4
    call .nibble
    mov  al, ch
    and  al, 0x0F
    call .nibble
    pop  cx
    pop  bx
    pop  ax
    ret
.nibble:
    cmp  al, 10
    jb   .digit
    add  al, 'A' - 10
    jmp  .put
.digit:
    add  al, '0'
.put:
    mov  ah, 0x0E
    xor  bx, bx
    int  0x10
    ret

; ---------------------------------------------------------------------------
; print_dec — print AX as unsigned decimal
; ---------------------------------------------------------------------------
print_dec:
    push ax
    push bx
    push cx
    push dx
    mov  bx, 10
    xor  cx, cx
.push_loop:
    xor  dx, dx
    div  bx
    push dx
    inc  cx
    test ax, ax
    jnz  .push_loop
.pop_loop:
    pop  dx
    mov  al, dl
    add  al, '0'
    mov  ah, 0x0E
    xor  bx, bx
    int  0x10
    loop .pop_loop
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; puts — print null-terminated string at DS:SI
; ---------------------------------------------------------------------------
puts:
    push ax
    push bx
.lp:
    lodsb
    or   al, al
    jz   .done
    mov  ah, 0x0E
    xor  bx, bx
    int  0x10
    jmp  .lp
.done:
    pop  bx
    pop  ax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
boot_drive: db 0
lba:        dw 0
remain:     dw 0
sec:        db 0
cyl:        db 0
hd:         db 0
err_code:   db 0

msg_load_kernel: db 'Loading kernel...', 13, 10, 0
msg_load_fs:     db 'Loading filesystem...', 13, 10, 0
msg_ok:          db 'Starting ClaudeOS...', 13, 10, 0
msg_error:       db 13, 10, 'FATAL: error code: 0x', 0
msg_crlf:        db 13, 10, 0
msg_lba:         db ' LBA=', 0
msg_c:           db ' C=', 0
msg_h:           db ' H=', 0
msg_s:           db ' S=', 0