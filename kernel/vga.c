#include "vga.h"
#include <stdint.h>

/* ── Internal state ─────────────────────────────────── */
static int     vga_row   = 0;
static int     vga_col   = 0;
static uint8_t vga_attr  = 0;   /* current colour attribute byte */

/* Inline port I/O (no <sys/io.h> available in freestanding) */
static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

/* ── Hardware cursor via VGA CRT registers ──────────── */
static void _hw_cursor(int row, int col) {
    uint16_t pos = (uint16_t)(row * VGA_WIDTH + col);
    outb(0x3D4, 0x0F); outb(0x3D5, (uint8_t)(pos & 0xFF));
    outb(0x3D4, 0x0E); outb(0x3D5, (uint8_t)(pos >> 8));
}

static inline uint16_t _entry(char c, uint8_t attr) {
    return (uint16_t)((uint16_t)attr << 8 | (uint8_t)c);
}

/* ── Public API ─────────────────────────────────────── */
void vga_init(void) {
    vga_attr = (VGA_COLOR_BLACK << 4) | VGA_COLOR_LIGHT_GREY;
    vga_clear();
}

void vga_set_color(vga_color_t fg, vga_color_t bg) {
    vga_attr = (uint8_t)((bg << 4) | fg);
}

void vga_clear(void) {
    for (int r = 0; r < VGA_HEIGHT; r++)
        for (int c = 0; c < VGA_WIDTH; c++)
            VGA_BUFFER[r * VGA_WIDTH + c] = _entry(' ', vga_attr);
    vga_row = vga_col = 0;
    _hw_cursor(0, 0);
}

static void _scroll(void) {
    /* Move every row up by one */
    for (int r = 1; r < VGA_HEIGHT; r++)
        for (int c = 0; c < VGA_WIDTH; c++)
            VGA_BUFFER[(r-1) * VGA_WIDTH + c] = VGA_BUFFER[r * VGA_WIDTH + c];
    /* Clear last row */
    for (int c = 0; c < VGA_WIDTH; c++)
        VGA_BUFFER[(VGA_HEIGHT-1) * VGA_WIDTH + c] = _entry(' ', vga_attr);
    vga_row = VGA_HEIGHT - 1;
}

void vga_putchar(char c) {
    if (c == '\n') {
        vga_col = 0;
        if (++vga_row >= VGA_HEIGHT) _scroll();
    } else if (c == '\r') {
        vga_col = 0;
    } else if (c == '\b') {
        if (vga_col > 0) {
            vga_col--;
            VGA_BUFFER[vga_row * VGA_WIDTH + vga_col] = _entry(' ', vga_attr);
        }
    } else if (c == '\t') {
        vga_col = (vga_col + 8) & ~7;
        if (vga_col >= VGA_WIDTH) { vga_col = 0; if (++vga_row >= VGA_HEIGHT) _scroll(); }
    } else {
        VGA_BUFFER[vga_row * VGA_WIDTH + vga_col] = _entry(c, vga_attr);
        if (++vga_col >= VGA_WIDTH) {
            vga_col = 0;
            if (++vga_row >= VGA_HEIGHT) _scroll();
        }
    }
    _hw_cursor(vga_row, vga_col);
}

void vga_puts(const char *s) {
    while (*s) vga_putchar(*s++);
}

void vga_set_cursor(int row, int col) {
    vga_row = row; vga_col = col;
    _hw_cursor(row, col);
}
