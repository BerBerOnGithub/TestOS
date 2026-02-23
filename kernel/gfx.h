#ifndef GFX_DRIVER_H
#define GFX_DRIVER_H

#include <stdint.h>

/*
 * gfx.h  —  VGA Mode 13h graphics driver
 *
 * Mode 13h: 320x200, 256 colours, linear framebuffer at 0xA0000.
 * One byte per pixel.  No bank switching needed.
 *
 * Palette: we load a custom 256-colour palette on init.
 * Colours 0-15  : standard CGA/EGA palette (matches text mode)
 * Colours 16-31 : greyscale ramp
 * Colours 32+   : GUI colours (desktop, window chrome, etc.)
 */

#define GFX_W      320
#define GFX_H      200
#define GFX_BUF    ((volatile uint8_t *)0xA0000)

/* Named GUI palette indices */
#define COL_BLACK        0
#define COL_BLUE         1
#define COL_GREEN        2
#define COL_CYAN         3
#define COL_RED          4
#define COL_MAGENTA      5
#define COL_BROWN        6
#define COL_LGREY        7
#define COL_DGREY        8
#define COL_LBLUE        9
#define COL_LGREEN      10
#define COL_LCYAN       11
#define COL_LRED        12
#define COL_LMAGENTA    13
#define COL_YELLOW      14
#define COL_WHITE       15

/* Extra GUI palette slots */
#define COL_DESKTOP     32   /* teal desktop background */
#define COL_WIN_BG      33   /* window interior          */
#define COL_TITLEBAR    34   /* active title bar         */
#define COL_TITLEBAR_I  35   /* inactive title bar       */
#define COL_TITLE_TEXT  36   /* title bar text           */
#define COL_WIN_BORDER  37   /* window border            */
#define COL_SHADOW      38   /* drop shadow              */
#define COL_BTN_FACE    39   /* button face              */
#define COL_BTN_HI      40   /* button highlight edge    */
#define COL_BTN_SH      41   /* button shadow edge       */
#define COL_TASKBAR     42   /* taskbar background       */
#define COL_TASKBTN     43   /* taskbar button           */
#define COL_TASKBTN_A   44   /* taskbar active button    */
#define COL_CURSOR      45   /* mouse cursor fill        */
#define COL_CURSOR_OUT  46   /* mouse cursor outline     */
#define COL_TXT_FG      47   /* default text foreground  */
#define COL_TXT_BG      48   /* text area background     */
#define COL_HIGHLIGHT   49   /* selected / highlight     */
#define COL_MENUBAR     50   /* menu bar                 */
#define COL_MENU_BG     51   /* menu dropdown            */
#define COL_ICON_BG     52   /* desktop icon background  */

/* Switch to mode 13h and load palette */
void gfx_init(void);

/* Return to VGA text mode (mode 3) */
void gfx_text_mode(void);

/* Primitives */
void gfx_clear(uint8_t col);
void gfx_pixel(int x, int y, uint8_t col);
uint8_t gfx_get_pixel(int x, int y);

void gfx_hline(int x, int y, int w, uint8_t col);
void gfx_vline(int x, int y, int h, uint8_t col);
void gfx_rect(int x, int y, int w, int h, uint8_t col);
void gfx_fill_rect(int x, int y, int w, int h, uint8_t col);

/* 8x8 bitmap font glyph */
void gfx_char(int x, int y, char c, uint8_t fg, uint8_t bg);
void gfx_str(int x, int y, const char *s, uint8_t fg, uint8_t bg);
void gfx_str_transparent(int x, int y, const char *s, uint8_t fg);

/* Blit rectangular region from src buffer to screen */
void gfx_blit(int dx, int dy, int w, int h, const uint8_t *src);

/* Save / restore a screen region (for cursor erase) */
void gfx_save_region(int x, int y, int w, int h, uint8_t *dst);
void gfx_restore_region(int x, int y, int w, int h, const uint8_t *dst);

/* Raised / sunken 3-D box (Windows 3.x style) */
void gfx_raised_box(int x, int y, int w, int h);
void gfx_sunken_box(int x, int y, int w, int h);

#endif /* GFX_DRIVER_H */
