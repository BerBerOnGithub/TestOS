/*
 * linker.ld  —  ClaudeOS kernel linker script
 *
 * Everything is linked as a flat binary loaded at physical
 * address 0x10000 (64 KB mark) by the bootloader.
 *
 * The entry point symbol _start lives in kernel_entry.o
 * which must come first so execution begins there.
 */

ENTRY(_start)

SECTIONS {
    . = 0x10000;

    /* ── Text (code) ─────────────────────── */
    .text : {
        /* kernel_entry.o MUST be first — it holds _start */
        KEEP(*kernel_entry.o(.text))
        *(.text*)
    }

    /* ── Read-only data ──────────────────── */
    .rodata : {
        *(.rodata*)
    }

    /* ── Initialised data ────────────────── */
    .data : {
        *(.data*)
    }

    /* ── BSS (zero-initialised) ──────────── */
    .bss : {
        *(COMMON)
        *(.bss*)
    }

    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
    }
}
