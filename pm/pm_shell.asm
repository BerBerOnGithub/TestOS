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

    ; If VBE failed, skip the graphical WM entirely and use text-mode shell
    cmp  byte [vbe_ok], 1
    jne  .text_shell

    ; initialise window manager (draws desktop + taskbar)
    call wm_init

    ; try to load bitmap cursor from ClaudeFS
    call cursor_load_bmp

    ; load desktop icons from ClaudeFS
    call icons_init

    ; open the initial Terminal window — offset right to leave icon column
    mov  al,  WM_TERM
    mov  ebx, 110           ; x: leave 110px for icon column
    mov  ecx, 50
    mov  edx, 520           ; width: fills to x=630
    mov  esi, 340
    call wm_open            ; ECX = window index (ignored here)

    call wm_draw_all

    call term_init
    call mouse_init

.loop:
    call mouse_poll

    ; update icon hover state (for future use)
    call icons_hover

    ; check for window manager mouse events
    mov  al, [mouse_btn]
    mov  bl, [pm_prev_btn]

    ; left button just pressed?
    test al, 0x01
    jz   .check_drag
    test bl, 0x01
    jnz  .check_drag        ; was already held
    ; fresh press — check icons first
    mov  eax, [mouse_x]
    mov  ebx, [mouse_y]
    call icons_click
    jc   .btn_done          ; icon handled it
    mov  eax, [mouse_x]    ; reload — icons_click clobbers EAX/EBX
    mov  ebx, [mouse_y]
    call wm_on_click
    jmp  .btn_done

.check_drag:
    ; left held = drag
    test al, 0x01
    jz   .check_release
    mov  eax, [mouse_x]
    mov  ebx, [mouse_y]
    call wm_on_drag
    jmp  .btn_done

.check_release:
    test bl, 0x01
    jz   .btn_done
    call wm_on_release

.btn_done:
    mov  al, [mouse_btn]
    mov  [pm_prev_btn], al

    ; refresh live window content (clock ticks, etc.)
    call wm_update_contents

    ; process one keystroke (non-blocking)
    call term_tick

    jmp  .loop

; ---------------------------------------------------------------------------
; .text_shell — VBE unavailable; run text-mode PM shell instead
; ---------------------------------------------------------------------------
.text_shell:
    call pm_cls
    mov  esi, pm_str_novbe
    mov  bl,  0x0C
    call pm_puts
    call pm_newline

pm_shell_loop:
    mov  esi, pm_prompt
    mov  bl, 0x0A
    call pm_puts
    call pm_readline
    call pm_exec
    jmp  pm_shell_loop

; pm_gfx_test removed - window manager (wm.asm) now handles all drawing
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

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_clock
    call pm_strcmp
    je   .clock

    mov  esi, pm_input_buf
    mov  edi, pm_str_cmd_files
    call pm_strcmp
    je   .files

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
.clock:     call pm_cmd_clock
    jmp  .done
.files:     call pm_cmd_files
    jmp  .done
.exit:  call pm_cmd_exit       ; does not return to here

.done:
    pop  ebx
    pop  edi
    pop  esi
    ret

; ---------------------------------------------------------------------------
; pm_cmd_clock  — open a Clock window
; ---------------------------------------------------------------------------
pm_cmd_clock:
    pusha
    mov  al,  WM_CLOCK
    mov  ebx, 200
    mov  ecx, 150
    mov  edx, 180
    mov  esi, 80
    call wm_open            ; returns new index in ECX
    jc   .full
    push ecx                ; save window index
    call wm_draw_all
    pop  ecx                ; restore for wm_draw_clock
    call wm_draw_clock
    jmp  .done
.full:
    mov  esi, pm_str_wm_full
    call term_puts
    call term_newline
.done:
    popa
    ret

; ---------------------------------------------------------------------------
; pm_cmd_files  — open a Files window
; ---------------------------------------------------------------------------
pm_cmd_files:
    pusha
    mov  al,  WM_FILES
    mov  ebx, 160
    mov  ecx, 80
    mov  edx, 300
    mov  esi, 280
    call wm_open            ; returns new index in ECX
    jc   .full
    push ecx                ; save window index
    call wm_draw_all
    pop  ecx                ; restore for wm_draw_files
    call wm_draw_files
    jmp  .done
.full:
    mov  esi, pm_str_wm_full
    call term_puts
    call term_newline
.done:
    popa
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
%include "pm/fs_pm.asm"
%include "pm/wm.asm"
%include "pm/icons.asm"
