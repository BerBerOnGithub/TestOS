; ===========================================================================
; pm/net/udp.asm - UDP layer  (RFC 768)  -- VERBOSE DEBUG BUILD
; ===========================================================================

[BITS 32]

UDP_HDR_LEN         equ 8
UDP_MAX_PAYLOAD     equ 1472
UDP_EPHEMERAL_PORT  equ 49152

; ---------------------------------------------------------------------------
; udp_send
; ---------------------------------------------------------------------------
udp_send:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp  ecx, UDP_MAX_PAYLOAD
    ja   .err

    mov  [udp_tx_dst_ip],   eax
    mov  [udp_tx_src_port], bx
    mov  [udp_tx_dst_port], dx
    mov  [udp_tx_pld_ptr],  esi
    mov  [udp_tx_pld_len],  ecx

    mov  edi, udp_tx_buf

    mov  ax, [udp_tx_src_port]
    xchg al, ah
    mov  [edi + 0], ax

    mov  ax, [udp_tx_dst_port]
    xchg al, ah
    mov  [edi + 2], ax

    mov  eax, [udp_tx_pld_len]
    add  eax, UDP_HDR_LEN
    xchg al, ah
    mov  [edi + 4], ax

    mov  word [edi + 6], 0

    push esi
    push edi
    mov  esi, [udp_tx_pld_ptr]
    add  edi, UDP_HDR_LEN
    mov  ecx, [udp_tx_pld_len]
    rep  movsb
    pop  edi
    pop  esi

    mov  ecx, [udp_tx_pld_len]
    add  ecx, UDP_HDR_LEN
    mov  esi, udp_tx_buf
    mov  eax, [udp_tx_dst_ip]
    mov  bl,  IP_PROTO_UDP
    call ip_send
    jmp  .done

.err:
    stc
.done:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; udp_recv
; ---------------------------------------------------------------------------
udp_recv:
    push ebx
    push edx

    call ip_recv
    jc   .no_packet

    cmp  al, IP_PROTO_UDP
    jne  .no_packet

    cmp  ecx, UDP_HDR_LEN
    jl   .no_packet

    mov  eax, [ip_rx_src]
    mov  [udp_rx_src_ip], eax

    mov  ax, [esi + 0]
    xchg al, ah
    mov  [udp_rx_src_port], ax

    mov  ax, [esi + 2]
    xchg al, ah
    mov  [udp_rx_dst_port], ax

    mov  ax, [esi + 4]
    xchg al, ah
    movzx ecx, ax
    sub  ecx, UDP_HDR_LEN

    add  esi, UDP_HDR_LEN
    clc
    jmp  .done

.no_packet:
    stc
.done:
    pop  edx
    pop  ebx
    ret

; ---------------------------------------------------------------------------
; cmd_udplisten - VERBOSE DEBUG VERSION
; Every stage prints a [udp] marker so you can see exactly where it stops.
; Counter is in MEMORY (udp_listen_ticks) -- NOT in EDI/ECX -- so
; eth_recv cannot clobber it.
; ---------------------------------------------------------------------------
cmd_udplisten:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    call pm_newline

    ; STAGE 1
    mov  esi, pm_str_udp_dbg1
    mov  bl, 0x08
    call pm_puts
    call pm_newline

    ; skip "udplisten "  (10 chars including the space)
    mov  esi, pm_input_buf
    add  esi, 10

    ; STAGE 2 - show raw char at ESI before parsing
    mov  esi, pm_str_udp_dbg2
    mov  bl, 0x08
    call pm_puts
    mov  esi, pm_input_buf
    add  esi, 10
    movzx eax, byte [esi]
    call pm_print_hex8
    call pm_newline

    ; re-point and parse
    mov  esi, pm_input_buf
    add  esi, 10
    call pm_parse_uint
    test eax, eax
    jz   .usage
    cmp  eax, 65535
    ja   .usage
    mov  [udp_listen_port], ax

    ; STAGE 3
    mov  esi, pm_str_udp_dbg3
    mov  bl, 0x08
    call pm_puts
    movzx eax, word [udp_listen_port]
    call pm_print_uint
    call pm_newline

    ; user-facing banner
    mov  esi, pm_str_udp_listen
    mov  bl, 0x0B
    call pm_puts
    movzx eax, word [udp_listen_port]
    call pm_print_uint
    mov  esi, pm_str_udp_listen2
    mov  bl, 0x07
    call pm_puts
    call pm_newline

    ; STAGE 4
    mov  esi, pm_str_udp_dbg4
    mov  bl, 0x08
    call pm_puts
    call pm_newline

    mov  dword [udp_listen_ticks], 1500000

.poll:
    ; Print a heartbeat every 300000 ticks so we know the loop is alive
    mov  eax, [udp_listen_ticks]
    mov  ecx, 300000
    xor  edx, edx
    div  ecx                    ; EAX=quotient, EDX=remainder
    test edx, edx
    jnz  .skip_hb
    test eax, eax
    jz   .skip_hb
    mov  esi, pm_str_udp_hb
    mov  bl, 0x08
    call pm_puts
    mov  eax, [udp_listen_ticks]
    call pm_print_uint
    call pm_newline
.skip_hb:

    cmp  dword [udp_listen_ticks], 0
    je   .timeout

    ; STAGE 6 - call udp_recv (uses ip_recv -> eth_recv internally)
    call udp_recv
    jc   .no_pkt

    ; STAGE 7 - something came back
    mov  esi, pm_str_udp_dbg7
    mov  bl, 0x0A
    call pm_puts
    call pm_newline

    ; show what port arrived vs what we want
    mov  esi, pm_str_udp_dbg_dstport
    mov  bl, 0x08
    call pm_puts
    movzx eax, word [udp_rx_dst_port]
    call pm_print_uint
    mov  esi, pm_str_udp_dbg_wantport
    mov  bl, 0x08
    call pm_puts
    movzx eax, word [udp_listen_port]
    call pm_print_uint
    call pm_newline

    mov  ax, [udp_rx_dst_port]
    cmp  ax, [udp_listen_port]
    jne  .wrong_port

    ; STAGE 8 - port matched
    mov  esi, pm_str_udp_dbg8
    mov  bl, 0x08
    call pm_puts
    call pm_newline

    mov  esi, pm_str_udp_from
    mov  bl, 0x0A
    call pm_puts
    mov  eax, [udp_rx_src_ip]
    call pm_print_ip
    mov  al, ':'
    mov  bl, 0x07
    call pm_putc
    movzx eax, word [udp_rx_src_port]
    call pm_print_uint
    mov  al, ' '
    call pm_putc
    mov  al, '('
    call pm_putc
    mov  eax, ecx
    call pm_print_uint
    mov  esi, pm_str_udp_bytes
    mov  bl, 0x07
    call pm_puts
    call pm_newline

    ; STAGE 9 - hex dump first (safest, no encoding issues)
    mov  esi, pm_str_udp_dbg9
    mov  bl, 0x08
    call pm_puts
    call pm_newline

    push ecx
    push esi
.hexdump:
    test ecx, ecx
    jz   .hexdump_done
    movzx eax, byte [esi]
    call pm_print_hex8
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    inc  esi
    dec  ecx
    jmp  .hexdump
.hexdump_done:
    call pm_newline
    pop  esi
    pop  ecx

    ; STAGE 10 - text render
    mov  esi, pm_str_udp_dbg10
    mov  bl, 0x08
    call pm_puts
    call pm_newline

    push ecx
    push esi
.print_payload:
    test ecx, ecx
    jz   .payload_done
    movzx eax, byte [esi]
    cmp  al, 0x20
    jl   .non_print
    cmp  al, 0x7E
    jle  .printable
.non_print:
    mov  al, '.'
.printable:
    mov  bl, 0x0F
    call pm_putc
    inc  esi
    dec  ecx
    jmp  .print_payload
.payload_done:
    pop  esi
    pop  ecx
    call pm_newline

    mov  esi, pm_str_udp_dbg_done
    mov  bl, 0x0A
    call pm_puts
    call pm_newline
    jmp  .done

.wrong_port:
    mov  esi, pm_str_udp_dbg_wrongport
    mov  bl, 0x08
    call pm_puts
    call pm_newline

.no_pkt:
    dec  dword [udp_listen_ticks]
    jmp  .poll

.timeout:
    mov  esi, pm_str_udp_timeout
    mov  bl, 0x0C
    call pm_puts
    call pm_newline
    mov  esi, pm_str_udp_dbg_timedout
    mov  bl, 0x08
    call pm_puts
    call pm_newline
    jmp  .done

.usage:
    mov  esi, pm_str_udplisten_usage
    mov  bl, 0x0E
    call pm_puts

.done:
    call pm_newline
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; cmd_udpsend
; ---------------------------------------------------------------------------
cmd_udpsend:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    call pm_newline

    mov  esi, pm_str_udp_dbg_s1
    mov  bl, 0x08
    call pm_puts
    call pm_newline

    mov  esi, pm_input_buf
    add  esi, 8

    call pm_parse_ip
    test eax, eax
    jz   .usage
    mov  [udp_cmd_dst_ip], eax

    mov  esi, pm_str_udp_dbg_s2
    mov  bl, 0x08
    call pm_puts
    mov  eax, [udp_cmd_dst_ip]
    call pm_print_ip
    call pm_newline

    call pm_parse_uint
    test eax, eax
    jz   .usage
    cmp  eax, 65535
    ja   .usage
    mov  [udp_cmd_dst_port], ax

    mov  esi, pm_str_udp_dbg_s3
    mov  bl, 0x08
    call pm_puts
    movzx eax, word [udp_cmd_dst_port]
    call pm_print_uint
    call pm_newline

    ; ESI now points at message text
    mov  edi, esi
    xor  ecx, ecx
.msglen:
    cmp  byte [edi], 0
    je   .gotslen
    inc  edi
    inc  ecx
    jmp  .msglen
.gotslen:
    test ecx, ecx
    jz   .usage

    mov  esi, pm_str_udp_sending
    mov  bl, 0x0B
    call pm_puts
    mov  eax, [udp_cmd_dst_ip]
    call pm_print_ip
    mov  al, ':'
    mov  bl, 0x07
    call pm_putc
    movzx eax, word [udp_cmd_dst_port]
    call pm_print_uint
    mov  al, ' '
    call pm_putc
    mov  al, '('
    call pm_putc
    mov  eax, ecx
    call pm_print_uint
    mov  esi, pm_str_udp_bytes
    mov  bl, 0x07
    call pm_puts
    call pm_newline

    mov  esi, edi
    sub  esi, ecx
    mov  eax, [udp_cmd_dst_ip]
    mov  bx,  UDP_EPHEMERAL_PORT
    mov  dx,  [udp_cmd_dst_port]
    call udp_send
    jc   .send_err

    mov  esi, pm_str_udp_sent
    mov  bl, 0x0A
    call pm_puts
    jmp  .done

.send_err:
    mov  esi, pm_str_udp_err
    mov  bl, 0x0C
    call pm_puts
    jmp  .done

.usage:
    mov  esi, pm_str_udpsend_usage
    mov  bl, 0x0E
    call pm_puts

.done:
    call pm_newline
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
udp_tx_buf:         times (UDP_HDR_LEN + UDP_MAX_PAYLOAD) db 0

udp_tx_dst_ip:      dd 0
udp_tx_src_port:    dw 0
udp_tx_dst_port:    dw 0
udp_tx_pld_ptr:     dd 0
udp_tx_pld_len:     dd 0

udp_rx_src_ip:      dd 0
udp_rx_src_port:    dw 0
udp_rx_dst_port:    dw 0

udp_cmd_dst_ip:     dd 0
udp_cmd_dst_port:   dw 0
udp_listen_port:    dw 0
udp_listen_ticks:   dd 0

; user-facing
pm_str_udp_sending:     db ' Sending UDP to ', 0
pm_str_udp_bytes:       db ' bytes)', 0
pm_str_udp_sent:        db ' Sent.', 0
pm_str_udp_err:         db ' Error: ARP miss or TX fail', 0
pm_str_udpsend_usage:   db ' Usage: udpsend <ip> <port> <message>', 13, 10
                        db '   e.g. udpsend 10.0.2.2 9 hello', 0
pm_str_udp_listen:      db ' Listening on UDP port ', 0
pm_str_udp_listen2:     db ' (timeout 3s) ...', 0
pm_str_udp_from:        db ' Packet from ', 0
pm_str_udp_timeout:     db ' Timeout -- no packet received.', 0
pm_str_udplisten_usage: db ' Usage: udplisten <port>', 13, 10
                        db '   e.g. udplisten 5000', 0

; debug (attr 0x08 = dark grey)
pm_str_udp_dbg1:         db '[udp] entered cmd_udplisten', 0
pm_str_udp_dbg2:         db '[udp] first char at esi+10 = 0x', 0
pm_str_udp_dbg3:         db '[udp] port parsed = ', 0
pm_str_udp_dbg4:         db '[udp] entering poll loop (mem counter)', 0
pm_str_udp_hb:           db '[udp] heartbeat ticks=', 0
pm_str_udp_dbg7:         db '[udp] got UDP packet!', 0
pm_str_udp_dbg8:         db '[udp] port match -- delivering', 0
pm_str_udp_dbg9:         db '[udp] hex dump:', 0
pm_str_udp_dbg10:        db '[udp] text:', 0
pm_str_udp_dbg_done:     db '[udp] done.', 0
pm_str_udp_dbg_timedout: db '[udp] exited via timeout', 0
pm_str_udp_dbg_wrongport: db '[udp] wrong port -- ignored', 0
pm_str_udp_dbg_dstport:  db '[udp] pkt.dstport=', 0
pm_str_udp_dbg_wantport: db '  want=', 0
pm_str_udp_dbg_s1:       db '[udp] entered cmd_udpsend', 0
pm_str_udp_dbg_s2:       db '[udp] dst IP=', 0
pm_str_udp_dbg_s3:       db '[udp] dst port=', 0