# boot.S  — ClaudeOS Stage-1 Bootloader
# Fix: read only KERNEL_COUNT sectors (set by Makefile to exact kernel size),
#      and always pad the image so those sectors exist on disk.

.section .boot, "ax"
.code16
.globl _boot_start
_boot_start:

    cli
    xorw  %ax, %ax
    movw  %ax, %ds
    movw  %ax, %es
    movw  %ax, %ss
    movw  $0x7C00, %sp
    sti

    movb  %dl, boot_drive       # save BIOS boot drive number

    # ── Print banner ─────────────────────────────────────
    movw  $msg_loading, %si
.print:
    lodsb
    testb %al, %al
    jz    .print_done
    movb  $0x0E, %ah
    int   $0x10
    jmp   .print
.print_done:

    # ── Reset disk controller first (good practice) ───────
    xorb  %ah, %ah
    movb  boot_drive, %dl
    int   $0x13

    # ── Load kernel: sectors 2..N → 0x1000:0000 (=0x10000) ──
    movw  $0x1000, %ax
    movw  %ax, %es
    xorw  %bx, %bx             # ES:BX = 0x10000

    movb  $0x02, %ah            # BIOS: read sectors
    movb  $KERNEL_COUNT, %al   # number of sectors (patched by Makefile)
    movb  $0, %ch              # cylinder 0
    movb  $0, %dh              # head 0
    movb  $2, %cl              # start at sector 2
    movb  boot_drive, %dl
    int   $0x13
    jc    disk_error

    # ── Enter 32-bit protected mode ───────────────────────
    cli
    lgdtl gdt_desc

    movl  %cr0, %eax
    orl   $1, %eax
    movl  %eax, %cr0

    ljmp  $0x08, $pm32_entry   # flush pipeline, load CS with code descriptor

disk_error:
    movw  $msg_disk_err, %si
.err:
    lodsb
    testb %al, %al
    jz    .halt
    movb  $0x0E, %ah
    int   $0x10
    jmp   .err
.halt:
    hlt
    jmp   .halt

# ── Data ─────────────────────────────────────────────────
boot_drive:   .byte 0
msg_loading:  .ascii "ClaudeOS: Loading..."
              .byte 0x0D, 0x0A, 0
msg_disk_err: .ascii "DISK READ ERROR - check image padding"
              .byte 0x0D, 0x0A, 0

# ── GDT ──────────────────────────────────────────────────
.align 4
gdt_base:
    .quad 0                        # null descriptor
gdt_code:
    .word 0xFFFF, 0x0000           # limit 4G, base 0
    .byte 0x00, 0x9A, 0xCF, 0x00  # present, ring0, code, exec/read, 4K gran, 32-bit
gdt_data:
    .word 0xFFFF, 0x0000
    .byte 0x00, 0x92, 0xCF, 0x00  # present, ring0, data, read/write, 4K gran, 32-bit
gdt_end:

gdt_desc:
    .word gdt_end - gdt_base - 1
    .long gdt_base

# ── 32-bit entry ──────────────────────────────────────────
.code32
pm32_entry:
    movw  $0x10, %ax    # data segment selector
    movw  %ax, %ds
    movw  %ax, %es
    movw  %ax, %ss
    movw  %ax, %fs
    movw  %ax, %gs
    movl  $0x9FFFF, %esp

    ljmp  $0x08, $0x10000   # jump to kernel entry at physical 0x10000

# ── Boot signature at byte 510 ────────────────────────────
.org 510
.byte 0x55, 0xAA
