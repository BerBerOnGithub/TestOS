; ===========================================================================
; pm/mouse.asm - PS/2 mouse driver (polling, 3-byte packets)
;
; Public:
;   mouse_init   - call once from pm_entry, after gfx_init
;   mouse_poll   - call in main loop; moves cursor on new packets
;
; State (read-only externally):
;   mouse_x   dd   0..639
;   mouse_y   dd   0..479
;   mouse_btn db   bit0=L, bit1=R, bit2=M
; ===========================================================================

[BITS 32]

%define PORT_DATA   0x60
%define PORT_STATUS 0x64
%define PORT_CMD    0x64

; ---------------------------------------------------------------------------
; mouse_init
; ---------------------------------------------------------------------------
mouse_init:
    pusha

    mov  dword [mouse_x],       320
    mov  dword [mouse_y],       240
    mov  byte  [mouse_btn],     0
    mov  byte  [mouse_pkt_idx], 0

    ; enable aux port
    call .kww
    mov  al, 0xA8
    out  PORT_CMD, al

    ; read controller command byte, set aux-IRQ enable, clear aux-clock-disable
    call .kww
    mov  al, 0x20
    out  PORT_CMD, al
    call .kwr
    in   al, PORT_DATA
    or   al, 0x02
    and  al, 0xDF
    push eax
    call .kww
    mov  al, 0x60
    out  PORT_CMD, al
    call .kww
    pop  eax
    out  PORT_DATA, al

    ; send 0xF4 (enable data reporting) to mouse
    call .kww
    mov  al, 0xD4
    out  PORT_CMD, al
    call .kww
    mov  al, 0xF4
    out  PORT_DATA, al
    call .kwr
    in   al, PORT_DATA          ; discard ACK

    call cursor_draw
    popa
    ret

; wait until 8042 input buffer empty (ok to write)
.kww:
    in   al, PORT_STATUS
    test al, 0x02
    jnz  .kww
    ret

; wait until 8042 output buffer full (ok to read)
.kwr:
    in   al, PORT_STATUS
    test al, 0x01
    jz   .kwr
    ret

; ---------------------------------------------------------------------------
; mouse_poll  — call every iteration of main loop
; ---------------------------------------------------------------------------
mouse_poll:
    pusha
.again:
    in   al, PORT_STATUS
    test al, 0x01           ; any data?
    jz   .out
    test al, 0x20           ; aux data specifically?
    jz   .out
    in   al, PORT_DATA

    movzx ebx, byte [mouse_pkt_idx]
    mov   [mouse_pkt + ebx], al
    inc   bl
    cmp   bl, 3
    jl    .store
    mov   byte [mouse_pkt_idx], 0
    call  .process
    jmp   .again
.store:
    mov   [mouse_pkt_idx], bl
    jmp   .again
.out:
    popa
    ret

.process:
    ; erase cursor at CURRENT position before updating coords
    call cursor_erase

    ; buttons
    mov  al, [mouse_pkt]
    and  al, 0x07
    mov  [mouse_btn], al

    ; X (signed, bit4 of flags = overflow sign)
    movsx eax, byte [mouse_pkt+1]
    test  byte [mouse_pkt], 0x10
    jz    .xp
    or    eax, 0xFFFFFF00
.xp:
    add   eax, [mouse_x]
    cmp   eax, 0 
    jge   .xnn
    xor   eax, eax
.xnn:
    cmp   eax, 639
    jle   .xok
    mov   eax, 639
.xok:
    mov   [mouse_x], eax

    ; Y (inverted)
    movsx eax, byte [mouse_pkt+2]
    test  byte [mouse_pkt], 0x20
    jz    .yp
    or    eax, 0xFFFFFF00
.yp:
    neg   eax
    add   eax, [mouse_y]
    cmp   eax, 0
    jge   .ynn
    xor   eax, eax
.ynn:
    cmp   eax, 479
    jle   .yok
    mov   eax, 479
.yok:
    mov   [mouse_y], eax

    ; draw cursor at NEW position (cursor_draw saves bg first)
    call  cursor_draw
    ret

; ---------------------------------------------------------------------------
; cursor_save_bg  — save 8x8 pixels under cursor into cursor_bg[64]
; ---------------------------------------------------------------------------
cursor_save_bg:
    pusha
    xor  esi, esi            ; row
.srow:
    cmp  esi, 12
    jge  .sdone

    mov  eax, [mouse_y]
    add  eax, esi
    cmp  eax, 479
    jg   .snext
    mov  edx, [gfx_fb_pitch]
    mul  edx
    add  eax, [gfx_fb_base]
    add  eax, [mouse_x]

    xor  ecx, ecx
.scol:
    cmp  ecx, 12
    jge  .snext
    mov  ebx, [mouse_x]
    add  ebx, ecx
    cmp  ebx, 639
    jg   .snext

    push eax
    mov  bl, [eax + ecx]
    mov  eax, esi
    imul eax, 12
    add  eax, ecx
    mov  [cursor_bg + eax], bl
    pop  eax

    inc  ecx
    jmp  .scol
.snext:
    inc  esi
    jmp  .srow
.sdone:
    popa
    ret

cursor_erase:
    pusha
    xor  esi, esi
.erow:
    cmp  esi, 12
    jge  .edone
    mov  eax, [mouse_y]
    add  eax, esi
    cmp  eax, 479
    jg   .enext
    mov  edx, [gfx_fb_pitch]
    mul  edx
    add  eax, [gfx_fb_base]
    add  eax, [mouse_x]

    xor  ecx, ecx
.ecol:
    cmp  ecx, 12
    jge  .enext
    mov  ebx, [mouse_x]
    add  ebx, ecx
    cmp  ebx, 639
    jg   .enext

    push eax
    mov  eax, esi
    imul eax, 12
    add  eax, ecx
    mov  bl, [cursor_bg + eax]
    pop  eax
    mov  [eax + ecx], bl

    inc  ecx
    jmp  .ecol
.enext:
    inc  esi
    jmp  .erow
.edone:
    popa
    ret

; ---------------------------------------------------------------------------
; cursor_draw — save bg then blit 12x12 arrow (black outline + white fill)
; ---------------------------------------------------------------------------
cursor_draw:
    call cursor_save_bg
    pusha

    ; pass 1: black outline
    mov  dword [cursor_draw_colour], 0x00
    mov  esi, cursor_outline
    call cursor_blit

    ; pass 2: white fill
    mov  dword [cursor_draw_colour], 0x0F
    mov  esi, cursor_fill
    call cursor_blit

    popa
    ret

; cursor_blit: ESI = 12-byte bitmap, colour = [cursor_draw_colour]
cursor_blit:
    pusha
    xor  edi, edi            ; row
.row:
    cmp  edi, 12
    jge  .done

    mov  eax, [mouse_y]
    add  eax, edi
    cmp  eax, 479
    jg   .next

    mov  edx, [gfx_fb_pitch]
    mul  edx
    add  eax, [gfx_fb_base]
    add  eax, [mouse_x]      ; eax = &fb[y+row][x]

    movzx ebx, byte [esi + edi]  ; bitmap byte for this row

    xor  ecx, ecx            ; col
.col:
    cmp  ecx, 12
    jge  .next

    mov  edx, [mouse_x]
    add  edx, ecx
    cmp  edx, 639
    jg   .next

    ; test bit (7-col), only 8 bits wide so cols 8-11 are always 0
    cmp  ecx, 8
    jge  .skip
    mov  edx, 7
    sub  edx, ecx
    bt   ebx, edx
    jnc  .skip

    mov  dl, [cursor_draw_colour]
    mov  [eax + ecx], dl

.skip:
    inc  ecx
    jmp  .col

.next:
    inc  edi
    jmp  .row

.done:
    popa
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
mouse_x:            dd 320
mouse_y:            dd 240
mouse_btn:          db 0
mouse_pkt_idx:      db 0
                    dw 0
mouse_pkt:          db 0, 0, 0
                    db 0
cursor_draw_colour: dd 0

cursor_bg:  times 144 db 0   ; 12x12 saved background

; 12x12 arrow cursor
; Row by row, MSB=leftmost, 8 bits used (cols 0-7), rows 0-11
;
; Outline (black border):  Fill (white interior):
; X...........             ...........
; XX..........             X..........
; X0X.........             X0.........
; X00X........             X00........
; X000X.......             X000.......
; X0000X......             X0000......
; X00000X.....             X00000.....
; X000000X....             X000000....
; X0000XXX....             X0000......
; X00X.X......             X00........
; X0X..X......             X0.........
; XX...XX.....             ...........

cursor_outline:
    db 10000000b  ; row  0  X
    db 11000000b  ; row  1  XX
    db 10100000b  ; row  2  X X
    db 10010000b  ; row  3  X  X
    db 10001000b  ; row  4  X   X
    db 10000100b  ; row  5  X    X
    db 10000010b  ; row  6  X     X
    db 10011110b  ; row  7  X  XXXX
    db 10110000b  ; row  8  X XX
    db 11010000b  ; row  9  XX X
    db 10001000b  ; row 10  X   X
    db 00000000b  ; row 11

cursor_fill:
    db 00000000b  ; row  0
    db 00000000b  ; row  1
    db 00000000b  ; row  2
    db 01100000b  ; row  3   **
    db 00110000b  ; row  4    **
    db 00011000b  ; row  5     **
    db 00001100b  ; row  6      **
    db 00000000b  ; row  7
    db 00000000b  ; row  8
    db 00000000b  ; row  9
    db 00000000b  ; row 10
    db 00000000b  ; row 11