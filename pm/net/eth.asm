; ===========================================================================
; pm/net/eth.asm - Ethernet II framing layer
;
; Builds and parses Ethernet II frames.
; Calls e1000_send_frame / e1000_recv for TX/RX.
;
; Frame layout (14-byte header + payload):
;   [0]  6 bytes  destination MAC
;   [6]  6 bytes  source MAC (filled from e1000_mac)
;   [12] 2 bytes  EtherType (big-endian)
;   [14] N bytes  payload
;
; EtherTypes:
;   0x0806  ARP
;   0x0800  IPv4
;
; Public interface:
;   eth_send   ESI=payload, ECX=payload_len, EDI=dst_mac, DX=ethertype
;              -> CF=0 ok, CF=1 error
;   eth_recv   -> ESI=frame ptr, ECX=payload_len, DX=ethertype
;              -> CF=0 ok (packet waiting), CF=1 no packet
;              Caller must process before next eth_recv call (buffer reused)
; ===========================================================================

[BITS 32]

ETH_HEADER_LEN  equ 14
ETH_MAX_FRAME   equ 1514        ; 1500 payload + 14 header
ETH_MIN_FRAME   equ 60          ; minimum frame (padding added by NIC)

ETHERTYPE_ARP   equ 0x0806
ETHERTYPE_IPV4  equ 0x0800

; -
; eth_send - build and transmit an Ethernet II frame
;
; In:  ESI = payload pointer
;      ECX = payload length (bytes)
;      EDI = destination MAC pointer (6 bytes)
;      DX  = EtherType (host byte order, will be stored big-endian)
; Out: CF=0 success, CF=1 error
; -
eth_send:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; bounds check
    cmp  ecx, 1500
    ja   .err

    ; save payload info
    mov  [eth_tx_payload_ptr], esi
    mov  [eth_tx_payload_len], ecx
    mov  [eth_tx_ethertype],   dx

    ; - Build frame in eth_tx_buf -

    ; destination MAC (6 bytes from EDI)
    push esi
    push edi
    mov  esi, edi
    mov  edi, eth_tx_buf
    mov  ecx, 6
    rep  movsb

    ; source MAC (6 bytes from e1000_mac)
    mov  esi, e1000_mac
    mov  ecx, 6
    rep  movsb

    ; EtherType big-endian (swap bytes of DX)
    mov  ax, [eth_tx_ethertype]
    xchg al, ah
    mov  [edi], ax
    add  edi, 2

    ; payload
    mov  esi, [eth_tx_payload_ptr]
    mov  ecx, [eth_tx_payload_len]
    rep  movsb

    pop  edi
    pop  esi

    ; total frame length = 14 + payload
    mov  ecx, [eth_tx_payload_len]
    add  ecx, ETH_HEADER_LEN

    ; pad to minimum frame size if needed
    cmp  ecx, ETH_MIN_FRAME
    jge  .send
    ; zero-pad remainder
    push edi
    mov  edi, eth_tx_buf
    add  edi, ecx
    push ecx
    mov  ecx, ETH_MIN_FRAME
    sub  ecx, [eth_tx_payload_len]
    sub  ecx, ETH_HEADER_LEN
    xor  eax, eax
    rep  stosb
    pop  ecx
    pop  edi
    mov  ecx, ETH_MIN_FRAME

.send:
    mov  esi, eth_tx_buf
    call e1000_send_frame    ; ESI=frame, ECX=length -> CF
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

; -
; eth_recv - receive one Ethernet frame if available
;
; Out: CF=1  no packet
;      CF=0  packet received:
;              ESI = pointer to payload (eth_rx_buf + 14)
;              ECX = payload length
;              DX  = EtherType (host byte order)
;              eth_rx_dst_mac / eth_rx_src_mac populated
; -
eth_recv:
    push eax
    push edi

    mov  edi, eth_rx_buf
    call e1000_recv          ; EDI=buf -> ECX=total_len, CF

    jc   .no_packet
    test ecx, ecx
    jz   .no_packet
    cmp  ecx, ETH_HEADER_LEN
    jl   .no_packet

    ; copy dst/src MACs out of header for callers
    push esi
    push ecx
    mov  esi, eth_rx_buf
    push edi
    mov  edi, eth_rx_dst_mac
    mov  ecx, 6
    rep  movsb               ; dst MAC
    mov  edi, eth_rx_src_mac
    mov  ecx, 6
    rep  movsb               ; src MAC
    pop  edi
    pop  ecx
    pop  esi

    ; EtherType at offset 12 - stored big-endian, return host order
    mov  ax, [eth_rx_buf + 12]
    xchg al, ah
    mov  dx, ax
    mov  [eth_rx_ethertype], dx

    ; payload starts at offset 14
    mov  esi, eth_rx_buf + ETH_HEADER_LEN
    sub  ecx, ETH_HEADER_LEN  ; payload length

    clc
    jmp  .done

.no_packet:
    stc
.done:
    pop  edi
    pop  eax
    ret

; -
; Data
; -
eth_tx_buf:          times ETH_MAX_FRAME db 0
eth_rx_buf:          times ETH_MAX_FRAME db 0

eth_tx_payload_ptr:  dd 0
eth_tx_payload_len:  dd 0
eth_tx_ethertype:    dw 0

eth_rx_dst_mac:      times 6 db 0
eth_rx_src_mac:      times 6 db 0
eth_rx_ethertype:    dw 0