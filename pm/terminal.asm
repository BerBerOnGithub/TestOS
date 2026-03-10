; ===========================================================================
; pm/terminal.asm - GUI terminal window
;
; Draws a window with a title bar and a scrollable text area.
; Accepts keyboard input, runs pm_exec on Enter.
;
; Window geometry (matches pm_gfx_test window):
;   Window:    x=80, y=60,  w=480, h=340
;   Title bar: x=80, y=60,  w=480, h=18
;   Client:    x=88, y=82,  w=464, h=314  (4px padding inside border)
;
; Text grid (8x8 font):
;   Cols = 464 / 8 = 58 chars
;   Rows = 314 / 8 = 39 rows
;
; Public:
;   term_init       - draw window, reset state
;   term_run        - blocking: read keys, execute commands, loop forever
;   term_puts       - print null-terminated string (ESI)
;   term_putchar    - print char in AL
;   term_newline    - move to next line, scroll if needed
; ===========================================================================

[BITS 32]

%define TERM_X       88          ; client area left
%define TERM_Y       82          ; client area top
%define TERM_W       464         ; client area width  (pixels)
%define TERM_H       314         ; client area height (pixels)
%define TERM_COLS    58          ; chars per row
%define TERM_ROWS    39          ; visible rows
%define TERM_FG      0x0A        ; bright green text
%define TERM_BG      0x00        ; black background
%define TERM_PROMPT  0x0B        ; cyan prompt
%define TERM_WIN_X   80
%define TERM_WIN_Y   60
%define TERM_WIN_W   480
%define TERM_WIN_H   340

; ---------------------------------------------------------------------------
; term_init  — draw window chrome + clear text area
; ---------------------------------------------------------------------------
term_init:
    pusha

    ; window body (black client area)
    mov  eax, TERM_WIN_X
    mov  ebx, TERM_WIN_Y
    mov  ecx, TERM_WIN_W
    mov  edx, TERM_WIN_H
    mov  esi, TERM_BG
    call fb_fill_rect

    ; title bar
    mov  eax, TERM_WIN_X
    mov  ebx, TERM_WIN_Y
    mov  ecx, TERM_WIN_W
    mov  edx, 18
    mov  esi, 0x01
    call fb_fill_rect

    ; title text
    mov  esi, term_str_title
    mov  ebx, TERM_WIN_X + 8
    mov  ecx, TERM_WIN_Y + 5
    mov  dl,  0x0F
    mov  dh,  0x01
    call fb_draw_string

    ; close button
    mov  eax, TERM_WIN_X + TERM_WIN_W - 20
    mov  ebx, TERM_WIN_Y + 2
    mov  ecx, 16
    mov  edx, 14
    mov  esi, 0x04
    call fb_fill_rect

    ; border (bevel)
    mov  eax, TERM_WIN_X
    mov  ebx, TERM_WIN_Y
    mov  ecx, TERM_WIN_W
    mov  edx, TERM_WIN_H
    mov  esi, 0x07
    call fb_draw_rect_outline

    ; reset cursor
    mov  dword [term_col], 0
    mov  dword [term_row], 0

    ; print welcome banner
    mov  esi, term_str_banner
    call term_puts
    call term_newline

    ; draw input prompt
    call term_draw_prompt

    popa
    ret

; ---------------------------------------------------------------------------
; term_run  — main input loop (never returns)
; ---------------------------------------------------------------------------
term_run:
.loop:
    ; poll mouse so cursor still moves
    call mouse_poll

    ; non-blocking key check
    in   al, 0x64
    test al, 0x01
    jz   .loop
    test al, 0x20           ; ignore aux (mouse) bytes
    jnz  .loop

    call pm_getkey
    or   al, al
    jz   .loop

    cmp  al, 13             ; Enter
    je   .enter
    cmp  al, 8              ; Backspace
    je   .backspace

    ; printable: echo and buffer it
    cmp  dword [term_input_len], TERM_COLS - 3
    jge  .loop              ; line full

    ; store in input buffer
    mov  edi, term_input_buf
    add  edi, [term_input_len]
    mov  [edi], al
    inc  dword [term_input_len]

    ; echo to screen
    call term_putchar
    jmp  .loop

.backspace:
    cmp  dword [term_input_len], 0
    je   .loop
    dec  dword [term_input_len]
    ; erase character: move col back, print space, move back again
    dec  dword [term_col]
    push eax
    mov  al, ' '
    call term_putchar
    dec  dword [term_col]
    pop  eax
    jmp  .loop

.enter:
    call term_newline

    ; null-terminate input
    mov  edi, term_input_buf
    mov  eax, [term_input_len]
    mov  byte [edi + eax], 0

    ; copy to pm_input_buf and set pm_input_len
    mov  esi, term_input_buf
    mov  edi, pm_input_buf
    mov  ecx, [term_input_len]
    mov  [pm_input_len], ecx
    rep  movsb
    mov  byte [edi], 0

    ; execute
    call pm_exec

    ; reset input buffer
    mov  dword [term_input_len], 0
    mov  dword [term_col], 0

    ; new prompt
    call term_draw_prompt
    jmp  .loop

; ---------------------------------------------------------------------------
; term_draw_prompt  — print "> " in cyan at current row
; ---------------------------------------------------------------------------
term_draw_prompt:
    push eax
    push esi
    mov  esi, term_str_prompt
    push edx
    mov  dl, TERM_PROMPT
    mov  dh, TERM_BG
    call term_puts_colour
    pop  edx
    pop  esi
    pop  eax
    ret

; ---------------------------------------------------------------------------
; term_putchar  AL = char — print at (term_col, term_row), advance col
; ---------------------------------------------------------------------------
term_putchar:
    pusha

    cmp  al, 10             ; LF
    je   .newline
    cmp  al, 13             ; CR
    je   .cr

    ; clamp col
    cmp  dword [term_col], TERM_COLS - 1
    jge  .wrap

    ; compute pixel coords
    mov  ebx, [term_col]
    imul ebx, 8
    add  ebx, TERM_X

    mov  ecx, [term_row]
    imul ecx, 8
    add  ecx, TERM_Y

    mov  dl, TERM_FG
    mov  dh, TERM_BG
    call fb_draw_char

    inc  dword [term_col]
    jmp  .done

.wrap:
    call term_newline
    ; retry
    popa
    jmp  term_putchar

.newline:
    call term_newline
    jmp  .done

.cr:
    mov  dword [term_col], 0

.done:
    popa
    ret

; ---------------------------------------------------------------------------
; term_puts  ESI = null-terminated string  (uses TERM_FG/TERM_BG colours)
; ---------------------------------------------------------------------------
term_puts:
    push eax
    push edx
    mov  dl, TERM_FG
    mov  dh, TERM_BG
    call term_puts_colour
    pop  edx
    pop  eax
    ret

; term_puts_colour  ESI = string, DL = fg, DH = bg
term_puts_colour:
    push eax
    push ebx
    push ecx
.loop:
    mov  al, [esi]
    test al, al
    jz   .done
    cmp  al, 10
    je   .nl
    cmp  al, 13
    je   .cr

    ; draw char
    mov  ebx, [term_col]
    imul ebx, 8
    add  ebx, TERM_X
    mov  ecx, [term_row]
    imul ecx, 8
    add  ecx, TERM_Y
    call fb_draw_char
    inc  dword [term_col]
    cmp  dword [term_col], TERM_COLS
    jl   .next
    call term_newline
    jmp  .next
.nl:
    call term_newline
    jmp  .next
.cr:
    mov  dword [term_col], 0
.next:
    inc  esi
    jmp  .loop
.done:
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; term_newline  — move to next row, scroll entire text area up one row if needed
; ---------------------------------------------------------------------------
term_newline:
    pusha
    mov  dword [term_col], 0
    inc  dword [term_row]
    cmp  dword [term_row], TERM_ROWS
    jl   .done

    ; ── Scroll up: copy pixel rows [TERM_Y+8 .. TERM_Y+TERM_H-1]
    ;               to             [TERM_Y   .. TERM_Y+TERM_H-9]
    ; i.e. shift everything up by 8 pixels (one text row)
    mov  ecx, TERM_H - 8    ; number of pixel rows to copy
    xor  esi, esi            ; pixel row offset (0-based from TERM_Y+8)
.sloop:
    cmp  esi, TERM_H - 8
    jge  .clear_last

    ; src = fb[TERM_Y + 8 + esi][TERM_X]
    mov  eax, TERM_Y + 8
    add  eax, esi
    mov  edx, [gfx_fb_pitch]
    mul  edx
    add  eax, [gfx_fb_base]
    add  eax, TERM_X         ; eax = src ptr

    ; dst = fb[TERM_Y + esi][TERM_X]
    mov  ebx, TERM_Y
    add  ebx, esi
    mov  edx, [gfx_fb_pitch]
    push eax
    mov  eax, ebx
    mul  edx
    add  eax, [gfx_fb_base]
    add  eax, TERM_X         ; eax = dst ptr
    mov  edi, eax
    pop  eax                 ; eax = src ptr again

    ; copy TERM_W bytes src→dst
    push esi
    mov  esi, eax
    mov  ecx, TERM_W
    rep  movsb
    pop  esi

    inc  esi
    jmp  .sloop

.clear_last:
    ; blank the last text row
    mov  eax, TERM_X
    mov  ebx, TERM_Y + TERM_H - 8
    mov  ecx, TERM_W
    mov  edx, 8
    mov  esi, TERM_BG
    call fb_fill_rect

    mov  dword [term_row], TERM_ROWS - 1

.done:
    popa
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
term_col:         dd 0
term_row:         dd 0
term_input_len:   dd 0
term_input_buf:   times 128 db 0

term_str_title:   db 'Terminal', 0
term_str_banner:  db 'ClaudeOS v2.0 - type help for commands', 0
term_str_prompt:  db '> ', 0