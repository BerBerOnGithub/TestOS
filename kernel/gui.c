/*
 * gui.c  —  ClaudeOS graphical desktop
 *
 * Architecture:
 *   - Desktop drawn once, then only dirty regions redrawn
 *   - Windows: title bar, close/min buttons, draggable, content area
 *   - Mouse cursor: 12x19 arrow sprite, region save/restore
 *   - Taskbar: clock, open window buttons, Start-style menu
 *   - Built-in window apps: About, Terminal, Calc, Color Picker
 */

#include "gui.h"
#include "gfx.h"
#include "mouse.h"
#include "timer.h"
#include "keyboard.h"
#include "../libc/klib.h"
#include <stdint.h>

static inline void outb(uint16_t p, uint8_t v){ __asm__ volatile("outb %0,%1"::"a"(v),"Nd"(p)); }
static inline uint8_t inb(uint16_t p){ uint8_t v; __asm__ volatile("inb %1,%0":"=a"(v):"Nd"(p)); return v; }

/* ════════════════════════════════════════════════════════ *
 *  Constants                                              *
 * ════════════════════════════════════════════════════════ */
#define TASKBAR_H     12
#define TITLEBAR_H    11
#define BTN_W         9
#define BORDER        2
#define MAX_WINDOWS   6
#define CURSOR_W      12
#define CURSOR_H      19

/* ════════════════════════════════════════════════════════ *
 *  Mouse cursor — 12x19 arrow                            *
 * ════════════════════════════════════════════════════════ */
/* 0=transparent, 1=outline(black), 2=fill(white) */
static const uint8_t cursor_shape[CURSOR_H][CURSOR_W] = {
    {1,0,0,0,0,0,0,0,0,0,0,0},
    {1,1,0,0,0,0,0,0,0,0,0,0},
    {1,2,1,0,0,0,0,0,0,0,0,0},
    {1,2,2,1,0,0,0,0,0,0,0,0},
    {1,2,2,2,1,0,0,0,0,0,0,0},
    {1,2,2,2,2,1,0,0,0,0,0,0},
    {1,2,2,2,2,2,1,0,0,0,0,0},
    {1,2,2,2,2,2,2,1,0,0,0,0},
    {1,2,2,2,2,2,2,2,1,0,0,0},
    {1,2,2,2,2,2,2,2,2,1,0,0},
    {1,2,2,2,2,2,2,2,2,2,1,0},
    {1,2,2,2,2,2,2,1,1,1,1,1},
    {1,2,2,2,1,2,2,1,0,0,0,0},
    {1,2,2,1,0,1,2,2,1,0,0,0},
    {1,2,1,0,0,1,2,2,1,0,0,0},
    {1,1,0,0,0,0,1,2,2,1,0,0},
    {1,0,0,0,0,0,1,2,2,1,0,0},
    {0,0,0,0,0,0,0,1,2,1,0,0},
    {0,0,0,0,0,0,0,1,1,0,0,0},
};
static uint8_t cursor_save[CURSOR_H * CURSOR_W];
static int     cursor_saved_x = -1, cursor_saved_y = -1;

static void cursor_erase(void) {
    if (cursor_saved_x < 0) return;
    gfx_restore_region(cursor_saved_x, cursor_saved_y,
                       CURSOR_W, CURSOR_H, cursor_save);
    cursor_saved_x = -1;
}
static void cursor_draw(int x, int y) {
    gfx_save_region(x, y, CURSOR_W, CURSOR_H, cursor_save);
    cursor_saved_x = x; cursor_saved_y = y;
    for (int r = 0; r < CURSOR_H; r++)
        for (int c = 0; c < CURSOR_W; c++) {
            uint8_t v = cursor_shape[r][c];
            if (v == 1) gfx_pixel(x+c, y+r, COL_CURSOR_OUT);
            else if (v == 2) gfx_pixel(x+c, y+r, COL_CURSOR);
        }
}

/* ════════════════════════════════════════════════════════ *
 *  Window structure                                       *
 * ════════════════════════════════════════════════════════ */
typedef enum { APP_NONE=0, APP_ABOUT, APP_TERMINAL, APP_CALC, APP_COLORS, APP_SNAKE_GUI } app_id_t;

typedef struct {
    int       open;
    int       x, y, w, h;
    int       drag_dx, drag_dy;
    int       dragging;
    int       minimized;
    char      title[32];
    app_id_t  app;
    /* Per-app state */
    char      term_buf[20][38];   /* terminal: 20 lines x 38 chars */
    int       term_row, term_col;
    char      term_input[64];
    int       term_input_len;
    int       calc_val;
    char      calc_disp[16];
    int       color_sel;
} window_t;

static window_t windows[MAX_WINDOWS];
static int focused = -1;

/* ════════════════════════════════════════════════════════ *
 *  Helpers                                               *
 * ════════════════════════════════════════════════════════ */
// max unused
// min_i unused
static int clamp(int v, int lo, int hi){ return v<lo?lo:v>hi?hi:v; }

static int pt_in_rect(int px, int py, int rx, int ry, int rw, int rh) {
    return px>=rx && px<rx+rw && py>=ry && py<ry+rh;
}

/* ════════════════════════════════════════════════════════ *
 *  Window drawing                                        *
 * ════════════════════════════════════════════════════════ */
static void draw_button(int x, int y, int w, int h, const char *label, int pressed) {
    if (pressed) gfx_sunken_box(x,y,w,h);
    else         gfx_raised_box(x,y,w,h);
    int tx = x + (w - (int)kstrlen(label)*8)/2;
    int ty = y + (h - 8)/2;
    gfx_str_transparent(tx, ty, label, COL_BLACK);
}

static void draw_window(int idx) {
    window_t *wn = &windows[idx];
    if (!wn->open || wn->minimized) return;

    int x=wn->x, y=wn->y, w=wn->w, h=wn->h;
    int isfoc = (idx == focused);

    /* Drop shadow */
    gfx_fill_rect(x+3, y+3, w, h, COL_SHADOW);

    /* Outer border */
    gfx_fill_rect(x, y, w, h, COL_WIN_BORDER);

    /* Title bar */
    uint8_t tbar_col = isfoc ? COL_TITLEBAR : COL_TITLEBAR_I;
    gfx_fill_rect(x+BORDER, y+BORDER, w-BORDER*2, TITLEBAR_H, tbar_col);

    /* Title text */
    gfx_str_transparent(x+BORDER+3, y+BORDER+2, wn->title, COL_TITLE_TEXT);

    /* Close button [X] */
    int bx = x+w-BORDER-BTN_W-1;
    int by = y+BORDER+1;
    gfx_raised_box(bx, by, BTN_W, BTN_W-1);
    gfx_str_transparent(bx+1, by, "x", COL_LRED);

    /* Minimise button [_] */
    int mx = bx - BTN_W - 2;
    gfx_raised_box(mx, by, BTN_W, BTN_W-1);
    gfx_str_transparent(mx+1, by+3, "_", COL_BLACK);

    /* Client area */
    int cx=x+BORDER, cy=y+BORDER+TITLEBAR_H;
    int cw=w-BORDER*2, ch=h-BORDER*2-TITLEBAR_H;
    gfx_fill_rect(cx, cy, cw, ch, COL_WIN_BG);
    gfx_rect(cx, cy, cw, ch, COL_BTN_SH);

    /* Draw app content */
    int tx=cx+4, ty=cy+4;

    if (wn->app == APP_ABOUT) {
        gfx_str(tx, ty,    "ClaudeOS v1.0",          COL_TITLEBAR,  COL_WIN_BG);
        gfx_str(tx, ty+12, "x86 Protected Mode OS",  COL_BLACK,     COL_WIN_BG);
        gfx_str(tx, ty+24, "Kernel:  custom C+ASM",  COL_DGREY,     COL_WIN_BG);
        gfx_str(tx, ty+36, "Display: VGA Mode 13h",  COL_DGREY,     COL_WIN_BG);
        gfx_str(tx, ty+48, "Timer:   PIT 1000 Hz",   COL_DGREY,     COL_WIN_BG);
        gfx_str(tx, ty+60, "Mouse:   PS/2 driver",   COL_DGREY,     COL_WIN_BG);
        gfx_str(tx, ty+72, "GUI:     ClaudeWM 1.0",  COL_DGREY,     COL_WIN_BG);
        draw_button(tx, ty+88, 48, 12, "OK", 0);
    }

    else if (wn->app == APP_TERMINAL) {
        /* Draw text lines */
        for (int r=0; r<20 && r<(ch-14)/9; r++) {
            gfx_str(tx, ty+r*9, wn->term_buf[r], COL_LGREEN, COL_BLACK);
        }
        /* Input line at bottom */
        gfx_fill_rect(cx, cy+ch-14, cw, 14, COL_BLACK);
        gfx_str_transparent(tx, cy+ch-11, "> ", COL_LGREEN);
        gfx_str_transparent(tx+16, cy+ch-11, wn->term_input, COL_WHITE);
        /* Blinking cursor */
        if ((timer_ticks()/500) % 2 == 0)
            gfx_fill_rect(tx+16+wn->term_input_len*8, cy+ch-11, 6, 8, COL_LGREEN);
    }

    else if (wn->app == APP_CALC) {
        /* Display */
        gfx_sunken_box(tx, ty, cw-8, 14);
        gfx_str(tx+cw-8-(int)kstrlen(wn->calc_disp)*8-4, ty+3,
                wn->calc_disp, COL_BLACK, COL_TXT_BG);
        /* Buttons: 4 columns x 5 rows */
        static const char *btns[5][4] = {
            {"7","8","9","/"},
            {"4","5","6","*"},
            {"1","2","3","-"},
            {"0",".","=","+"},
            {"C","","",""},
        };
        for (int r=0;r<5;r++) for (int c=0;c<4;c++) {
            if (!btns[r][c][0]) continue;
            int bx2=tx + c*18;
            int by2=ty+18 + r*14;
            draw_button(bx2,by2,16,12,btns[r][c],0);
        }
    }

    else if (wn->app == APP_COLORS) {
        gfx_str(tx, ty, "Palette (click a color):", COL_BLACK, COL_WIN_BG);
        for (int i=0;i<52;i++) {
            int bx2=tx+(i%13)*14, by2=ty+12+(i/13)*14;
            gfx_fill_rect(bx2,by2,13,13, (uint8_t)i);
            gfx_rect(bx2,by2,13,13, (i==wn->color_sel)?COL_WHITE:COL_DGREY);
        }
        /* Show selected colour index */
        char cbuf[16]; kstrcpy(cbuf,"Col: ");
        char nb[8]; kitoa(wn->color_sel,nb,10); kstrcat(cbuf,nb);
        gfx_str(tx, ty+72, cbuf, COL_BLACK, COL_WIN_BG);
    }
}

/* ════════════════════════════════════════════════════════ *
 *  Taskbar                                               *
 * ════════════════════════════════════════════════════════ */
static int  menu_open = 0;
static char time_str[16] = "00:00:00";

static void update_clock(void) {
    outb(0x70,0x00); uint8_t s = inb(0x71);
    outb(0x70,0x02); uint8_t m = inb(0x71);
    outb(0x70,0x04); uint8_t h = inb(0x71);
    s=(s>>4)*10+(s&0xF); m=(m>>4)*10+(m&0xF); h=(h>>4)*10+(h&0xF);
    /* Format HH:MM:SS */
    char *p = time_str;
    *p++ = '0'+h/10; *p++ = '0'+h%10; *p++ = ':';
    *p++ = '0'+m/10; *p++ = '0'+m%10; *p++ = ':';
    *p++ = '0'+s/10; *p++ = '0'+s%10; *p = 0;
}

static void draw_taskbar(void) {
    int y = GFX_H - TASKBAR_H;
    gfx_fill_rect(0, y, GFX_W, TASKBAR_H, COL_TASKBAR);
    gfx_hline(0, y, GFX_W, COL_BTN_HI);

    /* Start button */
    draw_button(1, y+1, 30, TASKBAR_H-2, "Menu", menu_open);

    /* Window buttons */
    int bx = 34;
    for (int i=0;i<MAX_WINDOWS;i++) {
        if (!windows[i].open) continue;
        uint8_t bc = (i==focused) ? COL_TASKBTN_A : COL_TASKBTN;
        gfx_fill_rect(bx, y+1, 44, TASKBAR_H-2, bc);
        gfx_rect(bx, y+1, 44, TASKBAR_H-2, COL_BTN_HI);
        /* Truncate title to 5 chars */
        char t[6]; int tl=(int)kstrlen(windows[i].title);
        for(int j=0;j<5;j++) { t[j]=(j<tl)?windows[i].title[j]:' '; } t[5]=0;
        gfx_str_transparent(bx+2, y+2, t, COL_WHITE);
        bx += 46;
    }

    /* Clock */
    gfx_str(GFX_W-66, y+2, time_str, COL_LGREEN, COL_TASKBAR);
}

/* ════════════════════════════════════════════════════════ *
 *  Start menu                                            *
 * ════════════════════════════════════════════════════════ */
static const struct { const char *label; app_id_t app; } menu_items[] = {
    { "About ClaudeOS", APP_ABOUT    },
    { "Terminal",       APP_TERMINAL },
    { "Calculator",     APP_CALC     },
    { "Color Picker",   APP_COLORS   },
    { "-- Reboot --",   APP_NONE     },
};
#define MENU_ITEMS 5
#define MENU_W     88
#define MENU_ITEM_H 12

static void draw_menu(void) {
    int my = GFX_H - TASKBAR_H - MENU_ITEMS * MENU_ITEM_H - 2;
    gfx_raised_box(1, my, MENU_W, MENU_ITEMS*MENU_ITEM_H+2);
    for (int i=0;i<MENU_ITEMS;i++) {
        int iy = my+1+i*MENU_ITEM_H;
        gfx_str(4, iy+2, menu_items[i].label, COL_BLACK, COL_BTN_FACE);
    }
}

/* ════════════════════════════════════════════════════════ *
 *  Desktop icons                                         *
 * ════════════════════════════════════════════════════════ */
static const struct { const char *name; int x, y; app_id_t app; } icons[] = {
    { "About",  2,  4, APP_ABOUT    },
    { "Term",   2, 40, APP_TERMINAL },
    { "Calc",   2, 76, APP_CALC     },
    { "Colors", 2,112, APP_COLORS   },
};
#define N_ICONS 4

static void draw_icons(void) {
    for (int i=0;i<N_ICONS;i++) {
        int ix=icons[i].x, iy=icons[i].y;
        /* Icon box */
        gfx_fill_rect(ix, iy, 22, 20, COL_ICON_BG);
        gfx_rect(ix, iy, 22, 20, COL_LCYAN);
        /* Label */
        gfx_str_transparent(ix, iy+22, icons[i].name, COL_WHITE);
    }
}

/* ════════════════════════════════════════════════════════ *
 *  Window management                                     *
 * ════════════════════════════════════════════════════════ */
static int open_window(app_id_t app) {
    /* Find free slot */
    int idx = -1;
    /* Check if already open */
    for (int i=0;i<MAX_WINDOWS;i++)
        if (windows[i].open && windows[i].app==app) { focused=i; return i; }
    for (int i=0;i<MAX_WINDOWS;i++)
        if (!windows[i].open) { idx=i; break; }
    if (idx<0) return -1;

    window_t *wn = &windows[idx];
    kmemset(wn, 0, sizeof(window_t));
    wn->open = 1;
    wn->app  = app;
    wn->minimized = 0;

    /* Default sizes and positions */
    switch (app) {
        case APP_ABOUT:
            kstrcpy(wn->title,"About ClaudeOS");
            wn->x=80; wn->y=30; wn->w=150; wn->h=120;
            break;
        case APP_TERMINAL:
            kstrcpy(wn->title,"Terminal");
            wn->x=30; wn->y=20; wn->w=200; wn->h=150;
            /* Init terminal */
            kstrcpy(wn->term_buf[0],"ClaudeOS Terminal v1.0");
            kstrcpy(wn->term_buf[1],"Type HELP for commands.");
            kstrcpy(wn->term_buf[2],"");
            wn->term_row=3; wn->term_col=0;
            break;
        case APP_CALC:
            kstrcpy(wn->title,"Calculator");
            wn->x=180; wn->y=40; wn->w=90; wn->h=110;
            kstrcpy(wn->calc_disp,"0");
            break;
        case APP_COLORS:
            kstrcpy(wn->title,"Color Picker");
            wn->x=60; wn->y=50; wn->w=190; wn->h=110;
            break;
        default: wn->open=0; return -1;
    }
    focused = idx;
    return idx;
}

static void close_window(int idx) {
    windows[idx].open = 0;
    if (focused == idx) {
        focused = -1;
        for (int i=MAX_WINDOWS-1;i>=0;i--)
            if (windows[i].open) { focused=i; break; }
    }
}

/* ════════════════════════════════════════════════════════ *
 *  Full redraw                                           *
 * ════════════════════════════════════════════════════════ */
static void redraw_all(void) {
    /* Desktop */
    gfx_fill_rect(0, 0, GFX_W, GFX_H - TASKBAR_H, COL_DESKTOP);
    /* Subtle grid pattern */
    for (int y=0;y<GFX_H-TASKBAR_H;y+=8)
        gfx_hline(0,y,GFX_W, COL_DESKTOP); /* same col, just marks it */

    draw_icons();

    /* Windows (back to front) */
    for (int i=0;i<MAX_WINDOWS;i++)
        if (i!=focused) draw_window(i);
    if (focused>=0) draw_window(focused);

    if (menu_open) draw_menu();
    draw_taskbar();
}

/* ════════════════════════════════════════════════════════ *
 *  Terminal command handling                             *
 * ════════════════════════════════════════════════════════ */
static void term_println(window_t *wn, const char *s) {
    if (wn->term_row >= 20) {
        /* Scroll */
        for (int r=0;r<19;r++) kstrcpy(wn->term_buf[r],wn->term_buf[r+1]);
        wn->term_row = 19;
    }
    /* Copy up to 37 chars */
    int i=0;
    while (s[i] && i<37) { wn->term_buf[wn->term_row][i]=s[i]; i++; }
    wn->term_buf[wn->term_row][i]=0;
    wn->term_row++;
}

static void term_exec(window_t *wn, const char *cmd) {
    /* Upper-case copy */
    char uc[64]; int i=0;
    while (cmd[i] && i<63) {
        uc[i]=(cmd[i]>='a'&&cmd[i]<='z')?cmd[i]-32:cmd[i]; i++;
    }
    uc[i]=0;

    if (kstrcmp(uc,"HELP")==0) {
        term_println(wn,"Commands: HELP VER MEM");
        term_println(wn,"          TIME CLEAR ABOUT");
    } else if (kstrcmp(uc,"VER")==0) {
        term_println(wn,"ClaudeOS v1.0 GUI mode");
    } else if (kstrcmp(uc,"CLEAR")==0) {
        for (int r=0;r<20;r++) wn->term_buf[r][0]=0;
        wn->term_row=0;
    } else if (kstrcmp(uc,"TIME")==0) {
        term_println(wn,time_str);
    } else if (kstrcmp(uc,"MEM")==0) {
        term_println(wn,"Kernel @ 0x10000");
        term_println(wn,"VGA    @ 0xA0000");
        term_println(wn,"Stack  @ 0x9FFFF");
    } else if (kstrcmp(uc,"ABOUT")==0) {
        open_window(APP_ABOUT);
    } else if (uc[0]==0) {
        /* blank */
    } else {
        char ebuf[40]; kstrcpy(ebuf,"Unknown: "); kstrcat(ebuf,cmd);
        term_println(wn,ebuf);
    }
}

/* ════════════════════════════════════════════════════════ *
 *  Hit testing helpers                                   *
 * ════════════════════════════════════════════════════════ */
typedef enum {
    HIT_NONE, HIT_TITLEBAR, HIT_CLOSE, HIT_MIN,
    HIT_CLIENT, HIT_RESIZE
} hit_t;

static hit_t hit_test_window(window_t *wn, int mx, int my) {
    int x=wn->x,y=wn->y,w=wn->w,h=wn->h;
    if (!pt_in_rect(mx,my,x,y,w,h)) return HIT_NONE;
    /* Close button */
    int bx=x+w-BORDER-BTN_W-1, by=y+BORDER+1;
    if (pt_in_rect(mx,my,bx,by,BTN_W,BTN_W-1)) return HIT_CLOSE;
    /* Min button */
    int mx2=bx-BTN_W-2;
    if (pt_in_rect(mx,my,mx2,by,BTN_W,BTN_W-1)) return HIT_MIN;
    /* Titlebar */
    if (pt_in_rect(mx,my,x+BORDER,y+BORDER,w-BORDER*2,TITLEBAR_H)) return HIT_TITLEBAR;
    /* Client */
    int cx=x+BORDER, cy=y+BORDER+TITLEBAR_H;
    if (pt_in_rect(mx,my,cx,cy,w-BORDER*2,h-BORDER*2-TITLEBAR_H)) return HIT_CLIENT;
    return HIT_NONE;
}

/* ════════════════════════════════════════════════════════ *
 *  Main GUI entry point                                  *
 * ════════════════════════════════════════════════════════ */
void gui_run(void) {
    mouse_init();
    gfx_init();

    /* Open About window on first boot */
    open_window(APP_ABOUT);
    open_window(APP_TERMINAL);

    mouse_state_t ms;
    ms.x = GFX_W/2; ms.y = GFX_H/2;
    ms.left = ms.right = 0;

    int prev_left = 0;
    int drag_win  = -1;
    int drag_ox   = 0, drag_oy = 0;
    uint32_t last_clock = 0;
    uint32_t last_draw  = 0;

    /* Initial draw */
    update_clock();
    redraw_all();
    cursor_draw(ms.x, ms.y);

    while (1) {
        /* ── Update clock every second ─────────────────── */
        if (timer_ticks() - last_clock >= 1000) {
            last_clock = timer_ticks();
            update_clock();
        }

        /* ── Poll mouse ────────────────────────────────── */
        mouse_poll(&ms);

        int left_down  = ms.left && !prev_left;   /* just pressed  */
        int left_up    = !ms.left && prev_left;   /* just released */

        /* ── Handle dragging ───────────────────────────── */
        if (drag_win >= 0 && ms.left) {
            window_t *wn = &windows[drag_win];
            int nx = ms.x - drag_ox;
            int ny = ms.y - drag_oy;
            wn->x = clamp(nx, 0, GFX_W - wn->w);
            wn->y = clamp(ny, 0, GFX_H - TASKBAR_H - wn->h);
        }
        if (left_up && drag_win >= 0) drag_win = -1;

        /* ── Handle left click ─────────────────────────── */
        if (left_down) {
            int cx=ms.x, cy=ms.y;
            int tb_y = GFX_H - TASKBAR_H;
            int handled = 0;

            /* Start menu toggle */
            if (pt_in_rect(cx,cy, 1,tb_y+1, 30,TASKBAR_H-2)) {
                menu_open = !menu_open;
                handled = 1;
            }

            /* Menu items */
            if (!handled && menu_open) {
                int my2 = GFX_H - TASKBAR_H - MENU_ITEMS*MENU_ITEM_H - 2;
                if (pt_in_rect(cx,cy,1,my2,MENU_W,MENU_ITEMS*MENU_ITEM_H+2)) {
                    int item = (cy - my2 - 1) / MENU_ITEM_H;
                    if (item>=0 && item<MENU_ITEMS) {
                        menu_open = 0;
                        if (menu_items[item].app == APP_NONE) {
                            /* Reboot */
                            __asm__ volatile("cli; hlt");
                        } else {
                            open_window(menu_items[item].app);
                        }
                    }
                    handled = 1;
                } else {
                    menu_open = 0;
                }
            }

            /* Taskbar window buttons */
            if (!handled && pt_in_rect(cx,cy,34,tb_y+1,GFX_W-100,TASKBAR_H-2)) {
                int bx2=34;
                for (int i=0;i<MAX_WINDOWS;i++) {
                    if (!windows[i].open) continue;
                    if (pt_in_rect(cx,cy,bx2,tb_y+1,44,TASKBAR_H-2)) {
                        if (focused==i) windows[i].minimized=!windows[i].minimized;
                        else { focused=i; windows[i].minimized=0; }
                        handled=1; break;
                    }
                    bx2+=46;
                }
            }

            /* Desktop icons (double-click emulation: just single-click opens) */
            if (!handled) {
                for (int i=0;i<N_ICONS;i++) {
                    if (pt_in_rect(cx,cy,icons[i].x,icons[i].y,22,20)) {
                        open_window(icons[i].app);
                        handled=1; break;
                    }
                }
            }

            /* Window hit testing (front to back) */
            if (!handled) {
                /* Test focused window first */
                int order[MAX_WINDOWS];
                int oc=0;
                if (focused>=0) order[oc++]=focused;
                for (int i=MAX_WINDOWS-1;i>=0;i--)
                    if (i!=focused && windows[i].open) order[oc++]=i;

                for (int oi=0;oi<oc && !handled;oi++) {
                    int i=order[oi];
                    window_t *wn=&windows[i];
                    if (!wn->open||wn->minimized) continue;
                    hit_t hit=hit_test_window(wn,cx,cy);
                    if (hit==HIT_NONE) continue;
                    focused=i; handled=1;

                    if (hit==HIT_CLOSE) { close_window(i); break; }
                    if (hit==HIT_MIN)   { wn->minimized=1; break; }
                    if (hit==HIT_TITLEBAR) {
                        drag_win=i;
                        drag_ox=cx-wn->x;
                        drag_oy=cy-wn->y;
                    }
                    if (hit==HIT_CLIENT) {
                        /* Per-app click handling */
                        int clx=cx-(wn->x+BORDER+4);
                        int cly=cy-(wn->y+BORDER+TITLEBAR_H+4);

                        if (wn->app==APP_ABOUT && pt_in_rect(clx,cly,0,88,48,12))
                            close_window(i);

                        if (wn->app==APP_COLORS) {
                            /* Which palette swatch? */
                            int ci=(cly-12)/14*13 + clx/14;
                            if (ci>=0&&ci<52) wn->color_sel=ci;
                        }

                        if (wn->app==APP_CALC) {
                            /* Button grid */
                            static const char *bkeys[5][4]={
                                {"7","8","9","/"},{"4","5","6","*"},
                                {"1","2","3","-"},{"0",".","=","+"},
                                {"C","","",""}
                            };
                            static int calc_prev=0, calc_op=0;
                            for (int r=0;r<5;r++) for (int c=0;c<4;c++) {
                                if (!bkeys[r][c][0]) continue;
                                int bx3=c*18, by3=18+r*14;
                                if (pt_in_rect(clx,cly,bx3,by3,16,12)) {
                                    char k=bkeys[r][c][0];
                                    if (k>='0'&&k<='9') {
                                        if (kstrcmp(wn->calc_disp,"0")==0)
                                            wn->calc_disp[0]=k,wn->calc_disp[1]=0;
                                        else {
                                            int l=(int)kstrlen(wn->calc_disp);
                                            if(l<14){wn->calc_disp[l]=k;wn->calc_disp[l+1]=0;}
                                        }
                                    } else if (k=='C') {
                                        kstrcpy(wn->calc_disp,"0");
                                        calc_prev=0; calc_op=0;
                                    } else if (k=='+'||k=='-'||k=='*'||k=='/') {
                                        calc_prev=katoi(wn->calc_disp);
                                        calc_op=k;
                                        kstrcpy(wn->calc_disp,"0");
                                    } else if (k=='=') {
                                        int v=katoi(wn->calc_disp), res=calc_prev;
                                        if(calc_op=='+') res=calc_prev+v;
                                        if(calc_op=='-') res=calc_prev-v;
                                        if(calc_op=='*') res=calc_prev*v;
                                        if(calc_op=='/'&&v!=0) res=calc_prev/v;
                                        kitoa(res,wn->calc_disp,10);
                                        calc_op=0;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        /* ── Keyboard input for focused terminal ──────── */
        if (focused>=0 && windows[focused].app==APP_TERMINAL && !windows[focused].minimized) {
            if (inb(0x64)&1) {
                /* Check it's keyboard not mouse */
                if (!(inb(0x64)&0x20)) {
                    uint8_t sc=inb(0x60);
                    if (!(sc&0x80)) {
                        /* Scancode to ASCII (simple table) */
                        static const char sctab[128]={
                            0,0,'1','2','3','4','5','6','7','8','9','0','-','=','\b','\t',
                            'q','w','e','r','t','y','u','i','o','p','[',']','\n',0,
                            'a','s','d','f','g','h','j','k','l',';','\'','`',0,'\\',
                            'z','x','c','v','b','n','m',',','.','/',0,'*',0,' '
                        };
                        char c=(sc<58)?sctab[sc]:0;
                        window_t *wn=&windows[focused];
                        if (c=='\n') {
                            char echoline[40];
                            kstrcpy(echoline,"> "); kstrcat(echoline,wn->term_input);
                            term_println(wn,echoline);
                            term_exec(wn,wn->term_input);
                            wn->term_input[0]=0; wn->term_input_len=0;
                        } else if (c=='\b') {
                            if (wn->term_input_len>0)
                                wn->term_input[--wn->term_input_len]=0;
                        } else if (c && c!='\t' && wn->term_input_len<37) {
                            wn->term_input[wn->term_input_len++]=c;
                            wn->term_input[wn->term_input_len]=0;
                        }
                    }
                }
            }
        }

        prev_left = ms.left;

        /* ── Redraw at ~30 fps (every 33 ms) ──────────── */
        if (timer_ticks() - last_draw >= 33) {
            last_draw = timer_ticks();
            cursor_erase();
            redraw_all();
            cursor_draw(ms.x, ms.y);
        }

        /* Sleep until next timer tick */
        __asm__ volatile("hlt");
    }
}
