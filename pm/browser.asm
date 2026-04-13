; ===========================================================================
; pm/browser.asm  -  NatureOS Enhanced Web Browser
;
; Features:
;   - Address bar with cursor indicator
;   - Navigation toolbar: Back, Reload, Go buttons
;   - HTML rendering engine (Netscape Navigator style)
;     * <h1> blue bold-effect headings
;     * <h2> cyan headings
;     * <h3> dark-grey headings
;     * <p>  paragraph spacing
;     * <a>  cyan link text
;     * <b> / <strong>  bold (bright white)
;     * <hr> horizontal rule line
;     * <br> line break
;     * <li> bullet list items
;     * <pre> monospace green text, no word-wrap
;     * <head>/<script>/<style> contents skipped
;   - Vertical scrolling via Up/Down arrow keys
;   - Status bar showing connection state and bytes received
;   - HTTP response header stripping (skips past \r\n\r\n)
; ===========================================================================

[BITS 32]

; Layout constants
BR_TOOLBAR_H   equ 28       ; toolbar strip height (below title bar)
BR_STATUSBAR_H equ 14       ; status bar height at bottom
BR_BTN_W       equ 28       ; width of Back / Reload buttons
BR_SCROLL_STEP equ 8        ; pixels per arrow-key press

; Colour palette
BR_C_TOOLBAR   equ 0x07     ; medium grey toolbar background
BR_C_URLBG     equ 0x0F     ; white URL field
BR_C_URLBRD    equ 0x08     ; dark grey URL border
BR_C_BTNBG     equ 0x09     ; blue buttons
BR_C_BTNTX     equ 0x0F     ; white button text
BR_C_CONTENT   equ 0x0F     ; white content background
BR_C_SEPLINE   equ 0x08     ; separator line colour
BR_C_STATUSBG  equ 0x07     ; grey status bar
BR_C_STATUSTX  equ 0x00     ; black status text

; HTML renderer colour constants
BR_C_TEXT      equ 0x00     ; black body text
BR_C_H1        equ 0x09     ; blue  H1
BR_C_H2        equ 0x03     ; cyan  H2
BR_C_H3        equ 0x08     ; dark grey H3
BR_C_LINK      equ 0x0B     ; bright cyan links
BR_C_BOLD      equ 0x0F     ; bright white bold
BR_C_PRE       equ 0x02     ; green preformatted
BR_C_HR        equ 0x08     ; dark grey HR line

; HTML renderer line heights
BR_LH_NORMAL   equ 10       ; normal text line height
BR_LH_H1       equ 18       ; H1 line height (drawn double for bold effect)
BR_LH_H2       equ 14       ; H2 line height
BR_LH_H3       equ 12       ; H3 line height

browser_init:
    pusha
    ; clear URL buffer
    mov  edi, browser_url
    xor  eax, eax
    mov  ecx, 64
    rep  stosd
    ; clear prev URL
    mov  edi, browser_prev_url
    mov  ecx, 64
    rep  stosd
    ; clear content
    mov  edi, browser_content
    mov  ecx, 4096
    rep  stosd
    ; clear status
    mov  edi, browser_status
    mov  ecx, 16
    rep  stosd
    ; clear title buffer
    mov  edi, browser_title_buf
    mov  ecx, 16
    rep  stosd

    ; initial URL
    mov  esi, browser_s_default_url
    mov  edi, browser_url
.copy_url:
    lodsb
    stosb
    test al, al
    jnz  .copy_url

    ; welcome text
    mov  esi, browser_s_welcome
    mov  edi, browser_content
.copy_welcome:
    lodsb
    stosb
    test al, al
    jnz  .copy_welcome

    ; initial status
    mov  esi, browser_s_ready
    mov  edi, browser_status
.copy_status:
    lodsb
    stosb
    test al, al
    jnz  .copy_status

    ; reset scroll
    mov  dword [browser_scroll_y], 0
    mov  dword [browser_rx_total], 0

    popa
    ret

; ===========================================================================
; browser_draw - Draw the entire browser UI
; In: EDI = window record
; ===========================================================================
browser_draw:
    pusha
    mov  [br_win], edi       ; stash window pointer

    mov  eax, [edi+0]   ; wx
    mov  ebx, [edi+4]   ; wy
    mov  ecx, [edi+8]   ; ww
    mov  edx, [edi+12]  ; wh

    ; ----- 1. Toolbar background -----
    pusha
    add  ebx, WM_TITLE_H
    mov  edx, BR_TOOLBAR_H
    mov  esi, BR_C_TOOLBAR
    call fb_fill_rect
    popa

    ; ----- 2. Back button [<] -----
    pusha
    add  eax, 4
    add  ebx, WM_TITLE_H + 4
    mov  ecx, BR_BTN_W
    mov  edx, 20
    mov  esi, BR_C_BTNBG
    call fb_fill_rect
    ; label
    mov  ebx, eax
    add  ebx, 8
    mov  edi, [br_win]
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 8
    mov  esi, browser_s_back
    mov  dl, BR_C_BTNTX
    mov  dh, BR_C_BTNBG
    call fb_draw_string
    popa

    ; ----- 3. Reload button [R] -----
    pusha
    add  eax, 4 + BR_BTN_W + 3
    add  ebx, WM_TITLE_H + 4
    mov  ecx, BR_BTN_W
    mov  edx, 20
    mov  esi, BR_C_BTNBG
    call fb_fill_rect
    ; label
    mov  ebx, eax
    add  ebx, 10
    mov  edi, [br_win]
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 8
    mov  esi, browser_s_reload
    mov  dl, BR_C_BTNTX
    mov  dh, BR_C_BTNBG
    call fb_draw_string
    popa

    ; ----- 3b. Home button [H] -----
    pusha
    add  eax, 4 + BR_BTN_W + 3 + BR_BTN_W + 3
    add  ebx, WM_TITLE_H + 4
    mov  ecx, BR_BTN_W
    mov  edx, 20
    mov  esi, BR_C_BTNBG
    call fb_fill_rect
    ; label
    mov  ebx, eax
    add  ebx, 10
    mov  edi, [br_win]
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 8
    mov  esi, browser_s_home
    mov  dl, BR_C_BTNTX
    mov  dh, BR_C_BTNBG
    call fb_draw_string
    popa

    ; ----- 4. URL bar -----
    pusha
    mov  edi, [br_win]
    ; x = wx + 4 + BTN_W + 3 + BTN_W + 3 + BTN_W + 3
    mov  eax, [edi+0]
    add  eax, 4 + BR_BTN_W + 3 + BR_BTN_W + 3 + BR_BTN_W + 3
    mov  [br_url_x], eax
    ; y = wy + TITLE_H + 4
    mov  ebx, [edi+4]
    add  ebx, WM_TITLE_H + 4
    mov  [br_url_y], ebx
    ; width = ww - (left margin + 3 buttons + Go button + margins)
    mov  ecx, [edi+8]
    sub  ecx, 4 + (BR_BTN_W + 3) * 3 + 3 + 42 + 4  ; total margins
    mov  [br_url_w], ecx
    mov  edx, 20         ; height
    ; border
    push eax
    push ebx
    push ecx
    push edx
    mov  esi, BR_C_URLBRD
    call fb_draw_rect_outline
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ; inner fill
    push eax
    push ebx
    push ecx
    push edx
    inc  eax
    inc  ebx
    sub  ecx, 2
    sub  edx, 2
    mov  esi, BR_C_URLBG
    call fb_fill_rect
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ; URL text
    mov  ebx, eax
    add  ebx, 4
    mov  edi, [br_win]
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 10
    mov  esi, browser_url
    mov  dl, 0x00        ; black text
    mov  dh, BR_C_URLBG  ; white bg
    call fb_draw_string
    ; cursor underscore
    ; ebx is now past the last char
    mov  al, '_'
    mov  dl, 0x08        ; grey cursor
    mov  dh, BR_C_URLBG
    mov  ecx, [br_win]
    mov  ecx, [ecx+4]
    add  ecx, WM_TITLE_H + 10
    call fb_draw_char
    popa

    ; ----- 5. Go button -----
    pusha
    mov  edi, [br_win]
    mov  eax, [edi+0]
    add  eax, [edi+8]
    sub  eax, 46
    add  ebx, WM_TITLE_H + 4
    mov  ecx, 42
    mov  edx, 20
    mov  esi, BR_C_BTNBG
    call fb_fill_rect
    ; label
    mov  ebx, eax
    add  ebx, 12
    mov  edi, [br_win]
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 8
    mov  esi, browser_s_go
    mov  dl, BR_C_BTNTX
    mov  dh, BR_C_BTNBG
    call fb_draw_string
    popa

    ; ----- 6. Separator line below toolbar -----
    pusha
    mov  edi, [br_win]
    mov  eax, [edi+0]
    mov  ebx, [edi+4]
    add  ebx, WM_TITLE_H + BR_TOOLBAR_H
    mov  edx, [edi+8]
    mov  cl, BR_C_SEPLINE
    call fb_hline
    popa

    ; ----- 7. Content area -----
    pusha
    mov  edi, [br_win]
    mov  eax, [edi+0]
    add  eax, 1
    mov  ebx, [edi+4]
    add  ebx, WM_TITLE_H + BR_TOOLBAR_H + 1
    mov  ecx, [edi+8]
    sub  ecx, 2
    mov  edx, [edi+12]
    sub  edx, WM_TITLE_H + BR_TOOLBAR_H + 1 + BR_STATUSBAR_H + 1
    mov  esi, BR_C_CONTENT
    call fb_fill_rect

    ; Draw content text (with scroll offset)
    mov  edi, [br_win]
    mov  eax, [edi+0]
    add  eax, 5
    mov  ebx, [edi+4]
    add  ebx, WM_TITLE_H + BR_TOOLBAR_H + 3
    mov  ecx, [edi+8]
    sub  ecx, 10
    mov  edx, [edi+12]
    sub  edx, WM_TITLE_H + BR_TOOLBAR_H + 3 + BR_STATUSBAR_H + 2

    mov  esi, browser_content
    call browser_draw_content
    popa

    ; ----- 8. Status bar -----
    pusha
    mov  edi, [br_win]
    ; separator line above status bar
    mov  eax, [edi+0]
    mov  ebx, [edi+4]
    add  ebx, [edi+12]
    sub  ebx, BR_STATUSBAR_H + 1
    mov  edx, [edi+8]
    mov  cl, BR_C_SEPLINE
    call fb_hline
    ; status background
    mov  eax, [edi+0]
    add  eax, 1
    mov  ebx, [edi+4]
    add  ebx, [edi+12]
    sub  ebx, BR_STATUSBAR_H
    mov  ecx, [edi+8]
    sub  ecx, 2
    mov  edx, BR_STATUSBAR_H
    mov  esi, BR_C_STATUSBG
    call fb_fill_rect
    ; status text
    mov  ebx, [edi+0]
    add  ebx, 6
    mov  ecx, [edi+4]
    add  ecx, [edi+12]
    sub  ecx, BR_STATUSBAR_H - 3
    mov  esi, browser_status
    mov  dl, BR_C_STATUSTX
    mov  dh, BR_C_STATUSBG
    call fb_draw_string
    popa

    ; ----- 9. Progress bar (inside status bar) -----
    pusha
    mov  eax, [browser_rx_total]
    test eax, eax
    jz   .no_progress
    mov  edi, [br_win]
    mov  eax, [edi+0]
    add  eax, [edi+8]
    sub  eax, 104       ; 100px bar + 4px margin
    mov  ebx, [edi+4]
    add  ebx, [edi+12]
    sub  ebx, BR_STATUSBAR_H - 4
    mov  ecx, 100       ; total width
    mov  edx, BR_STATUSBAR_H - 8
    mov  esi, 0x08      ; dark grey background for bar
    call fb_fill_rect
    
    ; fill based on rx_total (modulo 100 for indeterminate-like effect if no content-length)
    ; better: just fill based on (rx / 1024) % 100
    mov  eax, [browser_rx_total]
    shr  eax, 10        ; KB
    xor  edx, edx
    mov  ecx, 100
    div  ecx
    mov  ecx, edx       ; remainder (0..99)
    test ecx, ecx
    jz   .no_progress
    
    mov  edi, [br_win]
    mov  eax, [edi+0]
    add  eax, [edi+8]
    sub  eax, 104
    mov  esi, 0x0A      ; light green fill
    call fb_fill_rect
.no_progress:
    popa

    popa
    ret

; ===========================================================================
; browser_draw_content - Netscape-style HTML renderer
; In: ESI=content ptr, EAX=x0, EBX=y0, ECX=w, EDX=h
; Uses: browser_scroll_y for vertical offset
;
; HTML state machine:
;   br_html_* flags track current rendering mode
;   br_tag_buf accumulates tag name bytes (<xx...>)
;   Tags handled: h1 h2 h3 /h1 /h2 /h3 p /p a /a b /b strong /strong
;                 hr br li pre /pre head /head script /script style /style
; ===========================================================================
browser_draw_content:
    pusha
    mov  [br_x0],  eax
    mov  [br_y0],  ebx
    mov  [br_w],   ecx
    mov  [br_h],   edx

    ; Reset cursor to top-left of content area
    mov  [br_cx],  eax
    mov  dword [br_vy], 0

    ; Reset all HTML state flags
    mov  byte [br_html_in_tag],    0
    mov  byte [br_html_h1],        0
    mov  byte [br_html_h2],        0
    mov  byte [br_html_h3],        0
    mov  byte [br_html_bold],      0
    mov  byte [br_html_link],      0
    mov  byte [br_html_pre],       0
    mov  byte [br_html_skip],      0
    mov  byte [br_html_li_bullet], 0
    mov  dword [br_tag_len],       0
    mov  byte [br_need_nl],        0

.main_loop:
    movzx eax, byte [esi]
    inc  esi
    test al, al
    jz   .done

    ; ---- TAG ACCUMULATION MODE ----
    cmp  byte [br_html_in_tag], 1
    je   .in_tag

    ; ---- NORMAL CHARACTER MODE ----
    cmp  al, '<'
    je   .start_tag

    ; handle <title> accumulation
    cmp  byte [br_html_title], 1
    jne  .not_in_title
    ; find end of title string
    push edi
    mov  edi, browser_title_buf
    xor  ecx, ecx
.find_t_end:
    cmp  byte [edi+ecx], 0
    je   .t_found
    inc  ecx
    cmp  ecx, 63
    jl   .find_t_end
    jmp  .t_done
.t_found:
    mov  [edi+ecx], al
    mov  byte [edi+ecx+1], 0
.t_done:
    pop  edi
    jmp  .main_loop

.not_in_title:
    ; Skip content if inside head/script/style
    cmp  byte [br_html_skip], 1
    je   .main_loop

    cmp  al, 13      ; CR
    je   .main_loop
    cmp  al, 10      ; LF
    je   .handle_lf

    ; Deferred newline from block tags
    cmp  byte [br_need_nl], 1
    jne  .no_pending_nl
    mov  byte [br_need_nl], 0
    call br_do_newline
.no_pending_nl:

    ; <pre>: no word wrap
    cmp  byte [br_html_pre], 1
    je   .draw_the_char

    ; Word-wrap check
    mov  edx, [br_cx]
    sub  edx, [br_x0]
    add  edx, 8
    cmp  edx, [br_w]
    ja   .wrap_line

.draw_the_char:
    ; Check visible (above scroll window?)
    mov  edx, [br_vy]
    cmp  edx, [browser_scroll_y]
    jb   .advance_cx

    ; get screen Y
    call br_screen_y     ; ECX = screen Y
    ; check bottom clip
    mov  edx, ecx
    sub  edx, [br_y0]
    add  edx, 8
    cmp  edx, [br_h]
    ja   .done

    ; choose colour
    call br_get_fg_color ; DL = fg
    mov  dh, BR_C_CONTENT

    ; H1: draw twice (bold shadow effect)
    cmp  byte [br_html_h1], 1
    jne  .draw_once

    push eax
    push ecx
    mov  ebx, [br_cx]
    call fb_draw_char
    inc  ecx
    call fb_draw_char
    pop  ecx
    pop  eax
    jmp  .advance_cx

.draw_once:
    push eax
    mov  ebx, [br_cx]
    call fb_draw_char
    pop  eax

.advance_cx:
    add  dword [br_cx], 8
    jmp  .main_loop

.wrap_line:
    mov  eax, [br_x0]
    mov  [br_cx], eax
    call br_advance_vy
    dec  esi
    jmp  .main_loop

.handle_lf:
    cmp  byte [br_html_pre], 1
    jne  .main_loop
    ; In pre: real newline
    mov  eax, [br_x0]
    mov  [br_cx], eax
    call br_advance_vy
    jmp  .main_loop

.start_tag:
    mov  byte [br_html_in_tag], 1
    mov  dword [br_tag_len], 0
    mov  dword [br_tag_buf],   0
    mov  dword [br_tag_buf+4], 0
    mov  dword [br_tag_buf+8], 0
    jmp  .main_loop

.in_tag:
    cmp  al, '>'
    je   .end_tag
    mov  ecx, [br_tag_len]
    cmp  ecx, 15
    jge  .main_loop
    ; lowercase A-Z
    cmp  al, 'A'
    jl   .tag_store
    cmp  al, 'Z'
    jg   .tag_store
    or   al, 0x20
.tag_store:
    cmp  al, ' '
    je   .main_loop
    mov  [br_tag_buf + ecx], al
    inc  ecx
    mov  [br_tag_len], ecx
    mov  byte [br_tag_buf + ecx], 0
    jmp  .main_loop

.end_tag:
    mov  byte [br_html_in_tag], 0
    call br_dispatch_tag
    jmp  .main_loop

.done:
    popa
    ret

; ===========================================================================
; br_dispatch_tag - Apply HTML tag effect based on br_tag_buf
; ===========================================================================
br_dispatch_tag:
    push esi
    push edi
    push ecx

    mov  al, [br_tag_buf]
    cmp  al, '/'
    jne  .open_tags

    ; --- CLOSING TAGS ---
    mov  al, [br_tag_buf+1]

    cmp  al, 'h'
    jne  .close_not_h
    mov  al, [br_tag_buf+2]
    cmp  al, '1'
    je   .close_h1
    cmp  al, '2'
    je   .close_h2
    cmp  al, '3'
    je   .close_h3
    jmp  .close_not_h

.close_h1:
    mov  byte [br_html_h1], 0
    call br_block_end
    jmp  .tag_done

.close_h2:
    mov  byte [br_html_h2], 0
    call br_block_end
    jmp  .tag_done

.close_h3:
    mov  byte [br_html_h3], 0
    call br_block_end
    jmp  .tag_done

.close_not_h:
    cmp  al, 'a'
    jne  .close_not_a
    mov  ecx, [br_tag_len]
    cmp  ecx, 2
    jne  .close_not_a
    mov  byte [br_html_link], 0
    jmp  .tag_done

.close_not_a:
    cmp  al, 'b'
    jne  .close_not_b
    mov  ecx, [br_tag_len]
    cmp  ecx, 2
    jne  .close_not_b
    mov  byte [br_html_bold], 0
    jmp  .tag_done

.close_not_b:
    mov  esi, br_s_strong
    mov  edi, br_tag_buf+1
    call br_tag_match
    jnz  .close_not_strong
    mov  byte [br_html_bold], 0
    jmp  .tag_done

.close_not_strong:
    mov  esi, br_s_pre
    mov  edi, br_tag_buf+1
    call br_tag_match
    jnz  .close_not_pre
    mov  byte [br_html_pre], 0
    call br_block_end
    jmp  .tag_done

.close_not_pre:
    mov  esi, br_s_head
    mov  edi, br_tag_buf+1
    call br_tag_match
    jnz  .close_ck_script
    mov  byte [br_html_skip], 0
    jmp  .tag_done
.close_ck_script:
    mov  esi, br_s_script
    mov  edi, br_tag_buf+1
    call br_tag_match
    jnz  .close_ck_style
    mov  byte [br_html_skip], 0
    jmp  .tag_done
.close_ck_style:
    mov  esi, br_s_style
    mov  edi, br_tag_buf+1
    call br_tag_match
    jnz  .close_ck_title
    mov  byte [br_html_skip], 0
    jmp  .tag_done
.close_ck_title:
    mov  esi, br_s_title_tag
    mov  edi, br_tag_buf+1
    call br_tag_match
    jnz  .close_ck_p
    mov  byte [br_html_title], 0
    ; update window title
    mov  edi, [br_win]
    mov  dword [edi+20], browser_title_buf
    jmp  .tag_done
.close_ck_p:
    mov  al, [br_tag_buf+1]
    cmp  al, 'p'
    jne  .tag_done
    mov  ecx, [br_tag_len]
    cmp  ecx, 2
    jne  .tag_done
    call br_block_end
    jmp  .tag_done

    ; --- OPEN TAGS ---
.open_tags:
    cmp  al, 'h'
    jne  .not_h
    mov  al, [br_tag_buf+1]
    cmp  al, '1'
    je   .open_h1
    cmp  al, '2'
    je   .open_h2
    cmp  al, '3'
    je   .open_h3
    ; hr?
    cmp  al, 'r'
    jne  .not_h
    mov  ecx, [br_tag_len]
    cmp  ecx, 2
    jne  .not_h
    call br_draw_hr
    jmp  .tag_done

.open_h1:
    mov  byte [br_html_h1], 1
    mov  byte [br_html_h2], 0
    mov  byte [br_html_h3], 0
    call br_block_begin
    jmp  .tag_done

.open_h2:
    mov  byte [br_html_h1], 0
    mov  byte [br_html_h2], 1
    mov  byte [br_html_h3], 0
    call br_block_begin
    jmp  .tag_done

.open_h3:
    mov  byte [br_html_h1], 0
    mov  byte [br_html_h2], 0
    mov  byte [br_html_h3], 1
    call br_block_begin
    jmp  .tag_done

.not_h:
    cmp  al, 'p'
    jne  .not_p
    mov  ecx, [br_tag_len]
    cmp  ecx, 1
    jne  .not_p
    call br_block_begin
    jmp  .tag_done

.not_p:
    cmp  al, 'a'
    jne  .not_a
    mov  ecx, [br_tag_len]
    cmp  ecx, 1
    jne  .not_a
    mov  byte [br_html_link], 1
    jmp  .tag_done

.not_a:
    cmp  al, 'b'
    jne  .not_b_tag
    mov  ecx, [br_tag_len]
    cmp  ecx, 1
    jne  .not_b_tag
    mov  byte [br_html_bold], 1
    jmp  .tag_done

.not_b_tag:
    ; br tag
    mov  al, [br_tag_buf]
    cmp  al, 'b'
    jne  .not_br
    mov  al, [br_tag_buf+1]
    cmp  al, 'r'
    jne  .not_br
    mov  ecx, [br_tag_len]
    cmp  ecx, 2
    jne  .not_br
    call br_do_newline
    jmp  .tag_done
.not_br:

    mov  esi, br_s_strong
    mov  edi, br_tag_buf
    call br_tag_match
    jnz  .not_strong
    mov  byte [br_html_bold], 1
    jmp  .tag_done
.not_strong:

    mov  esi, br_s_pre
    mov  edi, br_tag_buf
    call br_tag_match
    jnz  .not_pre
    mov  byte [br_html_pre], 1
    call br_block_begin
    jmp  .tag_done
.not_pre:

    mov  esi, br_s_li
    mov  edi, br_tag_buf
    call br_tag_match
    jnz  .not_li
    call br_do_newline
    ; bullet
    mov  edx, [br_vy]
    cmp  edx, [browser_scroll_y]
    jb   .li_skip_bullet
    call br_screen_y
    mov  ebx, [br_cx]
    push eax
    mov  al, '*'
    mov  dl, BR_C_TEXT
    mov  dh, BR_C_CONTENT
    call fb_draw_char
    add  dword [br_cx], 8
    mov  al, ' '
    call fb_draw_char
    add  dword [br_cx], 8
    pop  eax
    jmp  .tag_done
.li_skip_bullet:
    add  dword [br_cx], 16
    jmp  .tag_done
.not_li:

    mov  esi, br_s_head
    mov  edi, br_tag_buf
    call br_tag_match
    jnz  .not_head
    mov  byte [br_html_skip], 1
    jmp  .tag_done
.not_head:
    mov  esi, br_s_script
    mov  edi, br_tag_buf
    call br_tag_match
    jnz  .not_script
    mov  byte [br_html_skip], 1
    jmp  .tag_done
.not_script:
    mov  esi, br_s_style
    mov  edi, br_tag_buf
    call br_tag_match
    jnz  .not_title_tag
    mov  byte [br_html_skip], 1
    jmp  .tag_done
.not_title_tag:
    mov  esi, br_s_title_tag
    mov  edi, br_tag_buf
    call br_tag_match
    jnz  .tag_done
    mov  byte [br_html_title], 1
    ; clear title buffer when opening new title
    push edi
    push ecx
    mov  edi, browser_title_buf
    mov  ecx, 16
    xor  eax, eax
    rep  stosd
    pop  ecx
    pop  edi

.tag_done:
    pop  ecx
    pop  edi
    pop  esi
    ret

; ===========================================================================
; br_tag_match - strcmp ESI vs EDI, ZF=1 match
; ===========================================================================
br_tag_match:
    push esi
    push edi
.tm_loop:
    mov  al, [esi]
    cmp  al, [edi]
    jne  .tm_no
    test al, al
    jz   .tm_yes
    inc  esi
    inc  edi
    jmp  .tm_loop
.tm_yes:
    pop  edi
    pop  esi
    test al, al   ; ZF=1
    ret
.tm_no:
    pop  edi
    pop  esi
    cmp  al, 0xFF ; ZF=0
    ret

; ===========================================================================
; br_block_begin - newline if not already at left margin
; ===========================================================================
br_block_begin:
    push eax
    mov  eax, [br_cx]
    cmp  eax, [br_x0]
    je   .ok
    call br_do_newline
.ok:
    pop  eax
    ret

; ===========================================================================
; br_block_end - newline + extra gap after block element
; ===========================================================================
br_block_end:
    push eax
    mov  eax, [br_cx]
    cmp  eax, [br_x0]
    je   .at_left
    call br_do_newline
.at_left:
    call br_advance_vy
    mov  byte [br_need_nl], 0
    pop  eax
    ret

; ===========================================================================
; br_do_newline - reset X, advance Y by line height
; ===========================================================================
br_do_newline:
    push eax
    mov  eax, [br_x0]
    mov  [br_cx], eax
    call br_advance_vy
    pop  eax
    ret

; ===========================================================================
; br_advance_vy - advance br_vy by line height for current heading state
; ===========================================================================
br_advance_vy:
    push eax
    cmp  byte [br_html_h1], 1
    je   .lh_h1
    cmp  byte [br_html_h2], 1
    je   .lh_h2
    cmp  byte [br_html_h3], 1
    je   .lh_h3
    add  dword [br_vy], BR_LH_NORMAL
    jmp  .done
.lh_h1:
    add  dword [br_vy], BR_LH_H1
    jmp  .done
.lh_h2:
    add  dword [br_vy], BR_LH_H2
    jmp  .done
.lh_h3:
    add  dword [br_vy], BR_LH_H3
.done:
    pop  eax
    ret

; ===========================================================================
; br_screen_y - ECX = screen Y from br_vy and scroll
; ===========================================================================
br_screen_y:
    push eax
    mov  ecx, [br_vy]
    sub  ecx, [browser_scroll_y]
    add  ecx, [br_y0]
    pop  eax
    ret

; ===========================================================================
; br_get_fg_color - DL = fg colour for current HTML state
; ===========================================================================
br_get_fg_color:
    cmp  byte [br_html_h1], 1
    je   .c_h1
    cmp  byte [br_html_h2], 1
    je   .c_h2
    cmp  byte [br_html_h3], 1
    je   .c_h3
    cmp  byte [br_html_link], 1
    je   .c_link
    cmp  byte [br_html_bold], 1
    je   .c_bold
    cmp  byte [br_html_pre], 1
    je   .c_pre
    mov  dl, BR_C_TEXT
    ret
.c_h1:   mov dl, BR_C_H1
    ret
.c_h2:   mov dl, BR_C_H2
    ret
.c_h3:   mov dl, BR_C_H3
    ret
.c_link: mov dl, BR_C_LINK
    ret
.c_bold: mov dl, BR_C_BOLD
    ret
.c_pre:  mov dl, BR_C_PRE
    ret

; ===========================================================================
; br_draw_hr - horizontal rule line
; ===========================================================================
br_draw_hr:
    push eax
    push ebx
    push ecx
    push edx
    call br_block_begin
    mov  edx, [br_vy]
    cmp  edx, [browser_scroll_y]
    jb   .hr_skip
    call br_screen_y
    mov  edx, ecx
    sub  edx, [br_y0]
    add  edx, 4
    cmp  edx, [br_h]
    ja   .hr_skip
    mov  eax, [br_x0]
    add  eax, 4
    mov  ebx, ecx
    add  ebx, 3
    mov  edx, [br_w]
    sub  edx, 8
    mov  cl, BR_C_HR
    call fb_hline
.hr_skip:
    call br_do_newline
    call br_advance_vy
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ===========================================================================
; HTML renderer state variables
; ===========================================================================
br_win:              dd 0
br_x0:               dd 0
br_y0:               dd 0
br_w:                dd 0
br_h:                dd 0
br_cx:               dd 0
br_vy:               dd 0
br_url_x:            dd 0
br_url_y:            dd 0
br_url_w:            dd 0
br_tag_len:          dd 0
br_tag_buf:          times 16 db 0
br_html_in_tag:      db 0
br_html_h1:          db 0
br_html_h2:          db 0
br_html_h3:          db 0
br_html_bold:        db 0
br_html_link:        db 0
br_html_pre:         db 0
br_html_skip:        db 0
br_html_title:       db 0
br_html_li_bullet:   db 0
br_need_nl:          db 0

; tag name match strings
br_s_strong:   db 'strong', 0
br_s_pre:      db 'pre', 0
br_s_li:       db 'li', 0
br_s_head:     db 'head', 0
br_s_script:   db 'script', 0
br_s_style:    db 'style', 0
br_s_title_tag: db 'title', 0

; ===========================================================================
; browser_tick - Handle keyboard input for focused browser
; ===========================================================================
browser_tick:
    pusha

    ; find focused browser
    mov  dword [wm_i], 0
.loop:
    mov  ecx, [wm_i]
    cmp  ecx, WM_MAX_WINS
    jge  .done
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1       ; open?
    jne  .next
    cmp  byte [edi+18], 1       ; focused?
    jne  .next
    cmp  byte [edi+16], WM_BROWSER
    jne  .next

    ; Focused browser found!
    in   al, 0x64
    test al, 0x01
    jz   .done
    test al, 0x20
    jnz  .done
    call pm_getkey
    or   al, al
    jz   .check_special

    cmp  al, 8
    je   .bs
    cmp  al, 13
    je   .go
    cmp  al, 32
    jl   .done
    cmp  al, 127
    jge  .done

    ; Append to URL
    mov  edi, browser_url
    xor  ecx, ecx
.find_end:
    cmp  byte [edi+ecx], 0
    je   .found
    inc  ecx
    cmp  ecx, 250
    jl   .find_end
    jmp  .done
.found:
    mov  [edi+ecx], al
    mov  byte [edi+ecx+1], 0
    call wm_draw_all
    jmp  .done

.check_special:
    cmp  al, 0xDA
    je   .scroll_up
    cmp  al, 0xD9
    je   .scroll_down
    jmp  .done

.scroll_up:
    cmp  dword [browser_scroll_y], 0
    je   .done
    sub  dword [browser_scroll_y], BR_SCROLL_STEP
    js   .clamp_zero
    call wm_draw_all
    jmp  .done
.clamp_zero:
    mov  dword [browser_scroll_y], 0
    call wm_draw_all
    jmp  .done

.scroll_down:
    add  dword [browser_scroll_y], BR_SCROLL_STEP
    call wm_draw_all
    jmp  .done

.bs:
    mov  edi, browser_url
    xor  ecx, ecx
.find_end2:
    cmp  byte [edi+ecx], 0
    je   .found2
    inc  ecx
    cmp  ecx, 250
    jl   .find_end2
    jmp  .done
.found2:
    test ecx, ecx
    jz   .done
    mov  byte [edi+ecx-1], 0
    call wm_draw_all
    jmp  .done

.go:
    call browser_do_navigate
    jmp  .done

.next:
    inc  dword [wm_i]
    jmp  .loop
.done:
    popa
    ret

; ===========================================================================
; browser_click - Handle mouse clicks on the browser client area
; In: EAX=mx, EBX=my, EDI=window record
; ===========================================================================
browser_click:
    pusha

    mov  ecx, eax
    mov  edx, ebx
    sub  ecx, [edi+0]
    sub  edx, [edi+4]

    cmp  ecx, 4
    jl   .check_other
    cmp  ecx, 4 + BR_BTN_W
    jge  .check_reload
    cmp  edx, WM_TITLE_H + 4
    jl   .check_other
    cmp  edx, WM_TITLE_H + 24
    jg   .check_other
    call browser_go_back
    jmp  .done

.check_reload:
    cmp  ecx, 4 + BR_BTN_W + 3
    jl   .check_other
    cmp  ecx, 4 + BR_BTN_W + 3 + BR_BTN_W
    jge  .check_home
    cmp  edx, WM_TITLE_H + 4
    jl   .check_other
    cmp  edx, WM_TITLE_H + 24
    jg   .check_other
    call browser_fetch
    call wm_draw_all
    jmp  .done

.check_home:
    cmp  ecx, 4 + (BR_BTN_W + 3) * 2
    jl   .check_other
    cmp  ecx, 4 + (BR_BTN_W + 3) * 2 + BR_BTN_W
    jge  .check_go
    cmp  edx, WM_TITLE_H + 4
    jl   .check_other
    cmp  edx, WM_TITLE_H + 24
    jg   .check_other
    ; navigate to home
    mov  esi, browser_s_default_url
    mov  edi, browser_url
.copy_home:
    lodsb
    stosb
    test al, al
    jnz  .copy_home
    call browser_do_navigate
    jmp  .done

.check_go:
    mov  eax, [edi+8]
    sub  eax, 46
    cmp  ecx, eax
    jl   .check_other
    mov  eax, [edi+8]
    sub  eax, 4
    cmp  ecx, eax
    jg   .check_other
    cmp  edx, WM_TITLE_H + 4
    jl   .check_other
    cmp  edx, WM_TITLE_H + 24
    jg   .check_other
    call browser_do_navigate
    jmp  .done

.check_other:
.done:
    popa
    ret

; ===========================================================================
; browser_do_navigate - Save current URL as prev, then fetch
; ===========================================================================
browser_do_navigate:
    pusha
    mov  esi, browser_url
    mov  edi, browser_prev_url
    mov  ecx, 256
    rep  movsb
    mov  dword [browser_scroll_y], 0
    call browser_fetch
    call wm_draw_all
    popa
    ret

; ===========================================================================
; browser_go_back - Swap prev URL into current and fetch
; ===========================================================================
browser_go_back:
    pusha
    cmp  byte [browser_prev_url], 0
    je   .done

    mov  esi, browser_url
    mov  edi, browser_tmp
    mov  ecx, 256
    rep  movsb
    mov  esi, browser_prev_url
    mov  edi, browser_url
    mov  ecx, 256
    rep  movsb
    mov  esi, browser_tmp
    mov  edi, browser_prev_url
    mov  ecx, 256
    rep  movsb

    mov  dword [browser_scroll_y], 0
    call browser_fetch
    call wm_draw_all
.done:
    popa
    ret

; ===========================================================================
; browser_fetch - Perform HTTP GET and populate browser_content
; ===========================================================================
browser_fetch:
    pusha
    cmp  byte [br_fetching], 1
    je   .done_busy

    mov  byte [br_fetching], 1
    mov  edi, browser_status
    mov  esi, browser_s_connecting
    call .copy_str
    mov  dword [browser_rx_total], 0
    call wm_draw_all

    mov  edi, browser_content
    mov  esi, browser_s_fetching
    call .copy_str
    call wm_draw_all

    mov  esi, browser_url
    mov  edi, browser_host_buf
    mov  ecx, 127
.copy_host:
    lodsb
    test al, al
    jz   .err_url
    cmp  al, ' '
    je   .host_done
    stosb
    loop .copy_host
.host_done:
    mov  byte [edi], 0
    
    push esi
    
    mov  esi, browser_host_buf
    call pm_parse_ip
    test eax, eax
    jnz  .have_ip

    mov  edi, browser_status
    mov  esi, browser_s_resolving
    call .copy_str
    call wm_draw_all

    mov  esi, browser_host_buf
    call dns_build_query
    mov  eax, DNS_SERVER_IP
    mov  bx,  UDP_SRC_PORT
    mov  cx,  DNS_PORT
    mov  esi, dns_pkt_buf
    mov  edx, ecx
    call udp_send
    jc   .dns_fail
    
    mov  dword [dns_poll_ctr], 2000000
.dns_poll:
    call pm_poll_events      ; Keep UI responsive during DNS poll
    call eth_recv
    jc   .dns_empty
    cmp  dx, ETHERTYPE_ARP
    jne  .dns_not_arp
    call arp_process
    jmp  .dns_poll
.dns_not_arp:
    cmp  dx, ETHERTYPE_IPV4
    jne  .dns_poll
    cmp  ecx, 20 + UDP_HDR_LEN
    jl   .dns_poll
    cmp  byte [esi], 0x45
    jne  .dns_poll
    cmp  byte [esi + 9], IP_PROTO_UDP
    jne  .dns_poll
    mov  ax, [esi + 20 + 2]
    xchg al, ah
    cmp  ax, UDP_SRC_PORT
    jne  .dns_poll
    mov  ax, [esi + 20 + 4]
    xchg al, ah
    movzx ecx, ax
    sub  ecx, UDP_HDR_LEN
    cmp  ecx, 12
    jl   .dns_poll
    
    push esi
    push ecx
    push edi
    add  esi, 20 + UDP_HDR_LEN
    mov  edi, dns_pkt_buf
    rep  movsb
    pop  edi
    pop  ecx
    pop  esi
    call dns_parse_response
    jc   .dns_poll
    jmp  .have_ip

.dns_empty:
    dec  dword [dns_poll_ctr]
    jnz  .dns_poll
.dns_fail:
    pop  esi
    jmp  .err_url

.have_ip:
    mov  [tcpg_dst_ip], eax
    pop  esi

    call pm_parse_uint
    test eax, eax
    jz   .err_url
    mov  [tcpg_dst_port], ax

.skip2:
    lodsb
    test al, al
    jz   .err_url
    cmp  al, ' '
    jne  .skip2
    mov  [tcpg_path_ptr], esi

    mov  eax, [tcpg_dst_ip]
    movzx ecx, word [tcpg_dst_port]
    call tcp_connect
    jc   .err_conn

    mov  edi, browser_status
    mov  esi, browser_s_sending
    call .copy_str

    mov  edi, tcpg_req_buf
    mov  byte [edi+0], 'G'
    mov  byte [edi+1], 'E'
    mov  byte [edi+2], 'T'
    mov  byte [edi+3], ' '
    add  edi, 4
    mov  esi, [tcpg_path_ptr]
.copy_p:
    lodsb
    stosb
    test al, al
    jnz  .copy_p
    dec  edi

    mov  esi, tcpg_str_http10
    call .append_s
    mov  esi, browser_s_hdr_host_pre
    call .append_s
    mov  esi, browser_host_buf
    call .append_s
    mov  esi, browser_s_crlf
    call .append_s
    mov  esi, tcpg_str_connclose
    call .append_s
    mov  byte [edi], 0

    mov  ecx, edi
    sub  ecx, tcpg_req_buf
    mov  esi, tcpg_req_buf
    call tcp_send
    jc   .err_send

    mov  dword [browser_rx_total], 0
    mov  edi, browser_content
    xor  eax, eax
    mov  ecx, 4096
    rep  stosd

    mov  edi, browser_content

    push edi
    mov  edi, browser_status
    mov  esi, browser_s_receiving
    call .copy_str
    pop  edi

.recv_loop:
    call pm_poll_events      ; Keep UI responsive during download
    cmp  byte [tcp_state], TCP_STATE_ESTABLISHED
    je   .do_recv
    cmp  byte [tcp_state], TCP_STATE_CLOSE_WAIT
    je   .do_recv
    jmp  .recv_done

.do_recv:
    mov  ecx, 1400
    push edi
    mov  edi, tcpg_recv_buf
    call tcp_recv
    pop  edi
    jc   .recv_done
    test ecx, ecx
    jz   .recv_done

    mov  eax, edi
    sub  eax, browser_content
    add  eax, ecx
    cmp  eax, 16000
    jae  .recv_done

    add  [browser_rx_total], ecx

    push ecx
    mov  esi, tcpg_recv_buf
.copy_data:
    lodsb
    mov  [edi], al
    inc  edi
    dec  ecx
    jnz  .copy_data
    pop  ecx

    push edi
    call browser_update_rx_status
    pop  edi

    mov  byte [edi], 0
    push edi
    call wm_draw_all
    pop  edi

    jmp  .recv_loop

.recv_done:
    mov  byte [edi], 0
    call tcp_close
    call browser_strip_headers
    call browser_update_done_status
    mov  byte [br_fetching], 0
    jmp  .done

.err_url:
    mov  esi, browser_s_err_url
    jmp  .set_msg
.err_conn:
    mov  esi, browser_s_err_conn
    jmp  .set_msg
.err_send:
    mov  esi, browser_s_err_send
.set_msg:
    mov  edi, browser_content
    call .copy_str
    push esi
    mov  edi, browser_status
    mov  esi, browser_s_error
    call .copy_str
    pop  esi
.done:
    mov  byte [br_fetching], 0
    popa
    ret

.done_busy:
    popa
    ret

.copy_str:
    lodsb
    stosb
    test al, al
    jnz  .copy_str
    ret

.append_s:
    lodsb
    stosb
    test al, al
    jnz  .append_s
    dec  edi
    ret

; ===========================================================================
; browser_strip_headers - Remove HTTP headers (scan for \r\n\r\n)
; ===========================================================================
browser_strip_headers:
    pusha
    mov  esi, browser_content

.scan:
    cmp  byte [esi], 0
    je   .no_headers
    cmp  byte [esi],   13
    jne  .scan_next
    cmp  byte [esi+1], 10
    jne  .scan_next
    cmp  byte [esi+2], 13
    jne  .scan_next
    cmp  byte [esi+3], 10
    jne  .scan_next

    add  esi, 4
    mov  edi, browser_content
    cmp  esi, edi
    je   .no_headers

.move:
    lodsb
    stosb
    test al, al
    jnz  .move
    jmp  .strip_done

.scan_next:
    inc  esi
    jmp  .scan

.no_headers:
.strip_done:
    popa
    ret

; ===========================================================================
; browser_strip_html_tags - legacy stub (HTML renderer handles tags natively)
; ===========================================================================
browser_strip_html_tags:
    ret

; ===========================================================================
; browser_update_rx_status
; ===========================================================================
browser_update_rx_status:
    pusha
    mov  edi, browser_status
    mov  esi, browser_s_receiving
    call browser_fetch.copy_str
    dec  edi
    mov  byte [edi], ' '
    inc  edi
    mov  byte [edi], '('
    inc  edi
    mov  eax, [browser_rx_total]
    call browser_write_dec
    mov  byte [edi], 'b'
    inc  edi
    mov  byte [edi], ')'
    inc  edi
    mov  byte [edi], 0
    popa
    ret

; ===========================================================================
; browser_update_done_status
; ===========================================================================
browser_update_done_status:
    pusha
    mov  edi, browser_status
    mov  esi, browser_s_done
    call browser_fetch.copy_str
    dec  edi
    mov  byte [edi], ' '
    inc  edi
    mov  byte [edi], '('
    inc  edi
    mov  eax, [browser_rx_total]
    call browser_write_dec
    mov  byte [edi], 'b'
    inc  edi
    mov  byte [edi], ')'
    inc  edi
    mov  byte [edi], 0
    popa
    ret

; ===========================================================================
; browser_write_dec - Write decimal EAX to [EDI]
; ===========================================================================
browser_write_dec:
    push eax
    push ebx
    push ecx
    push edx
    mov  ecx, 0
    mov  ebx, 10
.wd_push:
    xor  edx, edx
    div  ebx
    push edx
    inc  ecx
    test eax, eax
    jnz  .wd_push
.wd_pop:
    pop  edx
    add  dl, '0'
    mov  [edi], dl
    inc  edi
    loop .wd_pop
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ===========================================================================
; Data Section
; ===========================================================================
browser_url:        times 256 db 0
browser_prev_url:   times 256 db 0
browser_tmp:        times 256 db 0
browser_host_buf:   times 128 db 0
browser_content:    times 16384 db 0
browser_status:     times 64 db 0
browser_title_buf:  times 64 db 0
browser_scroll_y:   dd 0
browser_rx_total:   dd 0
br_fetching:        db 0

; UI strings
browser_s_go:           db 'Go', 0
browser_s_back:         db '<', 0
browser_s_reload:       db 'R', 0
browser_s_home:         db 'H', 0
browser_s_default_url:  db 'example.com 80 /', 0
browser_s_hdr_host_pre: db 'Host: ', 0
browser_s_crlf:         db 13, 10, 0
browser_s_welcome:      db '<h1>NatureOS Browser</h1>', 13, 10
                        db '<p>Welcome! Enter a URL above and press Go.</p>', 13, 10
                        db '<h2>URL Format</h2>', 13, 10
                        db '<p>hostname port path</p>', 13, 10
                        db '<p>e.g. <a>example.com 80 /</a></p>', 13, 10
                        db '<h2>Navigation</h2>', 13, 10
                        db '<li>Click [&lt;] to go back</li>', 13, 10
                        db '<li>Click [R] to reload</li>', 13, 10
                        db '<li>Click [Go] or press Enter to navigate</li>', 13, 10
                        db '<li>Up/Down arrows to scroll</li>', 13, 10
                        db '<hr>', 13, 10
                        db '<p>NatureOS v2.0</p>', 13, 10, 0
browser_s_fetching:     db 'Fetching...', 0
browser_s_ready:        db 'Ready', 0
browser_s_connecting:   db 'Connecting...', 0
browser_s_sending:      db 'Sending request...', 0
browser_s_receiving:    db 'Receiving...', 0
browser_s_done:         db 'Done', 0
browser_s_error:        db 'Error', 0
browser_s_err_url:      db '<h2>Error: Invalid URL</h2>', 13, 10
                        db '<p>Expected format: hostname port path</p>', 13, 10
                        db '<p>Example: <a>example.com 80 /</a></p>', 0
browser_s_err_conn:     db '<h2>Connection Failed</h2>', 13, 10
                        db '<p>Could not connect to the server.</p>', 13, 10
                        db '<p>Check the address and try again.</p>', 0
browser_s_err_send:     db '<h2>Send Error</h2>', 13, 10
                        db '<p>Failed to send the HTTP request.</p>', 0
browser_s_resolving:    db 'Resolving hostname...', 0
