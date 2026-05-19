; ===========================================================================
; pm/core/panic.asm - Kernel Panic / BSOD Renderer
; ===========================================================================
[BITS 32]

; - panic_screen -
; EAX = vector, EBX = error code, ESI = faulting address (CR2)
; -
panic_screen:
    cli                     ; ensure no interrupts interfere

    ; Save inputs
    mov  [.vec], eax
    mov  [.err], ebx
    mov  [.cr2], esi

    ; 1. Fill entire screen with Black
    mov  edi, [vbe_physbase]
    test edi, edi
    jz   .no_gfx

    mov  ecx, (640 * 480) / 4
    xor  eax, eax              ; Index 0 = Black
    rep  stosd

    ; 2. Draw header bar (full width, 18px tall, dark gray = index 8)
    mov  edi, [vbe_physbase]
    mov  ecx, 640 * 18
    mov  al, 0x08
    rep  stosb

    ; 3. Cyan accent stripe on left edge (x=0..3, full height)
    mov  ebx, 0                ; row counter
.stripe_loop:
    cmp  ebx, 480
    jge  .stripe_done
    mov  edi, [vbe_physbase]
    mov  eax, ebx
    imul eax, 640
    add  edi, eax
    mov  byte [edi+0], 0x03
    mov  byte [edi+1], 0x03
    mov  byte [edi+2], 0x03
    inc  ebx
    jmp  .stripe_loop
.stripe_done:

    ; 4. Cyan separator line under header (y=19)
    mov  edi, [vbe_physbase]
    add  edi, 19 * 640
    mov  ecx, 640
    mov  al, 0x03
    rep  stosb

    ; 5. Dark gray box at bottom for tech info (y=440..479)
    mov  edi, [vbe_physbase]
    add  edi, 440 * 640
    mov  ecx, (640 * 40) / 4
    mov  eax, 0x08080808
    rep  stosd

    ; Cyan separator line above tech box (y=439)
    mov  edi, [vbe_physbase]
    add  edi, 439 * 640
    mov  ecx, 640
    mov  al, 0x03
    rep  stosb

    ; 6. Draw header text
    ;    "NatureOS" in yellow at x=8, y=5
    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 5
    mov  byte  [.fg], 0x0E    ; Yellow
    mov  esi, .s_osname
    call .puts

    ;    "KERNEL PANIC" in light red at x=200, y=5
    mov  dword [.cur_x], 200
    mov  dword [.cur_y], 5
    mov  byte  [.fg], 0x0C    ; Light Red
    mov  esi, .s_panic_hdr
    call .puts

    ;    right-aligned marker: "[!!]" in yellow at x=600, y=5
    mov  dword [.cur_x], 600
    mov  dword [.cur_y], 5
    mov  byte  [.fg], 0x0E
    mov  esi, .s_bang
    call .puts

    ; 7. Look up per-exception strings by vector
    mov  eax, [.vec]
    call .lookup_exc          ; sets .p_name, .p_msg1, .p_msg2, .p_msg3, .p_hint

    ; Exception name in white, x=8 y=30
    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 30
    mov  byte  [.fg], 0x0F    ; White
    mov  esi, .s_exc_label
    call .puts
    mov  byte  [.fg], 0x0C    ; Light Red
    mov  esi, [.p_name]
    call .puts

    ; 8. Body text in light gray
    mov  byte  [.fg], 0x07    ; Light Gray
    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 50
    mov  esi, [.p_msg1]
    call .puts

    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 62
    mov  esi, [.p_msg2]
    call .puts

    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 74
    mov  esi, [.p_msg3]
    call .puts

    ; 9. "What to do" section
    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 100
    mov  byte  [.fg], 0x0B    ; Light Cyan
    mov  esi, .s_whattodo
    call .puts

    mov  byte  [.fg], 0x07    ; Light Gray
    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 114
    mov  esi, [.p_hint]
    call .puts

    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 126
    mov  esi, .s_step_reboot
    call .puts

    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 138
    mov  esi, .s_step_hw
    call .puts

    ; 10. Tech info box
    ;     Header label in light cyan
    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 446
    mov  byte  [.fg], 0x0B    ; Light Cyan
    mov  esi, .s_tech_hdr
    call .puts

    ;     Vector
    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 460
    mov  byte  [.fg], 0x07    ; Light gray label
    mov  esi, .s_vec_lbl
    call .puts
    mov  byte  [.fg], 0x0F    ; White value
    mov  eax, [.vec]
    call .puthex8

    ;     Error code
    mov  dword [.cur_x], 160
    mov  dword [.cur_y], 460
    mov  byte  [.fg], 0x07
    mov  esi, .s_err_lbl
    call .puts
    mov  byte  [.fg], 0x0F
    mov  eax, [.err]
    call .puthex32

    ;     CR2
    mov  dword [.cur_x], 336
    mov  dword [.cur_y], 460
    mov  byte  [.fg], 0x07
    mov  esi, .s_cr2_lbl
    call .puts
    mov  byte  [.fg], 0x0F
    mov  eax, [.cr2]
    call .puthex32

    ; --- Countdown and reboot ---
    sti                         ; re-enable interrupts so PIT ticks
    mov  dword [.countdown], 10

.countdown_loop:
    ; Blank 8 rows at y=420 (erase previous digit)
    mov  ebx, 0
.blank_r:
    cmp  ebx, 8
    jge  .blank_done
    mov  edi, [vbe_physbase]
    mov  eax, 420
    add  eax, ebx
    imul eax, 640
    add  edi, eax
    add  edi, 8
    mov  ecx, 400
    xor  al, al
    rep  stosb
    inc  ebx
    jmp  .blank_r
.blank_done:

    ; Print label in light gray
    mov  dword [.cur_x], 8
    mov  dword [.cur_y], 420
    mov  byte  [.fg], 0x07
    mov  esi, .s_reboot_msg
    call .puts

    ; Print digit(s) in yellow
    mov  byte  [.fg], 0x0E
    mov  eax, [.countdown]
    xor  edx, edx
    mov  ecx, 10
    div  ecx            ; eax=tens, edx=ones
    test eax, eax
    jz   .skip_tens
    add  al, '0'
    call .putc
.skip_tens:
    mov  eax, edx
    add  al, '0'
    call .putc

    ; Print trailing "..."
    mov  byte  [.fg], 0x07
    mov  esi, .s_dots
    call .puts

    ; Wait ~1 second (100 PIT ticks at 100Hz)
    mov  eax, [pit_ticks]
    add  eax, 100
.wait_tick:
    cmp  [pit_ticks], eax
    jb   .wait_tick

    dec  dword [.countdown]
    jnz  .countdown_loop

    ; Reboot via keyboard controller reset line
    cli
.kbc_wait:
    in   al, 0x64
    test al, 0x02
    jnz  .kbc_wait
    mov  al, 0xFE
    out  0x64, al
    ; If KBC reboot fails, triple-fault via null IDT
    lidt [.null_idt]
    int  3

.null_idt:
    dw 0
    dd 0

.halt:
    hlt
    jmp  .halt
.no_gfx:
    ret

; - Local Helpers -
; ESI=str
.puts:
    pusha
.lp:
    lodsb
    test al, al
    jz   .dn
    call .putc
    jmp  .lp
.dn:
    popa
    ret

; EAX = dword
.puthex32:
    pusha
    mov  ecx, 8
.l32:
    rol  eax, 4
    push eax
    and  al, 0x0F
    movzx ebx, al
    mov  al, [.h_table + ebx]
    call .putc
    pop  eax
    loop .l32
    popa
    ret

; EAX = byte
.puthex8:
    pusha
    mov  ecx, 2
.l8:
    rol  al, 4
    push eax
    mov  bl, al
    and  ebx, 0x0F
    mov  al, [.h_table + ebx]
    call .putc
    pop  eax
    loop .l8
    popa
    ret

; AL=char (using .cur_x/.cur_y/.fg)
.putc:
    pusha
    movzx eax, al
    and   eax, 0x7F
    shl   eax, 3
    add   eax, font_data
    mov   esi, eax          ; ESI = glyph pointer
    
    xor   edx, edx          ; row
.r:
    cmp   edx, 8
    jae   .c_dn
    
    ; EDI = base + (y+row)*pitch + x
    mov   edi, [vbe_physbase]
    mov   eax, [.cur_y]
    add   eax, edx
    movzx ebp, word [vbe_pitch]
    test  ebp, ebp
    jnz   .p_ok
    mov   ebp, 640          ; fallback
.p_ok:
    imul  eax, ebp
    add   edi, eax
    add   edi, [.cur_x]
    
    mov   al, [esi + edx]
    
    ; col loop
    mov   ecx, 8
.c:
    test  al, 0x80
    jz    .b
    push  eax
    mov   al, [.fg]
    mov   [edi], al
    pop   eax
.b:
    inc   edi
    shl   al, 1
    loop  .c
    
    inc   edx
    jmp   .r

.c_dn:
    add   dword [.cur_x], 8
    popa
    ret

; - lookup_exc -
; EAX = vector -> fills .p_name/.p_msg1/.p_msg2/.p_msg3/.p_hint
.lookup_exc:
    cmp  eax, 0x00
    jne  .lc01
    mov  dword [.p_name], .exc_de_name
    mov  dword [.p_msg1], .exc_de_m1
    mov  dword [.p_msg2], .exc_de_m2
    mov  dword [.p_msg3], .exc_de_m3
    mov  dword [.p_hint], .exc_de_hint
    ret
.lc01:
    cmp  eax, 0x06
    jne  .lc06
    mov  dword [.p_name], .exc_ud_name
    mov  dword [.p_msg1], .exc_ud_m1
    mov  dword [.p_msg2], .exc_ud_m2
    mov  dword [.p_msg3], .exc_ud_m3
    mov  dword [.p_hint], .exc_ud_hint
    ret
.lc06:
    cmp  eax, 0x08
    jne  .lc08
    mov  dword [.p_name], .exc_df_name
    mov  dword [.p_msg1], .exc_df_m1
    mov  dword [.p_msg2], .exc_df_m2
    mov  dword [.p_msg3], .exc_df_m3
    mov  dword [.p_hint], .exc_df_hint
    ret
.lc08:
    cmp  eax, 0x0A
    jne  .lc0a
    mov  dword [.p_name], .exc_ts_name
    mov  dword [.p_msg1], .exc_ts_m1
    mov  dword [.p_msg2], .exc_ts_m2
    mov  dword [.p_msg3], .exc_ts_m3
    mov  dword [.p_hint], .exc_ts_hint
    ret
.lc0a:
    cmp  eax, 0x0B
    jne  .lc0b
    mov  dword [.p_name], .exc_np_name
    mov  dword [.p_msg1], .exc_np_m1
    mov  dword [.p_msg2], .exc_np_m2
    mov  dword [.p_msg3], .exc_np_m3
    mov  dword [.p_hint], .exc_np_hint
    ret
.lc0b:
    cmp  eax, 0x0C
    jne  .lc0c
    mov  dword [.p_name], .exc_ss_name
    mov  dword [.p_msg1], .exc_ss_m1
    mov  dword [.p_msg2], .exc_ss_m2
    mov  dword [.p_msg3], .exc_ss_m3
    mov  dword [.p_hint], .exc_ss_hint
    ret
.lc0c:
    cmp  eax, 0x0D
    jne  .lc0d
    mov  dword [.p_name], .exc_gp_name
    mov  dword [.p_msg1], .exc_gp_m1
    mov  dword [.p_msg2], .exc_gp_m2
    mov  dword [.p_msg3], .exc_gp_m3
    mov  dword [.p_hint], .exc_gp_hint
    ret
.lc0d:
    cmp  eax, 0x0E
    jne  .lc0e
    mov  dword [.p_name], .exc_pf_name
    mov  dword [.p_msg1], .exc_pf_m1
    mov  dword [.p_msg2], .exc_pf_m2
    mov  dword [.p_msg3], .exc_pf_m3
    mov  dword [.p_hint], .exc_pf_hint
    ret
.lc0e:
    cmp  eax, 0x11
    jne  .lc_unk
    mov  dword [.p_name], .exc_ac_name
    mov  dword [.p_msg1], .exc_ac_m1
    mov  dword [.p_msg2], .exc_ac_m2
    mov  dword [.p_msg3], .exc_ac_m3
    mov  dword [.p_hint], .exc_ac_hint
    ret
.lc_unk:
    mov  dword [.p_name], .exc_unk_name
    mov  dword [.p_msg1], .exc_unk_m1
    mov  dword [.p_msg2], .exc_unk_m2
    mov  dword [.p_msg3], .exc_unk_m3
    mov  dword [.p_hint], .exc_unk_hint
    ret

; Data
.vec: dd 0
.err: dd 0
.cr2: dd 0
.cur_x: dd 0
.cur_y: dd 0
.fg:    db 0x0F
.h_table:  db "0123456789ABCDEF"

; Pointer slots filled by .lookup_exc
.p_name: dd 0
.p_msg1: dd 0
.p_msg2: dd 0
.p_msg3: dd 0
.p_hint: dd 0

.countdown: dd 0
.s_reboot_msg: db "Rebooting in ", 0
.s_dots:       db "...", 0
.s_osname:     db "NatureOS", 0
.s_panic_hdr:  db "-- KERNEL PANIC --", 0
.s_bang:       db "[!!]", 0
.s_exc_label:  db "Exception:  ", 0
.s_whattodo:   db "Recovery hints:", 0
.s_step_reboot: db "  ->  Reboot the machine and try again.", 0
.s_step_hw:    db "  ->  Inspect memory and CPU for hardware faults.", 0
.s_tech_hdr:   db "Fault Registers", 0
.s_vec_lbl:    db "vec=0x", 0
.s_err_lbl:    db "code=0x", 0
.s_cr2_lbl:    db "cr2=0x", 0

%include "include/panic_codes.inc"
