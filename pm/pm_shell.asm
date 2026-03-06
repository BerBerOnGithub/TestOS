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

    ; Initialise PM drivers (screen, keyboard, PIT, speaker)
    call pm_drv_init

    mov  esi, pm_banner
    mov  bl, 0x0B
    call pm_puts

pm_shell_loop:
    mov  esi, pm_prompt
    mov  bl, 0x0A
    call pm_puts
    call pm_readline
    call pm_exec
    jmp  pm_shell_loop

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