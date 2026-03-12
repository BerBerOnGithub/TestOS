; ===========================================================================
; pm/net/icmp.asm - ICMP  (RFC 792)
;
; Implements:
;   - Echo Request (type 8) → ping
;   - Echo Reply   (type 0) ← response to our ping
;   - Handles incoming Echo Requests and sends replies
;
; ICMP Echo header (8 bytes) + data:
;   [0]  type      1   8=request, 0=reply
;   [1]  code      1   0
;   [2]  checksum  2   BE ones-complement of entire ICMP message
;   [4]  ident     2   BE  (our PID equivalent)
;   [6]  seq       2   BE
;   [8+] data      N   arbitrary payload
;
; Public interface:
;   icmp_send_echo  EAX=dst_ip, CX=seq → CF
;   icmp_process    ESI=icmp_payload, ECX=len, EAX=src_ip
;   cmd_ping        shell command: ping <ip> [count]
; ===========================================================================

[BITS 32]

ICMP_TYPE_REPLY   equ 0
ICMP_TYPE_REQUEST equ 8
ICMP_HDR_LEN      equ 8
ICMP_DATA_LEN     equ 32        ; bytes of padding per echo
ICMP_IDENT        equ 0x4F53   ; 'OS'

; ---------------------------------------------------------------------------
; icmp_checksum - ones-complement checksum, identical to ip_checksum
; but called separately so ICMP can compute over its own buffer
; In: ESI=buf, ECX=len → AX=checksum (host order, ready to NOT and store)
; ---------------------------------------------------------------------------
icmp_checksum equ ip_checksum   ; exact same algorithm — reuse

; ---------------------------------------------------------------------------
; icmp_send_echo - send one ICMP Echo Request
;
; In:  EAX = destination IP (host order)
;      CX  = sequence number
; Out: CF=0 ok, CF=1 error
; ---------------------------------------------------------------------------
icmp_send_echo:
    push eax
    push ebx
    push ecx
    push esi
    push edi

    mov  [icmp_tx_dst], eax
    movzx eax, cx
    mov  [icmp_tx_seq], ax

    ; ── Build ICMP echo request in icmp_tx_buf ───────────────────────────
    mov  edi, icmp_tx_buf

    mov  byte [edi + 0], ICMP_TYPE_REQUEST
    mov  byte [edi + 1], 0       ; code

    ; checksum = 0 placeholder
    mov  word [edi + 2], 0

    ; identifier (big-endian)
    mov  ax, ICMP_IDENT
    xchg al, ah
    mov  [edi + 4], ax

    ; sequence (big-endian)
    mov  ax, [icmp_tx_seq]
    xchg al, ah
    mov  [edi + 6], ax

    ; fill data payload with 'A'..'Z' pattern
    mov  ecx, ICMP_DATA_LEN
    mov  edi, icmp_tx_buf + ICMP_HDR_LEN
    xor  eax, eax
.fill:
    mov  al, cl
    add  al, 'A' - 1
    cmp  al, 'Z'
    jle  .store
    sub  al, 26
.store:
    mov  [edi], al
    inc  edi
    loop .fill

    ; compute checksum over header + data
    mov  esi, icmp_tx_buf
    mov  ecx, ICMP_HDR_LEN + ICMP_DATA_LEN
    call ip_checksum             ; AX = checksum (network order, ready to store)
    mov  [icmp_tx_buf + 2], ax

    ; send via IP
    mov  esi, icmp_tx_buf
    mov  ecx, ICMP_HDR_LEN + ICMP_DATA_LEN
    mov  eax, [icmp_tx_dst]
    mov  bl,  IP_PROTO_ICMP
    call ip_send

    pop  edi
    pop  esi
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; icmp_process - handle incoming ICMP packet
;
; In:  ESI = ICMP message pointer
;      ECX = length
;      EAX = source IP (host order, from IP layer)
; ---------------------------------------------------------------------------
icmp_process:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    cmp  ecx, ICMP_HDR_LEN
    jl   .done

    mov  [icmp_rx_src], eax

    mov  al, [esi + 0]       ; type
    cmp  al, ICMP_TYPE_REPLY
    je   .is_reply
    cmp  al, ICMP_TYPE_REQUEST
    je   .is_request
    jmp  .done

.is_reply:
    ; check ident matches ours
    mov  ax, [esi + 4]
    xchg al, ah              ; to host order
    cmp  ax, ICMP_IDENT
    jne  .done

    ; extract sequence
    mov  ax, [esi + 6]
    xchg al, ah
    mov  [icmp_rx_seq], ax

    ; signal reply received
    mov  byte [icmp_got_reply], 1
    jmp  .done

.is_request:
    ; send echo reply: copy request, change type to 0, recompute checksum
    ; copy entire ICMP message to tx buf
    push esi
    push edi
    mov  edi, icmp_reply_buf
    push ecx
    rep  movsb
    pop  ecx
    pop  edi
    pop  esi

    ; change type to reply
    mov  byte [icmp_reply_buf + 0], ICMP_TYPE_REPLY
    mov  word [icmp_reply_buf + 2], 0   ; zero checksum

    ; recompute checksum
    push esi
    push ecx
    mov  esi, icmp_reply_buf
    call ip_checksum         ; AX = checksum (network order, ready to store)
    mov  [icmp_reply_buf + 2], ax
    pop  ecx
    pop  esi

    ; send reply
    push esi
    push ecx
    mov  esi, icmp_reply_buf
    mov  eax, [icmp_rx_src]
    mov  bl,  IP_PROTO_ICMP
    call ip_send
    pop  ecx
    pop  esi

.done:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; icmp_poll - receive and dispatch one IP packet, handle ICMP
; Called in a loop by cmd_ping
; ---------------------------------------------------------------------------
icmp_poll:
    push eax
    push ecx
    push edx
    push esi

    call eth_recv            ; CF=1 nothing; CF=0: ESI=payload, ECX=len, DX=ethertype
    jc   .done

    cmp  dx, ETHERTYPE_ARP
    jne  .not_arp
    call arp_process         ; drain ARP packets (QEMU sends these on boot)
    jmp  .done

.not_arp:
    cmp  dx, ETHERTYPE_IPV4
    jne  .done

    ; parse IPv4 header inline
    cmp  ecx, IP_HDR_LEN
    jl   .done
    cmp  byte [esi], 0x45
    jne  .done
    cmp  byte [esi + 9], IP_PROTO_ICMP
    jne  .done

    mov  eax, [esi + 12]
    bswap eax
    mov  [ip_rx_src], eax

    mov  bx, [esi + 2]
    xchg bl, bh
    movzx ecx, bx
    sub  ecx, IP_HDR_LEN
    add  esi, IP_HDR_LEN

    mov  eax, [ip_rx_src]
    call icmp_process

.done:
    pop  esi
    pop  edx
    pop  ecx
    pop  eax
    ret

; ---------------------------------------------------------------------------
; cmd_ping - send ICMP echo requests to <ip>, print replies
; Usage: ping <ip>
; Sends 4 packets, waits up to ~1s each
; ---------------------------------------------------------------------------
cmd_ping:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; parse destination IP
    mov  esi, pm_input_buf
    add  esi, 5              ; skip "ping "
    call pm_parse_ip         ; EAX = dst ip
    test eax, eax
    jz   .usage

    mov  [ping_dst], eax

    call pm_newline
    mov  esi, pm_str_ping_hdr
    mov  bl, 0x0B
    call pm_puts
    mov  eax, [ping_dst]
    call pm_print_ip
    mov  al, ':'
    mov  bl, 0x07
    call pm_putc
    call pm_newline

    ; send 4 pings
    mov  dword [ping_seq], 1
    mov  dword [ping_sent], 0
    mov  dword [ping_recv], 0

.ping_loop:
    cmp  dword [ping_seq], 5
    jge  .summary

    ; send echo request
    mov  byte [icmp_got_reply], 0
    mov  eax, [ping_dst]
    movzx ecx, word [ping_seq]
    call icmp_send_echo
    jc   .send_fail

    inc  dword [ping_sent]

    ; print "seq N ..."
    mov  esi, pm_str_ping_seq
    mov  bl, 0x07
    call pm_puts
    mov  eax, [ping_seq]
    call pm_print_uint
    mov  esi, pm_str_ping_wait
    mov  bl, 0x07
    call pm_puts

    ; poll for reply — ~500000 iterations ≈ 1 second
    mov  ecx, 500000
.wait:
    call icmp_poll
    cmp  byte [icmp_got_reply], 1
    je   .got_reply
    loop .wait

    ; timeout
    mov  esi, pm_str_ping_timeout
    mov  bl, 0x0C
    call pm_puts
    call pm_newline
    jmp  .next

.got_reply:
    inc  dword [ping_recv]
    mov  esi, pm_str_ping_reply
    mov  bl, 0x0A
    call pm_puts
    mov  eax, [ping_dst]
    call pm_print_ip
    mov  esi, pm_str_ping_seq2
    mov  bl, 0x07
    call pm_puts
    mov  eax, [ping_seq]
    call pm_print_uint
    call pm_newline
    jmp  .next

.send_fail:
    mov  esi, pm_str_ping_no_route
    mov  bl, 0x0C
    call pm_puts
    call pm_newline
    jmp  .next

.next:
    inc  dword [ping_seq]
    jmp  .ping_loop

.summary:
    call pm_newline
    mov  esi, pm_str_ping_stats
    mov  bl, 0x0B
    call pm_puts
    mov  eax, [ping_sent]
    call pm_print_uint
    mov  esi, pm_str_ping_tx
    mov  bl, 0x07
    call pm_puts
    mov  eax, [ping_recv]
    call pm_print_uint
    mov  esi, pm_str_ping_rx
    mov  bl, 0x07
    call pm_puts
    call pm_newline
    jmp  .done

.usage:
    mov  esi, pm_str_ping_usage
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
icmp_tx_buf:     times (ICMP_HDR_LEN + ICMP_DATA_LEN) db 0
icmp_reply_buf:  times 1500 db 0
icmp_tx_dst:     dd 0
icmp_tx_seq:     dw 0
icmp_rx_src:     dd 0
icmp_rx_seq:     dw 0
icmp_got_reply:  db 0

ping_dst:        dd 0
ping_seq:        dd 0
ping_sent:       dd 0
ping_recv:       dd 0

pm_str_ping_hdr:      db ' Pinging ', 0
pm_str_ping_seq:      db '  seq=', 0
pm_str_ping_wait:     db ' ... ', 0
pm_str_ping_reply:    db 'reply from ', 0
pm_str_ping_seq2:     db ' seq=', 0
pm_str_ping_timeout:  db 'timeout', 0
pm_str_ping_no_route: db 'no route (ARP miss)', 0
pm_str_ping_stats:    db ' --- stats: ', 0
pm_str_ping_tx:       db ' sent, ', 0
pm_str_ping_rx:       db ' received', 0
pm_str_ping_usage:    db ' Usage: ping <ip>  e.g. ping 10.0.2.2', 13, 10, 0

; ---------------------------------------------------------------------------
; cmd_netdbg - comprehensive NIC diagnostics
; ---------------------------------------------------------------------------
cmd_netdbg:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    call pm_newline

    ; == Section 1: NIC state ===============================================
    mov  esi, pm_str_ndbg_hdr1
    mov  bl, 0x0B
    call pm_puts

    ; e1000_ready
    mov  esi, pm_str_ndbg_ready
    mov  bl, 0x07
    call pm_puts
    movzx eax, byte [e1000_ready]
    call pm_print_hex32
    call pm_newline

    ; PCI Command register
    mov  esi, pm_str_ndbg_pcicmd
    mov  bl, 0x07
    call pm_puts
    mov  bl,  [pci_e1000_bus]
    mov  bh,  [pci_e1000_dev]
    xor  cl, cl
    mov  ch, 0x04
    call pci_make_addr
    call pci_read32
    call pm_print_hex32
    call pm_newline

    ; BAR0
    mov  esi, pm_str_ndbg_bar0
    mov  bl, 0x07
    call pm_puts
    mov  eax, [pci_e1000_bar0]
    call pm_print_hex32
    call pm_newline

    ; CTRL
    mov  esi, pm_str_ndbg_ctrl
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_CTRL
    call e1000_mmio_read
    call pm_print_hex32
    call pm_newline

    ; STATUS
    mov  esi, pm_str_ndbg_status
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_STATUS
    call e1000_mmio_read
    call pm_print_hex32
    call pm_newline

    ; RCTL
    mov  esi, pm_str_ndbg_rctlv
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_RCTL
    call e1000_mmio_read
    call pm_print_hex32
    call pm_newline

    ; TCTL
    mov  esi, pm_str_ndbg_tctlv
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_TCTL
    call e1000_mmio_read
    call pm_print_hex32
    call pm_newline

    ; RAL0 / RAH0
    mov  esi, pm_str_ndbg_ral0
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_RAL0
    call e1000_mmio_read
    call pm_print_hex32
    mov  esi, pm_str_ndbg_slash
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_RAH0
    call e1000_mmio_read
    call pm_print_hex32
    call pm_newline

    ; TDH / TDT
    mov  esi, pm_str_ndbg_tdhdt
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_TDH
    call e1000_mmio_read
    call pm_print_hex32
    mov  esi, pm_str_ndbg_slash
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_TDT
    call e1000_mmio_read
    call pm_print_hex32
    call pm_newline

    ; RDH / RDT / sw tail
    mov  esi, pm_str_ndbg_rdhdtreg
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_RDH
    call e1000_mmio_read
    call pm_print_hex32
    mov  esi, pm_str_ndbg_slash
    mov  bl, 0x07
    call pm_puts
    mov  edx, E1000_RDT
    call e1000_mmio_read
    call pm_print_hex32
    mov  esi, pm_str_ndbg_swtail
    mov  bl, 0x07
    call pm_puts
    mov  eax, [e1000_rx_tail]
    call pm_print_hex32
    call pm_newline

    ; TX desc[0] status byte
    mov  esi, pm_str_ndbg_txd0
    mov  bl, 0x07
    call pm_puts
    movzx eax, byte [E1000_TX_DESC_BASE + 12]
    call pm_print_hex32
    call pm_newline

    ; RX desc[0] status byte
    mov  esi, pm_str_ndbg_rxd0
    mov  bl, 0x07
    call pm_puts
    movzx eax, byte [E1000_RX_DESC_BASE + 11]
    call pm_print_hex32
    call pm_newline

    ; == Section 2: IP config ===============================================
    mov  esi, pm_str_ndbg_hdr2
    mov  bl, 0x0B
    call pm_puts

    mov  esi, pm_str_ndbg_ourip
    mov  bl, 0x07
    call pm_puts
    mov  eax, [net_our_ip]
    call pm_print_ip
    call pm_newline

    mov  esi, pm_str_ndbg_gw
    mov  bl, 0x07
    call pm_puts
    mov  eax, [net_our_gw]
    call pm_print_ip
    call pm_newline

    mov  esi, pm_str_ndbg_gwmac
    mov  bl, 0x07
    call pm_puts
    mov  eax, [net_our_gw]
    call arp_resolve
    jc   .no_gw_mac
    mov  edi, esi
    mov  ecx, 6
.gmac:
    movzx eax, byte [edi]
    call pm_print_hex8
    inc  edi
    cmp  ecx, 1
    je   .gmac_done
    push eax
    mov  al, ':'
    mov  bl, 0x07
    call pm_putc
    pop  eax
.gmac_done:
    loop .gmac
    call pm_newline
    jmp  .do_send

.no_gw_mac:
    mov  esi, pm_str_ndbg_nomac
    mov  bl, 0x0C
    call pm_puts
    jmp  .done

    ; == Section 3: TX test =================================================
.do_send:
    mov  esi, pm_str_ndbg_hdr3
    mov  bl, 0x0B
    call pm_puts

    ; dump RX desc[0] raw bytes BEFORE send
    mov  esi, pm_str_ndbg_rxd_pre
    mov  bl, 0x0E
    call pm_puts
    mov  edi, E1000_RX_DESC_BASE
    mov  ecx, 16
.rxd_pre_loop:
    movzx eax, byte [edi]
    call pm_print_hex8
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    inc  edi
    loop .rxd_pre_loop
    call pm_newline

    ; snapshot TDH/TDT before send
    mov  edx, E1000_TDH
    call e1000_mmio_read
    mov  [ndbg_tdh_before], eax
    mov  edx, E1000_TDT
    call e1000_mmio_read
    mov  [ndbg_tdt_before], eax

    mov  byte [icmp_got_reply], 0
    mov  eax, [net_our_gw]
    mov  cx, 1
    call icmp_send_echo
    jc   .send_err

    ; small delay to let QEMU process - do some MMIO reads
    mov  ecx, 10
.qemu_yield:
    mov  edx, E1000_STATUS
    call e1000_mmio_read
    loop .qemu_yield

    ; dump RX desc[0] raw bytes AFTER send (QEMU may have written reply already)
    mov  esi, pm_str_ndbg_rxd_post
    mov  bl, 0x0E
    call pm_puts
    mov  edi, E1000_RX_DESC_BASE
    mov  ecx, 16
.rxd_post_loop:
    movzx eax, byte [edi]
    call pm_print_hex8
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    inc  edi
    loop .rxd_post_loop
    call pm_newline

    ; snapshot TDH/TDT after send
    mov  edx, E1000_TDH
    call e1000_mmio_read
    mov  [ndbg_tdh_after], eax
    mov  edx, E1000_TDT
    call e1000_mmio_read
    mov  [ndbg_tdt_after], eax

    mov  esi, pm_str_ndbg_txbefore
    mov  bl, 0x07
    call pm_puts
    mov  eax, [ndbg_tdh_before]
    call pm_print_hex32
    mov  esi, pm_str_ndbg_slash
    mov  bl, 0x07
    call pm_puts
    mov  eax, [ndbg_tdt_before]
    call pm_print_hex32
    call pm_newline

    mov  esi, pm_str_ndbg_txafter
    mov  bl, 0x07
    call pm_puts
    mov  eax, [ndbg_tdh_after]
    call pm_print_hex32
    mov  esi, pm_str_ndbg_slash
    mov  bl, 0x07
    call pm_puts
    mov  eax, [ndbg_tdt_after]
    call pm_print_hex32
    call pm_newline

    ; TX IP header
    mov  esi, pm_str_ndbg_txhdr
    mov  bl, 0x07
    call pm_puts
    mov  edi, ip_tx_buf
    mov  ecx, 20
.tx_dump:
    movzx eax, byte [edi]
    call pm_print_hex8
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    inc  edi
    loop .tx_dump
    call pm_newline

    ; == Section 4: RX wait =================================================
    mov  esi, pm_str_ndbg_hdr4
    mov  bl, 0x0B
    call pm_puts

    mov  esi, pm_str_ndbg_waiting
    mov  bl, 0x07
    call pm_puts

    mov  dword [ndbg_poll], 2000000
    mov  dword [ndbg_rdh_last], 0
.poll:
    ; check if RDH moved (NIC received something)
    mov  edx, E1000_RDH
    call e1000_mmio_read
    cmp  eax, [ndbg_rdh_last]
    je   .poll_recv
    ; RDH changed - show it
    mov  [ndbg_rdh_last], eax
    mov  esi, pm_str_ndbg_rdhchg
    mov  bl, 0x0A
    call pm_puts
    call pm_print_hex32
    call pm_newline

    ; ← ADD HERE: dump all 16 bytes of RX desc[0]
    push ecx
    push edi
    mov  edi, E1000_RX_DESC_BASE
    mov  ecx, 16
.dump_rdh:
    movzx eax, byte [edi]
    call pm_print_hex8
    mov  al, ' '
    mov  bl, 0x07
    call pm_putc
    inc  edi
    loop .dump_rdh
    call pm_newline
    pop  edi
    pop  ecx

.poll_recv:
    call eth_recv
    jc   .no_rx

    ; dispatch by ethertype
    cmp  dx, ETHERTYPE_ARP
    jne  .not_arp
    call arp_process
    jmp  .poll
.not_arp:
    cmp  dx, ETHERTYPE_IPV4
    jne  .poll

   ;it's IPv4 — parse the IP header ourselves (packet already in ESI/ECX)
    cmp  ecx, IP_HDR_LEN
    jl   .poll
    cmp  byte [esi], 0x45    ; version 4, no options
    jne  .poll
    cmp  byte [esi + 9], IP_PROTO_ICMP
    jne  .poll

    ; extract src IP
    mov  eax, [esi + 12]
    bswap eax
    mov  [ip_rx_src], eax

    ; get payload length from IP total length field
    mov  bx, [esi + 2]
    xchg bl, bh
    movzx ecx, bx
    sub  ecx, IP_HDR_LEN

    ; advance ESI past IP header to ICMP payload
    add  esi, IP_HDR_LEN

    ; call icmp_process with ESI=icmp payload, ECX=len, EAX=src_ip
    mov  eax, [ip_rx_src]
    call icmp_process

    cmp  byte [icmp_got_reply], 1
    jne  .poll

    ; got our ping reply!
    mov  esi, pm_str_ndbg_rx
    mov  bl, 0x0A
    call pm_puts
    call pm_newline
    jmp  .rx_done

.no_rx:
    dec  dword [ndbg_poll]
    jnz  .poll

    ; timeout - final register dump
    call pm_newline
    mov  esi, pm_str_ndbg_rdh
    mov  bl, 0x0C
    call pm_puts
    mov  edx, E1000_RDH
    call e1000_mmio_read
    call pm_print_hex32
    mov  esi, pm_str_ndbg_rdt
    mov  bl, 0x0C
    call pm_puts
    mov  edx, E1000_RDT
    call e1000_mmio_read
    call pm_print_hex32
    mov  esi, pm_str_ndbg_tail
    mov  bl, 0x0C
    call pm_puts
    mov  eax, [e1000_rx_tail]
    call pm_print_hex32
    call pm_newline

    ; TDH after wait (did NIC consume TX desc?)
    mov  esi, pm_str_ndbg_tdhfinal
    mov  bl, 0x0C
    call pm_puts
    mov  edx, E1000_TDH
    call e1000_mmio_read
    call pm_print_hex32
    call pm_newline

    mov  esi, pm_str_ndbg_norx
    mov  bl, 0x0C
    call pm_puts
    jmp  .done

.send_err:
    mov  esi, pm_str_ndbg_senderr
    mov  bl, 0x0C
    call pm_puts
    jmp  .done

.rx_done:
.done:
    call pm_newline
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret

ndbg_poll:       dd 0
ndbg_rdh_last:   dd 0
ndbg_tdh_before: dd 0
ndbg_tdt_before: dd 0
ndbg_tdh_after:  dd 0
ndbg_tdt_after:  dd 0

pm_str_ndbg_hdr1:    db ' [1] NIC Hardware State', 13, 10, 0
pm_str_ndbg_hdr2:    db ' [2] Network Config', 13, 10, 0
pm_str_ndbg_hdr3:    db ' [3] TX Test', 13, 10, 0
pm_str_ndbg_hdr4:    db ' [4] RX Wait', 13, 10, 0
pm_str_ndbg_ready:   db '  e1000_ready : ', 0
pm_str_ndbg_pcicmd:  db '  PCI Command : ', 0
pm_str_ndbg_bar0:    db '  BAR0        : ', 0
pm_str_ndbg_ctrl:    db '  CTRL        : ', 0
pm_str_ndbg_status:  db '  STATUS      : ', 0
pm_str_ndbg_rctlv:   db '  RCTL        : ', 0
pm_str_ndbg_tctlv:   db '  TCTL        : ', 0
pm_str_ndbg_ral0:    db '  RAL0/RAH0   : ', 0
pm_str_ndbg_slash:   db ' / ', 0
pm_str_ndbg_tdhdt:   db '  TDH/TDT     : ', 0
pm_str_ndbg_rdhdtreg: db '  RDH/RDT/sw  : ', 0
pm_str_ndbg_swtail:  db ' / sw=', 0
pm_str_ndbg_txd0:    db '  TXdesc[0].s : ', 0
pm_str_ndbg_rxd0:    db '  RXdesc[0].s : ', 0
pm_str_ndbg_ourip:   db '  Our IP      : ', 0
pm_str_ndbg_gw:      db '  Gateway     : ', 0
pm_str_ndbg_gwmac:   db '  GW MAC      : ', 0
pm_str_ndbg_nomac:   db '  No GW MAC in ARP cache!', 13, 10, 0
pm_str_ndbg_rxd_pre:  db '  RXdesc[0] pre : ', 0
pm_str_ndbg_rxd_post: db '  RXdesc[0] post: ', 0
pm_str_ndbg_txbefore: db '  TDH/TDT pre : ', 0
pm_str_ndbg_txafter:  db '  TDH/TDT post: ', 0
pm_str_ndbg_txhdr:   db '  TX IP hdr   : ', 0
pm_str_ndbg_waiting: db '  Polling...', 13, 10, 0
pm_str_ndbg_rdhchg:  db '  RDH moved-> ', 0
pm_str_ndbg_rx:  db ' Got ICMP reply!', 13, 10, 0
pm_str_ndbg_rxdata:  db ' : ', 0
pm_str_ndbg_rdh:     db '  RDH=', 0
pm_str_ndbg_rdt:     db '  RDT=', 0
pm_str_ndbg_tail:    db '  sw=', 0
pm_str_ndbg_tdhfinal: db '  TDH final   : ', 0
pm_str_ndbg_norx:    db '  Nothing received.', 13, 10, 0
pm_str_ndbg_senderr: db '  Send failed (CF=1 from icmp_send_echo)', 13, 10, 0