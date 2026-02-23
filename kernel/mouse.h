#ifndef MOUSE_H
#define MOUSE_H

#include <stdint.h>

/*
 * mouse.h  —  PS/2 mouse driver
 *
 * Reads 3-byte packets from the PS/2 controller (port 0x60).
 * Decodes X/Y relative deltas and button state.
 * Accumulates absolute X/Y position clamped to the screen.
 */

typedef struct {
    int      x, y;          /* absolute position (pixels)      */
    int      dx, dy;        /* last delta (for this poll)       */
    uint8_t  left, right;   /* button state (1 = pressed)       */
    uint8_t  moved;         /* set if position changed          */
} mouse_state_t;

void mouse_init(void);

/*
 * Poll the mouse.  Should be called from the main GUI loop.
 * Returns 1 if anything changed (position or buttons), 0 otherwise.
 */
int mouse_poll(mouse_state_t *ms);

#endif
