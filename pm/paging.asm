; ===========================================================================
; pm/paging.asm - 32-bit Paging Implementation (Memory Mapper)
;
; Page tables are placed at FIXED physical addresses in conventional RAM,
; NOT embedded in the kernel binary. This avoids NASM multi-pass label
; shifting caused by align 4096 + large times blocks.
;
; Memory layout (0x120000 - 0x126FFF, 28KB total):
;   0x120000  page_directory   (4KB)
;   0x121000  page_table_0     (4KB)  maps 0x000000 - 0x3FFFFF
;   0x122000  page_table_1     (4KB)  maps 0x400000 - 0x7FFFFF
;   0x123000  page_table_2     (4KB)  maps 0x800000 - 0xBFFFFF
;   0x124000  page_table_3     (4KB)  maps 0xC00000 - 0xFFFFFFF
;   0x125000  page_table_vbe   (4KB)  maps VBE LFB (dynamic)
;   0x126000  page_table_e1000 (4KB)  maps e1000 BAR0 (dynamic)
;
; This region is above the e1000 buffers (0x11A000) and well below the
; wallpaper buffer (0x200000). This avoids overlapping with the FS blob
; which is loaded at 0x20000 and can be up to 800KB (ends at ~0xE3000).
; ===========================================================================
[BITS 32]

PAGE_DIR      equ 0x120000
PAGE_TBL_0    equ 0x121000
PAGE_TBL_1    equ 0x122000
PAGE_TBL_2    equ 0x123000
PAGE_TBL_3    equ 0x124000
PAGE_TBL_VBE  equ 0x125000
PAGE_TBL_E1000 equ 0x126000

paging_init:
    pusha

    ; 0. Zero out all 7 pages (28KB) at 0x120000
    mov  edi, PAGE_DIR
    mov  ecx, (7 * 4096) / 4    ; 7168 dwords
    xor  eax, eax
    rep  stosd

    ; 1. Link Page Directory entries 0..3 to Page Tables 0..3
    mov  dword [PAGE_DIR + 0*4], PAGE_TBL_0 | 0x03
    mov  dword [PAGE_DIR + 1*4], PAGE_TBL_1 | 0x03
    mov  dword [PAGE_DIR + 2*4], PAGE_TBL_2 | 0x03
    mov  dword [PAGE_DIR + 3*4], PAGE_TBL_3 | 0x03

    ; 2. Fill Page Tables 0..3 with identity map (virtual == physical)
    ; 4 tables * 1024 entries = 4096 entries (maps 16MB)
    mov  ecx, 4096
    mov  edi, PAGE_TBL_0
    mov  eax, 0x03              ; phys 0x000000 | Present | R/W
.fill_loop:
    mov  [edi], eax
    add  eax, 4096
    add  edi, 4
    loop .fill_loop

    ; 3. Map VBE LFB dynamically (if present)
    mov  eax, [vbe_physbase]
    test eax, eax
    jz   .no_vbe

    ; PDE index = physbase >> 22
    mov  ebx, eax
    shr  ebx, 22

    ; Install VBE page table in the directory
    mov  dword [PAGE_DIR + ebx*4], PAGE_TBL_VBE | 0x03

    ; Fill VBE page table (1024 entries = 4MB)
    mov  ecx, 1024
    mov  edi, PAGE_TBL_VBE
    and  eax, 0xFFC00000        ; align to 4MB boundary
    or   eax, 0x03
.vbe_loop:
    mov  [edi], eax
    add  eax, 4096
    add  edi, 4
    loop .vbe_loop

.no_vbe:
    ; 3.5 Map e1000 BAR0 dynamically (if present)
    mov  eax, [pci_e1000_bar0]
    test eax, eax
    jz   .no_e1000

    ; PDE index = physbase >> 22
    mov  ebx, eax
    shr  ebx, 22

    ; Install e1000 page table in the directory
    mov  dword [PAGE_DIR + ebx*4], PAGE_TBL_E1000 | 0x03

    ; Fill e1000 page table (1024 entries = 4MB)
    mov  ecx, 1024
    mov  edi, PAGE_TBL_E1000
    and  eax, 0xFFC00000        ; align to 4MB boundary
    or   eax, 0x03
.e1000_loop:
    mov  [edi], eax
    add  eax, 4096
    add  edi, 4
    loop .e1000_loop

.no_e1000:
    ; 4. Enable Paging
    mov  eax, PAGE_DIR
    mov  cr3, eax

    mov  eax, cr0
    or   eax, 0x80000000        ; Set PG bit
    mov  cr0, eax
    jmp  $+2                    ; flush prefetch queue

    popa
    ret
