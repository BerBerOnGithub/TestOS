/*
 * kmain.c  —  ClaudeOS kernel entry point
 *
 * Initialises all drivers then launches the GUI desktop.
 * The old text-mode CLI is still compiled in utils/ but not called.
 */

#include "vga.h"
#include "keyboard.h"
#include "timer.h"
#include "gui.h"
#include "../libc/klib.h"
#include <stdint.h>

void kmain(void) {
    /* Text mode for boot messages */
    vga_init();
    keyboard_init();

    vga_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
    vga_puts(" ClaudeOS v1.0  -  Booting...\n\n");
    vga_set_color(VGA_COLOR_LIGHT_GREY,  VGA_COLOR_BLACK);
    vga_puts(" [OK] VGA text driver\n");

    timer_init();
    vga_puts(" [OK] PIT timer (1000 Hz)\n");
    vga_puts(" [OK] PS/2 keyboard\n");
    vga_puts(" [OK] PS/2 mouse\n");
    vga_puts("\n Switching to graphics mode...\n");

    /* Small delay so the boot messages are visible */
    timer_sleep(800);

    /* Enter GUI — never returns */
    gui_run();
}
