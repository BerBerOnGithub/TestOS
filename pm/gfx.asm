; ===========================================================================
; pm/gfx.asm - Framebuffer graphics primitives
;
; All drawing goes through the VESA linear framebuffer at [vbe_physbase].
; Coordinates are in pixels, colour is a VGA palette index (0-255).
;
; Pitch (bytes per scanline) is read from [vbe_pitch] — do NOT assume
; pitch == width, some VESA implementations pad to a power of two.
;
; Public interface:
;   gfx_init          - cache physbase/pitch into fast registers
;                       call once after pm_entry before any drawing
;
;   fb_fill_rect      - fill a solid rectangle
;     In: EAX=x, EBX=y, ECX=width, EDX=height, ESI=colour (byte)
;
;   fb_draw_pixel     - plot a single pixel
;     In: EAX=x, EBX=y, CL=colour
;
;   fb_hline          - horizontal line
;     In: EAX=x, EBX=y, ECX=width, CL=colour  (CL set BEFORE call)
;     Note: set CL=colour, ECX=width (CL is low byte of ECX — caller
;           must set width in ECX then set CL separately, so use EDX
;           for width and move to ECX inside — see calling convention below)
;     Revised: EAX=x, EBX=y, EDX=width, CL=colour
;
;   fb_vline          - vertical line
;     In: EAX=x, EBX=y, EDX=height, CL=colour
;
;   fb_clear          - fill entire 640x480 screen with one colour
;     In: AL=colour
;
; Internal helper:
;   gfx_row_ptr       - compute EDI = framebuffer address of pixel (EAX,EBX)
;     In: EAX=x, EBX=y   Out: EDI=ptr   Trashes: EDI only
;
; All routines preserve EAX EBX ECX EDX ESI (except where they are IN params
; consumed by the routine). EDI is always trashed (it's the write pointer).
; ===========================================================================

[BITS 32]

; ---------------------------------------------------------------------------
; gfx_init - cache framebuffer base and pitch into memory fast-vars
; Call once from pm_entry after vbe_ok is confirmed.
; ---------------------------------------------------------------------------
gfx_init:
    push eax
    ; Copy vbe_physbase and vbe_pitch into our local fast copies
    ; (vbe_* vars are 16-bit boot-time values; we promote pitch to 32-bit)
    mov  eax, [vbe_physbase]
    mov  [gfx_fb_base], eax

    movzx eax, word [vbe_pitch]
    mov  [gfx_fb_pitch], eax

    pop  eax
    ret

; ---------------------------------------------------------------------------
; gfx_row_ptr - compute EDI = address of pixel (EAX=x, EBX=y)
; Trashes EDI only. Preserves EAX, EBX, ECX, EDX.
; ---------------------------------------------------------------------------
gfx_row_ptr:
    push eax
    push edx

    ; EDI = base + y*pitch + x
    mov  edi, [gfx_fb_base]
    mov  edx, [gfx_fb_pitch]
    imul edx, ebx            ; edx = y * pitch
    add  edi, edx            ; edi = base + y*pitch
    add  edi, eax            ; edi = base + y*pitch + x

    pop  edx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; fb_clear - fill entire screen with colour AL
; ---------------------------------------------------------------------------
fb_clear:
    push eax
    push ecx
    push edi

    mov  edi, [gfx_fb_base]
    mov  ecx, 640 * 480
    ; AL already has colour — movzx into EAX and use rep stosb
    movzx eax, al
    ; fill AL into all 4 bytes for potential future rep stosd optimisation
    rep  stosb

    pop  edi
    pop  ecx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; fb_draw_pixel - plot pixel at (EAX=x, EBX=y) with colour CL
; ---------------------------------------------------------------------------
fb_draw_pixel:
    push edi
    call gfx_row_ptr         ; EDI = pixel address
    mov  [edi], cl
    pop  edi
    ret

; ---------------------------------------------------------------------------
; fb_hline - draw horizontal line
; In: EAX=x, EBX=y, EDX=width, CL=colour
; ---------------------------------------------------------------------------
fb_hline:
    push ecx
    push edi

    call gfx_row_ptr         ; EDI = start of line
    mov  ecx, edx            ; ECX = width (pixel count)
    movzx eax, cl            ; AL = colour (rep stosb uses AL)
    rep  stosb

    pop  edi
    pop  ecx
    ret

; ---------------------------------------------------------------------------
; fb_vline - draw vertical line
; In: EAX=x, EBX=y, EDX=height, CL=colour
; ---------------------------------------------------------------------------
fb_vline:
    push eax
    push ebx
    push edx
    push edi

    mov  edi, 0              ; will be computed per row
.vline_loop:
    test edx, edx
    jz   .vline_done
    call gfx_row_ptr         ; EDI = address of (x, y)
    mov  [edi], cl
    inc  ebx                 ; y++
    dec  edx
    jmp  .vline_loop
.vline_done:

    pop  edi
    pop  edx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; fb_fill_rect - fill rectangle with solid colour
; In: EAX=x, EBX=y, ECX=width, EDX=height, ESI=colour (byte, low 8 bits)
; ---------------------------------------------------------------------------
fb_fill_rect:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; Save original x and width
    mov  [gfx_rect_x], eax
    mov  [gfx_rect_w], ecx
    mov  [gfx_rect_col], esi

.row_loop:
    test edx, edx
    jz   .rect_done

    ; Restore x for this row
    mov  eax, [gfx_rect_x]
    call gfx_row_ptr         ; EDI = start of this row

    ; Fill ECX pixels
    mov  ecx, [gfx_rect_w]
    movzx eax, byte [gfx_rect_col]
    ; AL = colour, ECX = count
    push ecx
.fill_row:
    mov  [edi], al
    inc  edi
    loop .fill_row
    pop  ecx

    inc  ebx                 ; y++
    dec  edx
    jmp  .row_loop

.rect_done:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; fb_draw_rect_outline - draw an unfilled rectangle border (1px)
; In: EAX=x, EBX=y, ECX=width, EDX=height, CL=colour
;
; Draws 4 lines: top, bottom, left, right
; Note: CL=colour, but ECX also used for width — we save width first.
; Calling convention: set colour in CH, width in CL? No — use a different
; register. Revised: colour passed in ESI low byte, width in ECX, height EDX
; ---------------------------------------------------------------------------
fb_draw_rect_outline:
    push eax
    push ebx
    push ecx
    push edx
    push esi

    mov  [gfx_rect_x],   eax
    mov  [gfx_rect_y],   ebx
    mov  [gfx_rect_w],   ecx
    mov  [gfx_rect_h],   edx
    mov  [gfx_rect_col], esi

    mov  cl, byte [gfx_rect_col]

    ; Top line: (x, y, width)
    mov  eax, [gfx_rect_x]
    mov  ebx, [gfx_rect_y]
    mov  edx, [gfx_rect_w]
    call fb_hline

    ; Bottom line: (x, y+height-1, width)
    mov  eax, [gfx_rect_x]
    mov  ebx, [gfx_rect_y]
    add  ebx, [gfx_rect_h]
    dec  ebx
    mov  edx, [gfx_rect_w]
    call fb_hline

    ; Left line: (x, y, height)
    mov  eax, [gfx_rect_x]
    mov  ebx, [gfx_rect_y]
    mov  edx, [gfx_rect_h]
    call fb_vline

    ; Right line: (x+width-1, y, height)
    mov  eax, [gfx_rect_x]
    add  eax, [gfx_rect_w]
    dec  eax
    mov  ebx, [gfx_rect_y]
    mov  edx, [gfx_rect_h]
    call fb_vline

    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; fb_xor_rect_outline - XOR a rectangle border onto framebuffer
; Calling it twice on the same coords restores original pixels exactly.
; In: EAX=x, EBX=y, ECX=width, EDX=height
; ---------------------------------------------------------------------------
fb_xor_rect_outline:
    push eax
    push ebx
    push ecx
    push edx
    push edi

    mov  [gfx_rect_x], eax
    mov  [gfx_rect_y], ebx
    mov  [gfx_rect_w], ecx
    mov  [gfx_rect_h], edx

    ; top row
    mov  eax, [gfx_rect_x]
    mov  ebx, [gfx_rect_y]
    call gfx_row_ptr
    mov  ecx, [gfx_rect_w]
.top:
    xor  byte [edi], 0xFF
    inc  edi
    loop .top

    ; bottom row
    mov  eax, [gfx_rect_x]
    mov  ebx, [gfx_rect_y]
    add  ebx, [gfx_rect_h]
    dec  ebx
    call gfx_row_ptr
    mov  ecx, [gfx_rect_w]
.bot:
    xor  byte [edi], 0xFF
    inc  edi
    loop .bot

    ; left col
    mov  eax, [gfx_rect_x]
    mov  ebx, [gfx_rect_y]
    mov  ecx, [gfx_rect_h]
.left:
    call gfx_row_ptr
    xor  byte [edi], 0xFF
    inc  ebx
    loop .left

    ; right col
    mov  eax, [gfx_rect_x]
    add  eax, [gfx_rect_w]
    dec  eax
    mov  ebx, [gfx_rect_y]
    mov  ecx, [gfx_rect_h]
.right:
    call gfx_row_ptr
    xor  byte [edi], 0xFF
    inc  ebx
    loop .right

    pop  edi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; Scratch variables (used internally by rect routines)
; ---------------------------------------------------------------------------
gfx_fb_base:   dd 0
gfx_fb_pitch:  dd 0
gfx_rect_x:    dd 0
gfx_rect_y:    dd 0
gfx_rect_w:    dd 0
gfx_rect_h:    dd 0
gfx_rect_col:  dd 0