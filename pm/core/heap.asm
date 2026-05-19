; ===========================================================================
; pm/core/heap.asm - Kernel Dynamic Heap Allocator (kmalloc / kfree)
; ===========================================================================

[BITS 32]

HEAP_BASE  equ 0x2000000
HEAP_SIZE  equ 33554432       ; 32MB

; Block Header (8 bytes):
;   [0..3] Size of payload (excluding header)
;   [4..7] Flags (bit 0: 1=Used, 0=Free, bit 1: 1=IsLast)

heap_total_free: dd HEAP_SIZE

heap_init:
    pusha
    mov  edi, HEAP_BASE
    ; Create one massive free block
    mov  eax, HEAP_SIZE - 8   ; total size minus this header
    mov  [edi], eax
    mov  dword [edi + 4], 2   ; Free (Used=0), IsLast=1
    popa
    ret

; -
; kmalloc
; In:  ECX = size in bytes
; Out: EAX = pointer to payload (CF=0) or error (CF=1)
; -
kmalloc:
    pushad              ; Save ALL registers (EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI)
    
    ; Log requested size
    mov  esi, heap_msg_km
    call serial_print
    mov  eax, ecx
    call serial_print_hex32
    mov  esi, heap_msg_km2
    call serial_print
    
    ; align size for safety
    add  ecx, 3
    and  ecx, 0xFFFFFFFC
    
    mov  esi, HEAP_BASE
.search:
    mov  eax, [esi]           ; block size
    mov  ebx, [esi + 4]       ; block flags
    
    test ebx, 1               ; Used?
    jnz  .next_block
    
    cmp  eax, ecx
    jl   .next_block          ; too small
    
    mov  edx, ecx
    add  edx, 12
    cmp  eax, edx
    jl   .take_whole
    
.split:
    mov  edx, eax
    sub  edx, ecx
    sub  edx, 8
    
    mov  [esi], ecx
    mov  dword [esi + 4], 1   ; Used=1
    
    mov  edi, esi
    add  edi, 8
    add  edi, ecx             ; EDI = next block header
    mov  [edi], edx
    and  ebx, 2               ; carry over IsLast
    mov  [edi + 4], ebx
    
    sub  dword [heap_total_free], ecx
    sub  dword [heap_total_free], 8
    
    mov  eax, esi
    add  eax, 8
    
    ; Log result
    push eax
    call serial_print_hex32
    
    ; print tag if provided in EDX
    mov  edx, [esp + 24]
    test edx, edx
    jz   .km_no_tag
    mov  esi, heap_msg_for
    call serial_print
    mov  esi, edx
    call serial_print
.km_no_tag:
    mov  esi, heap_msg_nl
    call serial_print
    pop  eax

    mov  [esp + 28], eax      ; Overwrite saved EAX in stack so it's returned
    popad
    clc
    ret
    
.take_whole:
    or   dword [esi + 4], 1   ; set Used=1
    sub  dword [heap_total_free], eax
    mov  eax, esi
    add  eax, 8

    ; Log result (Silenced)
    ;push eax
    ;call serial_print_hex32
    
    ;mov  edx, [esp + 24]
    ;test edx, edx
    ;jz   .tw_no_tag
    ;mov  esi, heap_msg_for
    ;call serial_print
    ;mov  esi, edx
    ;call serial_print
;.tw_no_tag:
    ;mov  esi, heap_msg_nl
    ;call serial_print
    ;pop  eax

    mov  [esp + 28], eax      ; Overwrite saved EAX in stack
    popad
    clc
    ret
    
.next_block:
    test ebx, 2
    jnz  .fail
    add  esi, 8
    add  esi, eax
    jmp  .search

.fail:
    popad
    stc
    xor  eax, eax
    ret

; -
; kfree
; In: EAX = pointer to payload
; -
kfree:
    pushad
    
    ; Log addr (Silenced)
    ;mov  esi, heap_msg_kf
    ;call serial_print
    ;push eax
    ;call serial_print_hex32
    ;pop  eax

    test eax, eax
    jz   .done
    
    mov  esi, eax
    sub  esi, 8               ; ESI = header
    
    mov  ebx, [esi + 4]
    test ebx, 1
    jz   .done                ; already free
    
    and  dword [esi + 4], ~1  ; Used=0
    mov  ecx, [esi]
    add  dword [heap_total_free], ecx
    
    ; Log size (Silenced)
    ;mov  esi, heap_msg_kf2
    ;call serial_print
    ;mov  eax, ecx
    ;call serial_print_hex32
    ;mov  esi, heap_msg_kf3
    ;call serial_print
    
    ; print tag
    ;mov  edx, [esp + 20]
    ;test edx, edx
    ;jz   .kf_no_tag
    ;mov  esi, heap_msg_for
    ;call serial_print
    ;mov  esi, edx
    ;call serial_print
;.kf_no_tag:
    ;mov  esi, heap_msg_nl
    ;call serial_print

    call heap_coalesce
.done:
    popad
    ret

heap_msg_kf:  db '[HEAP] free addr=0x', 0
heap_msg_kf2: db ' (sz=0x', 0
heap_msg_kf3: db ')', 0
heap_msg_km:  db '[HEAP] malloc sz=0x', 0
heap_msg_km2: db ' -> 0x', 0
heap_msg_for: db ' for ', 0
heap_msg_nl:  db 13, 10, 0

; -
; heap_coalesce: merges adjacent free blocks
; -
heap_coalesce:
    pusha
    mov  esi, HEAP_BASE
.scan:
    mov  eax, [esi]
    mov  ebx, [esi + 4]
    test ebx, 2               ; IsLast?
    jnz  .done
    
    test ebx, 1               ; check if current is free
    jnz  .next
    
    mov  edi, esi
    add  edi, 8
    add  edi, eax
    
    mov  ecx, [edi + 4]
    test ecx, 1               ; check if NEXT is free
    jnz  .next
    
    ; BOTH free! Merge!
    mov  edx, [edi]
    add  eax, 8
    add  eax, edx
    mov  [esi], eax
    
    and  ecx, 2               ; carry over NEXT IsLast bit
    mov  [esi + 4], ecx
    
    add  dword [heap_total_free], 8   ; recovered overhead
    jmp  .scan

.next:
    add  esi, 8
    add  esi, eax
    jmp  .scan
.done:
    popa
    ret

; -
; cmd_heaptest - Shell command to safely test the heap allocator
; -
cmd_heaptest:
    pusha
    
    mov  esi, .msg_start
    mov  bl, 0x0E
    call pm_puts
    
    ; Allocate 1024 bytes
    mov  ecx, 1024
    call kmalloc
    jc   .err_alloc
    
    ; Save pointer
    mov  edi, eax
    
    ; Write test pattern
    mov  ecx, 1024 / 4
    mov  eax, 0xDEADBEEF
    rep  stosd
    
    mov  esi, .msg_alloc
    mov  bl, 0x0A
    call pm_puts
    
    ; Free it
    mov  eax, edi
    sub  eax, 1024         ; restore original payload pointer
    call kfree
    
    mov  esi, .msg_free
    mov  bl, 0x0A
    call pm_puts
    
    call pm_newline
    popa
    ret

.err_alloc:
    mov  esi, .msg_fail
    mov  bl, 0x0C
    call pm_puts
    call pm_newline
    popa
    ret

.msg_start: db ' [HEAP] Allocating 1024 bytes...', 13, 10, 0
.msg_alloc: db ' [HEAP] Allocation & Write Successful. Freeing...', 13, 10, 0
.msg_free:  db ' [HEAP] Memory Freed Successfully.', 0
.msg_fail:  db ' [HEAP] Allocation Failed!', 0
