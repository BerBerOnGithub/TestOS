; ===========================================================================
; pm/pm_shell.asm - 32-bit Protected Mode entry point and shell dispatcher
; ===========================================================================

; ---------------------------------------------------------------------------
; 32-bit entry point - jumped to from cmd_system.asm after CR0.PE is set
; ---------------------------------------------------------------------------
[BITS 32]

pm_entry:
    mov  ax, 0x10
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
    mov  ss, ax
    mov  esp, 0x7BF0
    call pm_drv_init
    call gfx_init
    call term_init
    call mouse_init

.loop:
    call term_run
    ; draw mouse_x as a colour bar on row 0 (visible debug)
    mov  eax, [mouse_x]
    mov  edi, [gfx_fb_base]
    mov  byte [edi + eax], 0x04   ; red dot at row 0, column=mouse_x
    jmp  .loop

pm_shell_loop:
    mov  esi, pm_prompt
    mov  bl, 0x0A
    call pm_puts
    call pm_readline
    call pm_exec
    jmp  pm_shell_loop

pm_gfx_test:
    push eax
    push ebx
    push ecx
    push edx
    push esi

    ; ── Desktop background (teal = colour 0x03 in VGA default palette) ───
    mov  eax, 0              ; x=0
    mov  ebx, 0              ; y=0
    mov  ecx, 640            ; w=640
    mov  edx, 480            ; h=480
    mov  esi, 0x03           ; teal
    call fb_fill_rect

    mov  eax, 320
    mov  ebx, 240
    mov  cl, 0x0F
    call fb_draw_pixel       ; white dot in centre

    ; ── Window body: white (0x0F), at (80, 60), 480x340 ──────────────────
    mov  eax, 80
    mov  ebx, 60
    mov  ecx, 480
    mov  edx, 340
    mov  esi, 0x0F           ; bright white
    call fb_fill_rect

    ; ── Title bar: dark blue (0x01), at (80, 60), 480x18 ─────────────────
    mov  eax, 80
    mov  ebx, 60
    mov  ecx, 480
    mov  edx, 18
    mov  esi, 0x01           ; dark blue
    call fb_fill_rect

    ; ── Window border outline: dark grey (0x08) ───────────────────────────
    mov  eax, 80
    mov  ebx, 60
    mov  ecx, 480
    mov  edx, 340
    mov  esi, 0x08           ; dark grey
    call fb_draw_rect_outline

    ; ── Highlight: bright white top+left edges (bevel effect) ────────────
    ; top edge bright
    mov  eax, 80
    mov  ebx, 60
    mov  edx, 480
    mov  cl,  0x0F
    call fb_hline
    ; left edge bright
    mov  eax, 80
    mov  ebx, 60
    mov  edx, 340
    mov  cl,  0x0F
    call fb_vline

    ; ── Shadow: dark grey right+bottom edges ─────────────────────────────
    ; bottom edge shadow
    mov  eax, 80
    mov  ebx, 399            ; 60 + 340 - 1
    mov  edx, 480
    mov  cl,  0x07
    call fb_hline
    ; right edge shadow
    mov  eax, 559            ; 80 + 480 - 1
    mov  ebx, 60
    mov  edx, 340
    mov  cl,  0x07
    call fb_vline

    ; ── Close button placeholder: red square in top-right of title bar ────
    mov  eax, 540            ; 80+480-20 = 540
    mov  ebx, 62
    mov  ecx, 16
    mov  edx, 14
    mov  esi, 0x04           ; red
    call fb_fill_rect

    ; ── Corner pixel test: bright magenta at screen corners ───────────────
    mov  eax, 0
    mov  ebx, 0
    mov  cl,  0x0D
    call fb_draw_pixel

    mov  eax, 639
    mov  ebx, 0
    mov  cl,  0x0D
    call fb_draw_pixel

    mov  eax, 0
    mov  ebx, 479
    mov  cl,  0x0D
    call fb_draw_pixel

    mov  eax, 639
    mov  ebx, 479
    mov  cl,  0x0D
    call fb_draw_pixel

    ; Draw title bar text
    mov  esi, pm_str_title
    mov  ebx, 88             ; x = 8px inside title bar left edge
    mov  ecx, 65             ; y = centred in 18px title bar (60+5)
    mov  dl,  0x0F           ; fg = bright white
    mov  dh,  0x01           ; bg = dark blue (same as title bar)
    call fb_draw_string

.done:
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret
; ---------------------------------------------------------------------------
; pm_exec - dispatch command in pm_input_buf
; ---------------------------------------------------------------------------
pm_exec:
    push esi
    push edi
    push ebx

    cmp  dword [pm_input_len], 0
    je   .done

    ; exact matches
    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_help
    call pm_strcmp
    je   .help

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_ver
    call pm_strcmp
    je   .ver

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_clear
    call pm_strcmp
    je   .clear

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_exit
    call pm_strcmp
    je   .exit

    ; prefix matches
    mov  esi, pm_input_buf
    mov  edi, pm_str_pfx_echo
    call pm_startswith
    je   .echo

    mov  esi, pm_input_buf
    mov  edi, pm_str_pfx_calc
    call pm_startswith
    je   .calc

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_probe
    call pm_strcmp
    je   .probe

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_drivers
    call pm_strcmp
    je   .drivers

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_pci
    call pm_strcmp
    je   .pci

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_ifconfig
    call pm_strcmp
    je   .ifconfig

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_nicdbg
    call pm_strcmp
    je   .nicdbg

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_arp
    call pm_strcmp
    je   .arp

    mov  esi, pm_input_buf
    mov  edi, pm_str_pfx_arping
    call pm_startswith
    je   .arping

    mov  esi, pm_input_buf
    mov  edi, pm_str_pfx_ping
    call pm_startswith
    je   .ping

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_netdbg
    call pm_strcmp
    je   .netdbg

    ; unknown
    mov  esi, pm_str_unknown
    mov  bl, 0x0C
    call pm_puts
    jmp  .done

.help:  call pm_cmd_help
    jmp  .done
.ver:   call pm_cmd_ver
    jmp  .done
.clear: call pm_cmd_clear
    jmp  .done
.echo:  call pm_cmd_echo
    jmp  .done
.calc:  call pm_cmd_calc
    jmp  .done
.probe: call pm_cmd_probe
    jmp  .done
.drivers: call pm_cmd_drivers
    jmp  .done
.pci:       call cmd_pci
    jmp  .done
.ifconfig:  call cmd_ifconfig
    jmp  .done
.nicdbg:    call cmd_nicdbg
    jmp  .done
.arp:       call cmd_arp
    jmp  .done
.arping:    call cmd_arping
    jmp  .done
.ping:      call cmd_ping
    jmp  .done
.netdbg:    call cmd_netdbg
    jmp  .done
.exit:  call pm_cmd_exit       ; does not return to here

.done:
    pop  ebx
    pop  edi
    pop  esi
    ret

; ---------------------------------------------------------------------------
; Sub-modules
; ---------------------------------------------------------------------------
%include "pm/pm_screen.asm"
%include "pm/pm_keyboard.asm"
%include "pm/pm_string.asm"
%include "pm/pm_commands.asm"
%include "pm/pm_drivers.asm"
%include "pm/pm_data.asm"
%include "pm/mouse.asm"
%include "pm/terminal.asm"