; ===========================================================================
; pm/wm.asm  -  ClaudeOS Window Manager
;
; Up to WM_MAX_WINS windows.  Window types: TERM, CLOCK, FILES.
; Supports dragging by title bar, close button, focus.
;
; Window record  (WM_STRIDE bytes):
;   [+0]  dd  x
;   [+4]  dd  y
;   [+8]  dd  w
;  [+12]  dd  h
;  [+16]  db  type   (WM_TERM / WM_CLOCK / WM_FILES)
;  [+17]  db  open   (1 = visible)
;  [+18]  db  focus  (1 = active / topmost)
;  [+19]  db  pad
;  [+20]  dd  title  (pointer to null-terminated string)
;  [+24] .. [+31]  reserved
;
; Calling conventions used in this file:
;   fb_fill_rect        EAX=x EBX=y ECX=w EDX=h ESI=colour
;   fb_draw_rect_outline EAX=x EBX=y ECX=w EDX=h ESI=colour
;   fb_hline            EAX=x EBX=y EDX=width CL=colour
;   fb_draw_string      ESI=str EBX=x ECX=y DL=fg DH=bg
;
; Public:
;   wm_init             once at startup
;   wm_draw_all         full redraw (desktop + windows + taskbar)
;   wm_open             AL=type EBX=x ECX=y EDX=w ESI=h  → ECX=idx CF=1 full
;   wm_close            ECX=idx
;   wm_on_click         EAX=mx EBX=my  (call on left-button press)
;   wm_on_drag          (call each mouse-move while left held)
;   wm_on_release       (call on left-button release)
;   wm_update_contents  refresh live windows (clock, files)
; ===========================================================================

[BITS 32]

; ── tunables ─────────────────────────────────────────────────────────────────
WM_MAX_WINS   equ 4
WM_STRIDE     equ 32
WM_TITLE_H    equ 18        ; title bar pixel height
WM_TASKBAR_Y  equ 462       ; 480 - 18
WM_TASKBAR_H  equ 18

WM_TERM       equ 0
WM_CLOCK      equ 1
WM_FILES      equ 2

; colours
WM_C_DESK     equ 0x01      ; dark blue desktop
WM_C_TBAR     equ 0x08      ; dark grey taskbar
WM_C_TACT     equ 0x09      ; bright blue active title
WM_C_TINACT   equ 0x08      ; inactive title (same grey as taskbar)
WM_C_BODY     equ 0x00      ; black client area
WM_C_BORDER   equ 0x07      ; grey border
WM_C_CLOSE    equ 0x04      ; red close button

; ── wm_init ──────────────────────────────────────────────────────────────────
wm_init:
    pusha
    mov  edi, wm_table
    mov  ecx, (WM_MAX_WINS * WM_STRIDE) / 4
    xor  eax, eax
    rep  stosd
    mov  dword [wm_drag_win], -1
    call wm_draw_all

    popa
    ret

; ── wm_draw_desktop ──────────────────────────────────────────────────────────
wm_draw_desktop:
    pusha
    ; fill whole screen dark blue
    xor  eax, eax
    xor  ebx, ebx
    mov  ecx, 640
    mov  edx, 480
    mov  esi, WM_C_DESK
    call fb_fill_rect

    ; ── logo: "ClaudeOS" at 4x scale (32px tall) ─────────────────────────
    ; "ClaudeOS" = 8 chars × 8px × 4 = 256px wide, centred in 640px → x=192
    ; vertical centre of desktop (excluding taskbar): (462/2) - 16 = 199
    ; draw slightly above centre to leave room for subtitle
    mov  dword [fcs_scale], 4
    mov  esi, wm_s_logo
    mov  ebx, 192           ; (640 - 8*8*4) / 2 = (640-256)/2 = 192
    mov  ecx, 170           ; y: roughly upper third of desktop
    mov  dl,  0x0B          ; bright cyan
    mov  dh,  0xFF          ; transparent bg
    call fb_draw_string_scaled

    ; ── subtitle: "v2.0" at 2x scale (16px tall) ─────────────────────────
    ; "v2.0" = 4 chars × 8px × 2 = 64px wide, centred → x=288
    mov  dword [fcs_scale], 2
    mov  esi, wm_s_logo_ver
    mov  ebx, 288           ; (640 - 4*8*2) / 2 = (640-64)/2 = 288
    mov  ecx, 214           ; 170 + 32 (title) + 12 (gap)
    mov  dl,  0x09          ; bright blue
    mov  dh,  0xFF
    call fb_draw_string_scaled

    ; ── horizontal rules ─────────────────────────────────────────────────
    ; line above title
    xor  eax, eax
    mov  ebx, 162           ; 170 - 8
    mov  edx, 640
    mov  cl,  0x03          ; dark cyan
    call fb_hline
    ; line below subtitle
    xor  eax, eax
    mov  ebx, 238           ; 214 + 16 + 8
    mov  edx, 640
    mov  cl,  0x03
    call fb_hline

    ; taskbar strip
    xor  eax, eax
    mov  ebx, WM_TASKBAR_Y
    mov  ecx, 640
    mov  edx, WM_TASKBAR_H
    mov  esi, WM_C_TBAR
    call fb_fill_rect
    ; taskbar top separator line
    xor  eax, eax
    mov  ebx, WM_TASKBAR_Y
    mov  edx, 640
    mov  cl,  0x0F
    call fb_hline
    ; "ClaudeOS" brand label on left
    mov  esi, wm_s_brand
    mov  ebx, 6
    mov  ecx, WM_TASKBAR_Y + 5
    mov  dl,  0x0F
    mov  dh,  WM_C_TBAR
    call fb_draw_string
    popa
    ret

; ── wm_draw_one ──────────────────────────────────────────────────────────────
; Draws one window chrome (title bar, border, close btn).
; For WM_TERM the client area is NOT cleared — terminal manages its own pixels.
; ECX = index.  Preserves all registers.
wm_draw_one:
    pusha
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .skip

    mov  eax, [edi+0]
    mov  ebx, [edi+4]
    mov  ecx, [edi+8]
    mov  edx, [edi+12]

    ; ── client area — always fill black ──────────────────────────────────
    push eax
    push ebx
    push ecx
    push edx
    add  ebx, WM_TITLE_H
    sub  edx, WM_TITLE_H
    mov  esi, WM_C_BODY
    call fb_fill_rect
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax

.skip_body:

    ; ── title bar ──
    push eax
    push ebx
    push ecx
    push edx
    mov  edx, WM_TITLE_H
    mov  esi, WM_C_TINACT
    cmp  byte [edi+18], 1
    jne  .tb
    mov  esi, WM_C_TACT
.tb:
    call fb_fill_rect
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax

    ; ── outer border ──
    push eax
    push ebx
    push ecx
    push edx
    mov  esi, WM_C_BORDER
    call fb_draw_rect_outline
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax

    ; ── close button (red rectangle, top-right of title bar) ──
    push eax
    push ebx
    push ecx
    push edx
    add  eax, ecx               ; x + w
    sub  eax, 18                ; x of close box = winx+w-18
    add  ebx, 2
    mov  ecx, 14
    mov  edx, 14
    mov  esi, WM_C_CLOSE
    call fb_fill_rect
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax

    ; ── title text ──
    push eax
    push ecx
    mov  esi, [edi+20]          ; title string pointer
    mov  ecx, [edi+4]
    add  ecx, 5                 ; y = win_y + 5
    mov  ebx, [edi+0]
    add  ebx, 6                 ; x = win_x + 6
    mov  dl,  0x0F
    mov  dh,  WM_C_TINACT
    cmp  byte [edi+18], 1
    jne  .tt
    mov  dh, WM_C_TACT
.tt:
    call fb_draw_string
    pop  ecx
    pop  eax

.skip:
    popa
    ret

; ── wm_draw_taskbar_btns ─────────────────────────────────────────────────────
wm_draw_taskbar_btns:
    pusha
    mov  dword [wm_tbx], 90     ; start after the brand text
    mov  dword [wm_i],   0
.loop:
    mov  ecx, [wm_i]
    cmp  ecx, WM_MAX_WINS
    jge  .done

    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .next

    ; button fill
    mov  eax, [wm_tbx]
    mov  ebx, WM_TASKBAR_Y + 2
    mov  ecx, 88
    mov  edx, WM_TASKBAR_H - 4
    mov  esi, 0x07
    cmp  byte [edi+18], 1
    jne  .bbg
    mov  esi, 0x09
.bbg:
    call fb_fill_rect

    ; button border
    mov  eax, [wm_tbx]
    mov  ebx, WM_TASKBAR_Y + 2
    mov  ecx, 88
    mov  edx, WM_TASKBAR_H - 4
    mov  esi, 0x0F
    call fb_draw_rect_outline

    ; button label
    mov  esi, [edi+20]
    mov  ebx, [wm_tbx]
    add  ebx, 4
    mov  ecx, WM_TASKBAR_Y + 6
    mov  dl,  0x0F
    mov  dh,  0x07
    cmp  byte [edi+18], 1
    jne  .blbl
    mov  dh, 0x09
.blbl:
    call fb_draw_string

    add  dword [wm_tbx], 92

.next:
    inc  dword [wm_i]
    jmp  .loop
.done:
    popa
    ret

; ── wm_draw_all ──────────────────────────────────────────────────────────────
; Draw order: desktop → terminal chrome+content → all other windows → taskbar
; This ensures non-terminal windows always appear on top of the terminal.
wm_draw_all:
    pusha
    call cursor_erase           ; remove cursor before any drawing
    call wm_draw_desktop
    call icons_draw         ; icons are part of desktop — windows draw over them

    ; Pass 1: draw the terminal window (chrome + content) first
    mov  dword [wm_i], 0
.p1loop:
    mov  ecx, [wm_i]
    cmp  ecx, WM_MAX_WINS
    jge  .p1done
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .p1next
    cmp  byte [edi+16], WM_TERM
    jne  .p1next
    call wm_draw_one            ; draw chrome (fills client black)
    call term_redraw            ; paint text buffer on top
.p1next:
    inc  dword [wm_i]
    jmp  .p1loop
.p1done:

    ; Pass 2: draw all non-terminal windows on top
    mov  dword [wm_i], 0
.p2loop:
    mov  ecx, [wm_i]
    cmp  ecx, WM_MAX_WINS
    jge  .p2done
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .p2next
    cmp  byte [edi+16], WM_TERM
    je   .p2next                ; already drawn in pass 1
    call wm_draw_one
.p2next:
    inc  dword [wm_i]
    jmp  .p2loop
.p2done:

    call wm_draw_taskbar_btns
    call cursor_save_bg         ; save what's under cursor at current pos
    call cursor_draw            ; redraw cursor on top
    popa
    ret

; ── wm_open ──────────────────────────────────────────────────────────────────
; In:  AL=type  EBX=x  ECX=y  EDX=w  ESI=h
; Out: ECX=new index (unchanged if error);  CF=1 table full
wm_open:
    push eax
    push esi
    push edi

    ; save params before we clobber registers
    movzx eax, al
    mov  [wm_op_type], eax
    mov  [wm_op_x],    ebx
    mov  [wm_op_y],    ecx
    mov  [wm_op_w],    edx
    mov  [wm_op_h],    esi

    ; find a free slot -> ECX
    xor  ecx, ecx
.find:
    cmp  ecx, WM_MAX_WINS
    jge  .full
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 0
    je   .fill
    inc  ecx
    jmp  .find

.fill:
    mov  eax, [wm_op_x]
    mov  [edi+0],  eax
    mov  eax, [wm_op_y]
    mov  [edi+4],  eax
    mov  eax, [wm_op_w]
    mov  [edi+8],  eax
    mov  eax, [wm_op_h]
    mov  [edi+12], eax
    mov  eax, [wm_op_type]
    mov  [edi+16], al
    mov  byte [edi+17], 1       ; open
    mov  byte [edi+18], 1       ; focused

    ; pick title string
    cmp  eax, WM_TERM
    jne  .t1
    mov  dword [edi+20], wm_s_term
    jmp  .title_ok
.t1:
    cmp  eax, WM_CLOCK
    jne  .t2
    mov  dword [edi+20], wm_s_clock
    jmp  .title_ok
.t2:
    mov  dword [edi+20], wm_s_files
.title_ok:

    ; clear focus on all other windows
    push ecx
    push edi
    xor  eax, eax
.clrf:
    cmp  eax, WM_MAX_WINS
    jge  .clrf_done
    cmp  eax, [esp+4]           ; skip the newly opened one (saved ecx)
    je   .clrf_skip
    imul esi, eax, WM_STRIDE
    add  esi, wm_table
    mov  byte [esi+18], 0
.clrf_skip:
    inc  eax
    jmp  .clrf
.clrf_done:
    pop  edi
    pop  ecx

    clc
    jmp  .out

.full:
    stc

.out:
    pop  edi
    pop  esi
    pop  eax
    ret

; ── wm_close ─────────────────────────────────────────────────────────────────
; In: ECX = index
wm_close:
    pusha
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    mov  byte [edi+17], 0
    mov  byte [edi+18], 0
    ; re-focus the first remaining open window
    xor  ecx, ecx
.rf:
    cmp  ecx, WM_MAX_WINS
    jge  .rf_done
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .rf_next
    mov  byte [edi+18], 1
    jmp  .rf_done
.rf_next:
    inc  ecx
    jmp  .rf
.rf_done:
    call wm_draw_all

    popa
    ret

; ── wm_set_focus ─────────────────────────────────────────────────────────────
; In: ECX = index to focus
wm_set_focus:
    pusha
    xor  eax, eax
.clear:
    cmp  eax, WM_MAX_WINS
    jge  .set
    imul edi, eax, WM_STRIDE
    add  edi, wm_table
    mov  byte [edi+18], 0
    inc  eax
    jmp  .clear
.set:
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    mov  byte [edi+18], 1
    popa
    ret

; ── wm_hit_test ──────────────────────────────────────────────────────────────
; In:  EAX=mx  EBX=my
; Out: CF=0 → ECX=window index (topmost hit)  EDX=region(1=title 2=close 3=client)
;      CF=1 → desktop (no window hit)
wm_hit_test:
    push eax
    push ebx

    mov  ecx, WM_MAX_WINS - 1   ; scan top-to-bottom
.scan:
    cmp  ecx, 0
    jl   .miss

    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .snext

    ; x bounds check
    mov  edx, [edi+0]
    cmp  eax, edx
    jl   .snext
    add  edx, [edi+8]
    cmp  eax, edx
    jge  .snext
    ; y bounds check
    mov  edx, [edi+4]
    cmp  ebx, edx
    jl   .snext
    add  edx, [edi+12]
    cmp  ebx, edx
    jge  .snext

    ; ── determine region ──
    ; close button: x >= win_x+w-18  AND  y <= win_y+16
    mov  edx, [edi+0]
    add  edx, [edi+8]
    sub  edx, 18
    cmp  eax, edx
    jl   .not_close
    mov  edx, [edi+4]
    add  edx, 16
    cmp  ebx, edx
    jg   .not_close
    mov  edx, 2
    clc
    jmp  .hit

.not_close:
    ; title bar: y < win_y + WM_TITLE_H
    mov  edx, [edi+4]
    add  edx, WM_TITLE_H
    cmp  ebx, edx
    jge  .is_client
    mov  edx, 1
    clc
    jmp  .hit

.is_client:
    mov  edx, 3
    clc
    jmp  .hit

.snext:
    dec  ecx
    jmp  .scan

.miss:
    stc

.hit:
    pop  ebx
    pop  eax
    ret

; ── wm_on_click ──────────────────────────────────────────────────────────────
; In: EAX=mx  EBX=my
wm_on_click:
    pusha

    ; ── taskbar button click? ─────────────────────────────────────────────
    cmp  ebx, WM_TASKBAR_Y
    jl   .not_taskbar
    ; in taskbar row — find which button
    mov  edx, 90            ; first button x (matches wm_draw_taskbar_btns)
    xor  ecx, ecx
.tbscan:
    cmp  ecx, WM_MAX_WINS
    jge  .not_taskbar
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .tb_next
    cmp  eax, edx
    jl   .tb_next
    mov  esi, edx
    add  esi, 88
    cmp  eax, esi
    jge  .tb_next
    call wm_set_focus        ; ECX = window index
    call wm_draw_all

    jmp  .done
.tb_next:
    add  edx, 92
    inc  ecx
    jmp  .tbscan

.not_taskbar:
    ; ── window hit test ───────────────────────────────────────────────────
    call wm_hit_test
    jc   .desktop

    push ecx
    push edx
    call wm_set_focus
    pop  edx
    pop  ecx

    cmp  edx, 2             ; close?
    je   .do_close
    cmp  edx, 1             ; title bar — start drag
    je   .do_drag
    jmp  .done              ; client click — no redraw needed

.do_close:
    call wm_close
    jmp  .done

.do_drag:
    mov  [wm_drag_win], ecx
    mov  [wm_drag_mx0], eax
    mov  [wm_drag_my0], ebx
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    mov  eax, [edi+0]
    mov  [wm_drag_wx0], eax
    mov  eax, [edi+4]
    mov  [wm_drag_wy0], eax
    jmp  .done

.desktop:
    mov  dword [wm_drag_win], -1

.done:
    popa
    ret

; ── wm_on_drag ───────────────────────────────────────────────────────────────
; XOR ghost drag — erase old outline, move, draw new outline. Zero flicker.
wm_on_drag:
    pusha
    cmp  dword [wm_drag_win], -1
    je   .done

    mov  ecx, [wm_drag_win]
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .done

    ; compute new x
    mov  eax, [mouse_x]
    sub  eax, [wm_drag_mx0]
    add  eax, [wm_drag_wx0]
    test eax, eax
    jge  .xlo_ok
    xor  eax, eax
.xlo_ok:
    mov  edx, 640
    sub  edx, [edi+8]
    cmp  eax, edx
    jle  .xhi_ok
    mov  eax, edx
.xhi_ok:
    ; compute new y
    mov  ebx, [mouse_y]
    sub  ebx, [wm_drag_my0]
    add  ebx, [wm_drag_wy0]
    test ebx, ebx
    jge  .ylo_ok
    xor  ebx, ebx
.ylo_ok:
    mov  edx, WM_TASKBAR_Y
    sub  edx, [edi+12]
    cmp  ebx, edx
    jle  .yhi_ok
    mov  ebx, edx
.yhi_ok:

    ; skip if unchanged
    cmp  eax, [edi+0]
    jne  .moved
    cmp  ebx, [edi+4]
    je   .done

.moved:
    ; erase old XOR ghost at current (old) position
    call cursor_erase
    push eax
    push ebx
    mov  eax, [edi+0]
    mov  ebx, [edi+4]
    mov  ecx, [edi+8]
    mov  edx, [edi+12]
    call fb_xor_rect_outline
    pop  ebx
    pop  eax

    ; update position in table
    mov  [edi+0], eax
    mov  [edi+4], ebx

    ; draw new XOR ghost at new position
    mov  ecx, [edi+8]
    mov  edx, [edi+12]
    call fb_xor_rect_outline
    call cursor_save_bg
    call cursor_draw

.done:
    popa
    ret

; ── wm_on_release ────────────────────────────────────────────────────────────
; Full redraw now that drag is committed.
wm_on_release:
    pusha
    cmp  dword [wm_drag_win], -1
    je   .skip
    mov  dword [wm_drag_win], -1
    call wm_draw_all
    ; re-draw clock/files content after full redraw
    mov  dword [wm_i], 0
.loop:
    mov  ecx, [wm_i]
    cmp  ecx, WM_MAX_WINS
    jge  .skip
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .next
    movzx eax, byte [edi+16]
    cmp  eax, WM_CLOCK
    je   .doclock
    cmp  eax, WM_FILES
    je   .dofiles
    jmp  .next
.doclock:
    call wm_draw_clock
    jmp  .next
.dofiles:
    call wm_draw_files
.next:
    inc  dword [wm_i]
    jmp  .loop
.skip:

    popa
    ret

; ── wm_draw_clock ──────────────────────────────────────────────────────────── ────────────────────────────────────────────────────────────
; In: ECX = window index  (must be WM_CLOCK)
wm_draw_clock:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  [wm_tmp_idx], ecx

    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .done

    ; clear client area
    mov  eax, [edi+0]
    add  eax, 2
    mov  ebx, [edi+4]
    add  ebx, WM_TITLE_H + 2
    mov  ecx, [edi+8]
    sub  ecx, 4
    mov  edx, [edi+12]
    sub  edx, WM_TITLE_H + 4
    mov  esi, WM_C_BODY
    call fb_fill_rect

    ; read RTC  (BCD values via ports 0x70/0x71)
    mov  al, 0x04
    out  0x70, al
    in   al, 0x71
    movzx eax, al
    call .bcd2bin
    mov  [wm_clk_hh], eax

    mov  al, 0x02
    out  0x70, al
    in   al, 0x71
    movzx eax, al
    call .bcd2bin
    mov  [wm_clk_mm], eax

    mov  al, 0x00
    out  0x70, al
    in   al, 0x71
    movzx eax, al
    call .bcd2bin
    mov  [wm_clk_ss], eax

    ; build "HH:MM:SS" in wm_clk_buf
    mov  edi, wm_clk_buf
    mov  eax, [wm_clk_hh]
    call .d2
    mov  byte [edi], ':'
    inc  edi
    mov  eax, [wm_clk_mm]
    call .d2
    mov  byte [edi], ':'
    inc  edi
    mov  eax, [wm_clk_ss]
    call .d2
    mov  byte [edi], 0

    ; draw string in client area
    mov  ecx, [wm_tmp_idx]
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table

    mov  esi, wm_clk_buf
    mov  ebx, [edi+0]
    add  ebx, 10
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 10
    mov  dl,  0x0A              ; bright green
    mov  dh,  WM_C_BODY
    call fb_draw_string

.done:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; BCD byte in EAX -> binary in EAX
.bcd2bin:
    push ecx
    mov  ecx, eax
    shr  ecx, 4
    and  eax, 0x0F
    push eax
    mov  eax, ecx
    mov  ecx, 10
    mul  ecx
    pop  ecx
    add  eax, ecx
    pop  ecx
    ret

; write EAX (0-99) as 2 ASCII digits at [EDI], advance EDI by 2
.d2:
    push edx
    push ecx
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    add  al,  '0'
    mov  [edi], al
    inc  edi
    add  dl,  '0'
    mov  [edi], dl
    inc  edi
    pop  ecx
    pop  edx
    ret

; ── wm_draw_files ────────────────────────────────────────────────────────────
; In: ECX = window index  (must be WM_FILES)
wm_draw_files:
    pusha
    mov  [wm_tmp_idx], ecx

    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .fdone

    ; clear client area
    mov  eax, [edi+0]
    add  eax, 2
    mov  ebx, [edi+4]
    add  ebx, WM_TITLE_H + 2
    mov  ecx, [edi+8]
    sub  ecx, 4
    mov  edx, [edi+12]
    sub  edx, WM_TITLE_H + 4
    mov  esi, WM_C_BODY
    call fb_fill_rect

    ; reload entry pointer (fb_fill_rect may have changed ESI/EDI but we pusha'd)
    mov  ecx, [wm_tmp_idx]
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table

    ; draw "Name" header
    mov  esi, wm_s_filehdr
    mov  ebx, [edi+0]
    add  ebx, 4
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 4
    mov  dl,  0x0B
    mov  dh,  WM_C_BODY
    call fb_draw_string

    ; check FS
    cmp  dword [FS_PM_BASE], 0x53464C43
    jne  .fno_fs

    movzx eax, word [FS_PM_BASE + 4]   ; file count
    test eax, eax
    jz   .fempty
    mov  [wm_fcount], eax              ; save count to memory — not a register

    ; compute text positions from window entry
    mov  ecx, [wm_tmp_idx]
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table

    mov  eax, [edi+0]
    add  eax, 4
    mov  [wm_fx], eax

    mov  eax, [edi+4]
    add  eax, WM_TITLE_H + 14
    mov  [wm_fy], eax

    mov  eax, [edi+4]
    add  eax, [edi+12]
    sub  eax, 6
    mov  [wm_fy_max], eax

    mov  esi, FS_PM_BASE + 6           ; first directory entry

.frow:
    cmp  dword [wm_fcount], 0
    je   .fdone
    mov  eax, [wm_fy]
    cmp  eax, [wm_fy_max]
    jge  .fdone

    ; copy filename (16 bytes max, null-terminated) to wm_fbuf
    push esi
    mov  edi, wm_fbuf
    mov  ecx, 16
.fcopy:
    mov  al, [esi]
    mov  [edi], al
    inc  esi
    inc  edi
    test al, al
    jz   .fcopy_done
    loop .fcopy
    mov  byte [edi], 0          ; force null-terminate if no null found
.fcopy_done:
    pop  esi                    ; restore entry pointer

    ; draw filename
    push esi
    mov  esi, wm_fbuf
    mov  ebx, [wm_fx]
    mov  ecx, [wm_fy]
    mov  dl,  0x0F
    mov  dh,  WM_C_BODY
    call fb_draw_string
    pop  esi

    add  dword [wm_fy], 9
    add  esi, FS_ENT_SZ
    dec  dword [wm_fcount]
    jmp  .frow

.fempty:
    mov  ecx, [wm_tmp_idx]
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    mov  esi, wm_s_empty
    mov  ebx, [edi+0]
    add  ebx, 4
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 14
    mov  dl,  0x08
    mov  dh,  WM_C_BODY
    call fb_draw_string
    jmp  .fdone

.fno_fs:
    mov  ecx, [wm_tmp_idx]
    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    mov  esi, wm_s_nofs
    mov  ebx, [edi+0]
    add  ebx, 4
    mov  ecx, [edi+4]
    add  ecx, WM_TITLE_H + 14
    mov  dl,  0x0C
    mov  dh,  WM_C_BODY
    call fb_draw_string

.fdone:
    popa
    ret

; ── wm_update_contents ───────────────────────────────────────────────────────
; Refresh live windows. Clock updates once per second via RTC comparison.
; Files are static (drawn at open time) so skipped here.
wm_update_contents:
    push eax
    push ecx

    ; read current RTC seconds
    mov  al, 0x00
    out  0x70, al
    in   al, 0x71
    movzx eax, al

    ; only update if second has changed
    cmp  eax, [wm_last_sec]
    je   .done
    mov  [wm_last_sec], eax

    ; find any open clock window and refresh it
    mov  dword [wm_i], 0
.loop:
    mov  ecx, [wm_i]
    cmp  ecx, WM_MAX_WINS
    jge  .done

    imul edi, ecx, WM_STRIDE
    add  edi, wm_table
    cmp  byte [edi+17], 1
    jne  .next
    movzx eax, byte [edi+16]
    cmp  eax, WM_CLOCK
    jne  .next
    call wm_draw_clock

.next:
    inc  dword [wm_i]
    jmp  .loop

.done:
    pop  ecx
    pop  eax
    ret

; ── data ─────────────────────────────────────────────────────────────────────
wm_table:        times (WM_MAX_WINS * WM_STRIDE) db 0

wm_drag_win:     dd -1
wm_drag_mx0:     dd 0
wm_drag_my0:     dd 0
wm_drag_wx0:     dd 0
wm_drag_wy0:     dd 0

wm_tbx:          dd 0
wm_i:            dd 0
wm_tmp_idx:      dd 0

wm_op_type:      dd 0
wm_op_x:         dd 0
wm_op_y:         dd 0
wm_op_w:         dd 0
wm_op_h:         dd 0

wm_clk_hh:       dd 0
wm_clk_mm:       dd 0
wm_clk_ss:       dd 0
wm_clk_buf:      times 12 db 0

wm_fbuf:         times 20 db 0
wm_fx:           dd 0
wm_fy:           dd 0
wm_fy_max:       dd 0
wm_fcount:       dd 0

wm_s_brand:      db 'ClaudeOS', 0
wm_s_logo:       db 'ClaudeOS', 0
wm_s_logo_ver:   db 'v2.0', 0
wm_s_term:       db 'Terminal', 0
wm_s_clock:      db 'Clock', 0
wm_s_files:      db 'Files', 0
wm_s_filehdr:    db 'Name', 0
wm_s_empty:      db '(empty)', 0
wm_s_nofs:       db 'No FS', 0
wm_last_sec:     dd 0xFF      ; force first update