; ===========================================================================
; pm/core/pmm.asm - Physical Memory Manager
; ===========================================================================

[BITS 32]

PMM_PAGES      equ 32768       ; Supports up to 128MB RAM
PMM_BITMAP_SZ  equ 4096        ; Bytes needed for the bitmap
PMM_SYSTEM_END equ 12544       ; Reserve first 49MB (Core OS 17 + Heap 32) = 12544 pages

pmm_bitmap: times PMM_BITMAP_SZ db 0
pmm_free_pages:  dd 0
pmm_total_pages: dd 0

; -
; pmm_init: Identity maps and prepares physical page bitmap
; -
pmm_init:
    pusha
    
    ; Clear entire bitmap to 0 (FREE)
    mov  edi, pmm_bitmap
    mov  ecx, PMM_BITMAP_SZ / 4
    xor  eax, eax
    rep  stosd
    
    ; Mark system pages as USED (indices 0 to PMM_SYSTEM_END-1)
    mov  edi, pmm_bitmap
    mov  ecx, PMM_SYSTEM_END / 8   ; bytes to fill
    mov  al, 0xFF
    rep  stosb
    
    ; Record stats
    mov  dword [pmm_total_pages], PMM_PAGES
    mov  eax, PMM_PAGES
    sub  eax, PMM_SYSTEM_END
    mov  [pmm_free_pages], eax
    
    popa
    ret

; -
; pmm_alloc_page: allocate a single 4KB physical frame
; Out: EAX = absolute physical address (CF=0), or 0 if OOM (CF=1)
; -
pmm_alloc_page:
    push ebx
    push ecx

    mov  ecx, PMM_PAGES
    xor  ebx, ebx              ; EBX = bit index
.scan:
    bt   [pmm_bitmap], ebx
    jnc  .found
    inc  ebx
    loop .scan
    
    stc
    xor  eax, eax
    jmp  .done
.found:
    bts  [pmm_bitmap], ebx
    dec  dword [pmm_free_pages]
    mov  eax, ebx
    shl  eax, 12
    clc
.done:
    pop  ecx
    pop  ebx
    ret

; -
; pmm_free_page: free a physical frame
; In: EAX = physical address
; -
pmm_free_page:
    pusha
    shr  eax, 12               ; Physical to Index
    cmp  eax, PMM_PAGES
    jge  .done
    
    ; check if already free
    bt   [pmm_bitmap], eax
    jnc  .done
    
    btr  [pmm_bitmap], eax
    inc  dword [pmm_free_pages]
.done:
    popa
    ret
