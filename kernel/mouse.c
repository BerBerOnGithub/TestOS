/*
 * mouse.c  —  PS/2 mouse driver
 *
 * PS/2 mouse packets arrive on the same port as the keyboard (0x60)
 * but are routed through the PS/2 controller's second port (aux device).
 *
 * Initialisation sequence:
 *   1. Enable aux device  (cmd 0xA8 to port 0x64)
 *   2. Enable aux interrupts in the controller command byte
 *   3. Send "enable data reporting" (0xF4) to the mouse
 *
 * Each packet is 3 bytes:
 *   Byte 0:  flags  [Y-overflow | X-overflow | Y-sign | X-sign | 1 | Middle | Right | Left]
 *   Byte 1:  X movement (signed, 2's complement if X-sign set)
 *   Byte 2:  Y movement (signed, 2's complement if Y-sign set; Y axis INVERTED vs screen)
 */

#include "mouse.h"
#include "gfx.h"
#include <stdint.h>

static inline void outb(uint16_t p, uint8_t v){ __asm__ volatile("outb %0,%1"::"a"(v),"Nd"(p)); }
static inline uint8_t inb(uint16_t p){ uint8_t v; __asm__ volatile("inb %1,%0":"=a"(v):"Nd"(p)); return v; }

/* Wait for PS/2 controller input buffer empty (safe to write) */
static void ps2_wait_write(void) {
    int i = 100000;
    while (i-- && (inb(0x64) & 2));
}
/* Wait for PS/2 controller output buffer full (data ready) */
static void ps2_wait_read(void) {
    int i = 100000;
    while (i-- && !(inb(0x64) & 1));
}

/* Send a byte to the mouse (aux device) */
static void mouse_write(uint8_t val) {
    ps2_wait_write(); outb(0x64, 0xD4);   /* route next byte to aux */
    ps2_wait_write(); outb(0x60, val);
}
/* Read a byte from the data port */
static uint8_t mouse_read(void) {
    ps2_wait_read();
    return inb(0x60);
}

/* Packet state machine */
static int    pkt_byte  = 0;
static uint8_t pkt[3]  = {0,0,0};

/* Current absolute position */
static int mouse_x = GFX_W / 2;
static int mouse_y = GFX_H / 2;

void mouse_init(void) {
    /* Enable aux device */
    ps2_wait_write(); outb(0x64, 0xA8);

    /* Read controller command byte, set aux interrupt enable (bit 1) */
    ps2_wait_write(); outb(0x64, 0x20);
    ps2_wait_read();
    uint8_t cb = inb(0x60) | 0x02;
    ps2_wait_write(); outb(0x64, 0x60);
    ps2_wait_write(); outb(0x60, cb);

    /* Set mouse defaults */
    mouse_write(0xF6);  mouse_read();   /* set defaults */
    /* Set sample rate 40 */
    mouse_write(0xF3);  mouse_read();
    mouse_write(40);    mouse_read();
    /* Enable data reporting */
    mouse_write(0xF4);  mouse_read();

    mouse_x = GFX_W / 2;
    mouse_y = GFX_H / 2;
    pkt_byte = 0;
}

int mouse_poll(mouse_state_t *ms) {
    ms->moved = 0;
    ms->dx = 0; ms->dy = 0;

    /* Drain all available bytes and assemble complete packets */
    int changed = 0;
    int safety = 64;   /* never spin forever */

    while (safety-- && (inb(0x64) & 0x21) == 0x21) {
        /* Bit 5 of status = aux data available */
        uint8_t b = inb(0x60);

        if (pkt_byte == 0) {
            /* First byte must have bit 3 set (always-one bit) */
            if (!(b & 0x08)) continue;
        }
        pkt[pkt_byte++] = b;

        if (pkt_byte == 3) {
            pkt_byte = 0;

            /* Decode packet */
            uint8_t flags = pkt[0];
            if (flags & 0xC0) continue;    /* overflow — discard */

            int dx = (int)pkt[1] - ((flags & 0x10) ? 256 : 0);
            int dy = (int)pkt[2] - ((flags & 0x20) ? 256 : 0);

            /* Y is inverted in PS/2 protocol vs screen coords */
            mouse_x += dx;
            mouse_y -= dy;

            /* Clamp to screen */
            if (mouse_x < 0)        mouse_x = 0;
            if (mouse_x >= GFX_W)   mouse_x = GFX_W - 1;
            if (mouse_y < 0)        mouse_y = 0;
            if (mouse_y >= GFX_H)   mouse_y = GFX_H - 1;

            ms->dx     = dx;
            ms->dy     = -dy;
            ms->left   = (flags & 0x01) ? 1 : 0;
            ms->right  = (flags & 0x02) ? 1 : 0;
            ms->moved  = 1;
            changed    = 1;
        }
    }

    ms->x = mouse_x;
    ms->y = mouse_y;
    return changed;
}
