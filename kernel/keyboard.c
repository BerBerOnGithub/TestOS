#include "keyboard.h"
#include "vga.h"
#include <stdint.h>

/* ── Port I/O ──────────────────────────────────────── */
static inline uint8_t inb(uint16_t port) {
    uint8_t v;
    __asm__ volatile ("inb %1, %0" : "=a"(v) : "Nd"(port));
    return v;
}

/* ── US QWERTY scancode→ASCII table (set 1, make codes) */
static const char sc_ascii[128] = {
/*00*/  0,   0,  '1','2','3','4','5','6','7','8','9','0','-','=', '\b','\t',
/*10*/ 'q','w','e','r','t','y','u','i','o','p','[',']', '\n',  0, 'a','s',
/*20*/ 'd','f','g','h','j','k','l',';','\'','`',  0, '\\','z','x','c','v',
/*30*/ 'b','n','m',',','.','/',  0, '*',  0, ' ',  0,   0,   0,  0,  0,  0,
/*40*/   0,  0,  0,  0,  0,  0,  0, '7', '8','9', '-', '4','5','6','+','1',
/*50*/ '2','3','0', '.', 0,  0,  0,  0,   0,  0,  0,   0,   0,  0,  0,  0,
/*60*/   0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,   0,   0,  0,  0,  0,
/*70*/   0,  0,  0,  0,  0,  0,  0,  0,   0,  0,  0,   0,   0,  0,  0,  0,
};

static const char sc_ascii_shift[128] = {
/*00*/  0,   0,  '!','@','#','$','%','^','&','*','(',')','_','+', '\b','\t',
/*10*/ 'Q','W','E','R','T','Y','U','I','O','P','{','}', '\n',  0, 'A','S',
/*20*/ 'D','F','G','H','J','K','L',':','"','~',  0, '|', 'Z','X','C','V',
/*30*/ 'B','N','M','<','>','?',  0, '*',  0, ' ',  0,  0,  0,  0,  0,  0,
};

static int shift_held = 0;

void keyboard_init(void) {
    /* Flush any pending data */
    while (inb(0x64) & 1) inb(0x60);
}

char keyboard_getchar(void) {
    while (1) {
        /* Wait for data-ready bit in status register */
        if (!(inb(0x64) & 1)) continue;

        uint8_t sc = inb(0x60);

        /* Key release: high bit set */
        if (sc & 0x80) {
            uint8_t rel = sc & 0x7F;
            if (rel == 0x2A || rel == 0x36) shift_held = 0;
            continue;
        }

        /* Shift keys */
        if (sc == 0x2A || sc == 0x36) { shift_held = 1; continue; }

        if (sc >= 128) continue;

        char c = shift_held ? sc_ascii_shift[sc] : sc_ascii[sc];
        if (c) return c;
    }
}

void keyboard_readline(char *buf, int len) {
    int i = 0;
    while (1) {
        char c = keyboard_getchar();
        if (c == '\n' || c == '\r') {
            vga_putchar('\n');
            buf[i] = '\0';
            return;
        } else if (c == '\b') {
            if (i > 0) { i--; vga_putchar('\b'); }
        } else if (i < len - 1) {
            buf[i++] = c;
            vga_putchar(c);
        }
    }
}
