/*
 * apps.c  —  ClaudeOS extended applications
 *
 * All timing now uses timer_sleep(ms) backed by PIT IRQ0 at 1000 Hz,
 * so speed is consistent regardless of host CPU frequency.
 */

#include "commands.h"
#include "../kernel/vga.h"
#include "../kernel/keyboard.h"
#include "../kernel/timer.h"
#include "../libc/klib.h"
#include <stdint.h>

/* ── Port I/O ──────────────────────────────────────────── */
static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0,%1"::"a"(val),"Nd"(port));
}
static inline uint8_t inb(uint16_t port) {
    uint8_t v; __asm__ volatile ("inb %1,%0":"=a"(v):"Nd"(port)); return v;
}

/* ── PC Speaker ────────────────────────────────────────── */
static void speaker_on(uint32_t freq) {
    if (!freq) return;
    uint32_t div = 1193182 / freq;
    outb(0x43, 0xB6);
    outb(0x42, (uint8_t)(div & 0xFF));
    outb(0x42, (uint8_t)(div >> 8));
    outb(0x61, inb(0x61) | 0x03);
}
static void speaker_off(void) {
    outb(0x61, inb(0x61) & ~0x03);
}

/* Play a note for `ms` milliseconds then a short gap */
static void play_note(uint32_t freq, uint32_t ms) {
    if (freq) {
        speaker_on(freq);
        timer_sleep(ms);
        speaker_off();
    } else {
        timer_sleep(ms);   /* rest */
    }
    timer_sleep(20);       /* inter-note gap: 20 ms */
}

/* ── Non-blocking keyboard ─────────────────────────────── */
static int kb_ready(void)   { return inb(0x64) & 1; }
static uint8_t kb_scan(void){ return inb(0x60); }

/* ═══════════════════════════════════════════════════════ *
 *  TUNE  —  plays "Ode to Joy" on PC speaker             *
 * ═══════════════════════════════════════════════════════ */
int cmd_tune(const char *args) {
    (void)args;

    /* Frequencies in Hz; 0 = rest */
    static const uint32_t notes[] = {
        330,330,349,392,  392,349,330,294,
        262,262,294,330,  330,294,294,  0,
        330,330,349,392,  392,349,330,294,
        262,262,294,330,  294,262,262,  0
    };
    /* Durations in milliseconds */
    static const uint32_t durs[] = {
        240,240,240,240,  240,240,240,240,
        240,240,240,240,  360,120,480,120,
        240,240,240,240,  240,240,240,240,
        240,240,240,240,  360,120,480,120
    };

    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  Playing: Ode to Joy  (press any key to stop)\n\n");
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);

    for (int i = 0; i < 32; i++) {
        if (kb_ready()) { kb_scan(); break; }
        play_note(notes[i], durs[i]);
    }
    speaker_off();
    kprintf("  Done.\n\n");
    return 0;
}

/* ═══════════════════════════════════════════════════════ *
 *  PIANO  —  play notes with keyboard keys               *
 * ═══════════════════════════════════════════════════════ */
int cmd_piano(const char *args) {
    (void)args;

    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  PIANO MODE  (press Q to quit)\n\n");
    kprintf("  Keys: A S D F G H J  =  C D E F G A B\n");
    kprintf("        W E   T Y U    =  C# D#  F# G# A#\n\n");
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);

    while (1) {
        char c = keyboard_getchar();
        uint32_t freq = 0;
        const char *name = "";
        switch (c) {
            case 'a': case 'A': freq=262; name="C "; break;
            case 'w': case 'W': freq=277; name="C#"; break;
            case 's': case 'S': freq=294; name="D "; break;
            case 'e': case 'E': freq=311; name="D#"; break;
            case 'd': case 'D': freq=330; name="E "; break;
            case 'f': case 'F': freq=349; name="F "; break;
            case 't': case 'T': freq=370; name="F#"; break;
            case 'g': case 'G': freq=392; name="G "; break;
            case 'y': case 'Y': freq=415; name="G#"; break;
            case 'h': case 'H': freq=440; name="A "; break;
            case 'u': case 'U': freq=466; name="A#"; break;
            case 'j': case 'J': freq=494; name="B "; break;
            case 'k': case 'K': freq=523; name="C5"; break;
            case 'q': case 'Q':
                speaker_off();
                kprintf("\n  Exiting piano.\n\n");
                return 0;
            default: speaker_off(); continue;
        }
        if (freq) {
            vga_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
            kprintf("  [%s  %u Hz]\n", name, freq);
            vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
            speaker_on(freq);
            timer_sleep(180);   /* hold note 180 ms */
            speaker_off();
        }
    }
}

/* ═══════════════════════════════════════════════════════ *
 *  PRIMES  —  Sieve of Eratosthenes                      *
 * ═══════════════════════════════════════════════════════ */
int cmd_primes(const char *args) {
    while (*args == ' ') args++;
    int limit = *args ? katoi(args) : 200;
    if (limit < 2)    limit = 2;
    if (limit > 2000) limit = 2000;

    static uint8_t sieve[2001];
    kmemset(sieve, 1, (uint32_t)(limit + 1));
    sieve[0] = sieve[1] = 0;

    for (int i = 2; i * i <= limit; i++)
        if (sieve[i])
            for (int j = i*i; j <= limit; j += i)
                sieve[j] = 0;

    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  Primes up to %d:\n\n  ", limit);
    vga_set_color(VGA_COLOR_WHITE, VGA_COLOR_BLACK);

    int count = 0, col = 0;
    for (int i = 2; i <= limit; i++) {
        if (sieve[i]) {
            char buf[8]; kitoa(i, buf, 10);
            int pad = 5 - (int)kstrlen(buf);
            for (int p = 0; p < pad; p++) kprintf(" ");
            kprintf("%s", buf);
            count++; col++;
            if (col == 12) { kprintf("\n  "); col = 0; }
        }
    }
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    kprintf("\n\n  Found %d primes.\n\n", count);
    return 0;
}

/* ═══════════════════════════════════════════════════════ *
 *  MANDELBROT  —  ASCII art fractal                      *
 * ═══════════════════════════════════════════════════════ */
int cmd_mandelbrot(const char *args) {
    (void)args;

    const int W = 76, H = 20, MAX_ITER = 32;
#define FP 1024
    int x_min=-2560, x_max=1024, y_min=-1126, y_max=1126;
    static const char palette[] = " .-:;+=xX$&#@";

    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  Mandelbrot Set\n\n");

    for (int py = 0; py < H; py++) {
        kprintf("  ");
        for (int px = 0; px < W; px++) {
            int cr = x_min + (x_max - x_min) * px / W;
            int ci = y_min + (y_max - y_min) * py / H;
            int zr = 0, zi = 0, iter = 0;
            while (iter < MAX_ITER) {
                int zr2 = (zr*zr)/FP, zi2 = (zi*zi)/FP;
                if (zr2 + zi2 > 4*FP) break;
                int nzr = zr2 - zi2 + cr;
                int nzi = 2*((zr*zi)/FP) + ci;
                zr=nzr; zi=nzi; iter++;
            }
            int pi = iter * (int)(sizeof(palette)-2) / MAX_ITER;
            if (iter == MAX_ITER) {
                vga_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
                vga_putchar('@');
            } else if (pi > 8) {
                vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
                vga_putchar(palette[pi]);
            } else if (pi > 4) {
                vga_set_color(VGA_COLOR_CYAN, VGA_COLOR_BLACK);
                vga_putchar(palette[pi]);
            } else {
                vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
                vga_putchar(palette[pi]);
            }
        }
        vga_putchar('\n');
    }
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    kprintf("\n");
    return 0;
}

/* ═══════════════════════════════════════════════════════ *
 *  TYPE  —  typewriter effect                            *
 * ═══════════════════════════════════════════════════════ */
int cmd_type(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        kprintf("  Usage: TYPE <text>\n");
        return 1;
    }
    vga_set_color(VGA_COLOR_WHITE, VGA_COLOR_BLACK);
    kprintf("\n  ");
    while (*args) {
        vga_putchar(*args++);
        speaker_on(1200);
        timer_sleep(30);    /* 30 ms key-click tone */
        speaker_off();
        timer_sleep(40);    /* 40 ms between characters */
    }
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    kprintf("\n\n");
    return 0;
}

/* ═══════════════════════════════════════════════════════ *
 *  HEX  —  hex dump of physical memory                  *
 * ═══════════════════════════════════════════════════════ */
static uint32_t parse_hex(const char *s) {
    uint32_t v = 0;
    while (*s) {
        char c = *s++;
        if      (c>='0'&&c<='9') v=v*16+(uint32_t)(c-'0');
        else if (c>='A'&&c<='F') v=v*16+(uint32_t)(c-'A'+10);
        else if (c>='a'&&c<='f') v=v*16+(uint32_t)(c-'a'+10);
        else break;
    }
    return v;
}

int cmd_hex(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        kprintf("  Usage: HEX <address_hex> [count]\n");
        kprintf("  Example: HEX 10000 64    (kernel entry)\n");
        kprintf("           HEX B8000 32    (VGA buffer)\n");
        return 1;
    }
    uint32_t addr = parse_hex(args);
    while (*args && *args != ' ') args++;
    while (*args == ' ') args++;
    uint32_t count = *args ? (uint32_t)katoi(args) : 64;
    if (count > 256) count = 256;

    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  Hex dump: 0x%x (%u bytes)\n\n", addr, count);

    volatile uint8_t *mem = (volatile uint8_t *)addr;
    for (uint32_t i = 0; i < count; i += 16) {
        vga_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
        char abuf[12]; kutoa(addr+i, abuf, 16);
        for (int p=(int)kstrlen(abuf);p<8;p++) kprintf("0");
        kprintf("%s  ", abuf);

        vga_set_color(VGA_COLOR_WHITE, VGA_COLOR_BLACK);
        for (uint32_t j = 0; j < 16; j++) {
            if (i+j < count) {
                uint8_t b = mem[i+j];
                char hbuf[4]; kutoa(b,hbuf,16);
                if (b<16) kprintf("0");
                kprintf("%s ",hbuf);
            } else kprintf("   ");
            if (j==7) kprintf(" ");
        }
        vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
        kprintf(" |");
        for (uint32_t j=0;j<16&&i+j<count;j++) {
            uint8_t b=mem[i+j];
            vga_putchar((b>=0x20&&b<0x7F)?(char)b:'.');
        }
        kprintf("|\n");
    }
    kprintf("\n");
    return 0;
}

/* ═══════════════════════════════════════════════════════ *
 *  SNAKE  —  classic snake game                          *
 *  Speed is now tick-based: frame period in ms           *
 * ═══════════════════════════════════════════════════════ */

#define SNAKE_W   38
#define SNAKE_H   18
#define SNAKE_MAX 200

typedef struct { int x, y; } Point;
static Point  snake[SNAKE_MAX];
static int    slen, dx, dy;
static Point  food;
static uint32_t rng_state;

static uint32_t rng_next(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

static void snake_draw_border(int ox, int oy) {
    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    vga_set_cursor(oy, ox);
    for (int i=0;i<SNAKE_W+2;i++) vga_putchar(i==0?'+':(i==SNAKE_W+1?'+':'-'));
    vga_set_cursor(oy+SNAKE_H+1, ox);
    for (int i=0;i<SNAKE_W+2;i++) vga_putchar(i==0?'+':(i==SNAKE_W+1?'+':'-'));
    for (int r=1;r<=SNAKE_H;r++) {
        vga_set_cursor(oy+r,ox);            vga_putchar('|');
        vga_set_cursor(oy+r,ox+SNAKE_W+1); vga_putchar('|');
    }
}

static void snake_put(int gx, int gy, char c, vga_color_t col, int ox, int oy) {
    vga_set_color(col, VGA_COLOR_BLACK);
    vga_set_cursor(oy+1+gy, ox+1+gx);
    vga_putchar(c);
}

int cmd_snake(const char *args) {
    (void)args;
    outb(0x70,0x00); rng_state = inb(0x71) + 1;

    int ox = (80-(SNAKE_W+2))/2, oy = 1;
    vga_clear();
    vga_set_color(VGA_COLOR_LIGHT_BROWN, VGA_COLOR_BLACK);
    vga_set_cursor(0, 26); kprintf("  SNAKE  (WASD=move  Q=quit)");
    snake_draw_border(ox, oy);

    slen=3; dx=1; dy=0;
    for (int i=0;i<slen;i++) { snake[i].x=SNAKE_W/2-i; snake[i].y=SNAKE_H/2; }
    food.x=(int)(rng_next()%(uint32_t)SNAKE_W);
    food.y=(int)(rng_next()%(uint32_t)SNAKE_H);

    int score=0, running=1;
    uint32_t last_move = timer_ticks();

    while (running) {
        /* Draw */
        snake_put(food.x,food.y,'*',VGA_COLOR_LIGHT_RED,ox,oy);
        snake_put(snake[0].x,snake[0].y,'@',VGA_COLOR_LIGHT_GREEN,ox,oy);
        for (int i=1;i<slen;i++)
            snake_put(snake[i].x,snake[i].y,'o',VGA_COLOR_GREEN,ox,oy);

        vga_set_color(VGA_COLOR_WHITE, VGA_COLOR_BLACK);
        vga_set_cursor(oy+SNAKE_H+2,ox);
        kprintf("  Score: %d   Length: %d   Ticks: %u   ",
                score, slen, timer_ticks());

        /*
         * Frame rate: starts at 200 ms/frame (5 fps), speeds up.
         * This is pure wall-clock time via PIT — consistent on any CPU.
         */
        uint32_t frame_ms = 200;
        if (score >  5) frame_ms = 150;
        if (score > 10) frame_ms = 110;
        if (score > 20) frame_ms =  80;
        if (score > 35) frame_ms =  60;

        /* Read all pending scancodes during the frame window */
        uint32_t frame_end = timer_ticks() + frame_ms;
        while (timer_ticks() < frame_end) {
            if (kb_ready()) {
                uint8_t sc = kb_scan();
                if (sc & 0x80) continue;
                /* WASD scancodes: W=0x11 S=0x1F A=0x1E D=0x20 Q=0x10 */
                if (sc==0x11 && dy!= 1) { dx= 0; dy=-1; }
                if (sc==0x1F && dy!=-1) { dx= 0; dy= 1; }
                if (sc==0x1E && dx!= 1) { dx=-1; dy= 0; }
                if (sc==0x20 && dx!=-1) { dx= 1; dy= 0; }
                if (sc==0x10) { running=0; break; }
            }
            __asm__ volatile("hlt");   /* sleep until next IRQ */
        }
        if (!running) break;

        /* Only move once per frame */
        if (timer_ticks() - last_move < frame_ms) continue;
        last_move = timer_ticks();

        Point tail = snake[slen-1];
        for (int i=slen-1;i>0;i--) snake[i]=snake[i-1];
        snake[0].x += dx; snake[0].y += dy;

        /* Wall collision */
        if (snake[0].x<0||snake[0].x>=SNAKE_W||
            snake[0].y<0||snake[0].y>=SNAKE_H) { running=0; break; }

        /* Self collision */
        for (int i=1;i<slen;i++)
            if (snake[0].x==snake[i].x&&snake[0].y==snake[i].y) { running=0; break; }
        if (!running) break;

        snake_put(tail.x,tail.y,' ',VGA_COLOR_BLACK,ox,oy);

        if (snake[0].x==food.x&&snake[0].y==food.y) {
            score++;
            if (slen<SNAKE_MAX) { snake[slen]=tail; slen++; }
            /* Eat sound: quick chirp */
            speaker_on(880); timer_sleep(30); speaker_off();
            do {
                food.x=(int)(rng_next()%(uint32_t)SNAKE_W);
                food.y=(int)(rng_next()%(uint32_t)SNAKE_H);
                int ok=1;
                for (int i=0;i<slen;i++)
                    if (food.x==snake[i].x&&food.y==snake[i].y){ok=0;break;}
                if (ok) break;
            } while(1);
        }
    }

    /* Game over sound: descending tones */
    play_note(440, 100);
    play_note(330, 100);
    play_note(220, 200);

    vga_set_color(VGA_COLOR_LIGHT_RED, VGA_COLOR_BLACK);
    vga_set_cursor(oy+SNAKE_H/2,   ox+SNAKE_W/2-6); kprintf("  GAME OVER  ");
    vga_set_color(VGA_COLOR_WHITE,  VGA_COLOR_BLACK);
    vga_set_cursor(oy+SNAKE_H/2+1, ox+SNAKE_W/2-6); kprintf("  Score: %d   ", score);
    vga_set_cursor(24,0);
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    kprintf("\n");
    return 0;
}

/* ═══════════════════════════════════════════════════════ *
 *  REPEAT  —  run a command N times                      *
 * ═══════════════════════════════════════════════════════ */
int cmd_repeat(const char *args) {
    while (*args==' ') args++;
    if (!*args) {
        kprintf("  Usage: REPEAT <n> <command>\n");
        kprintf("  Example: REPEAT 5 BEEP\n");
        return 1;
    }
    int n = katoi(args);
    if (n<=0||n>100) { kprintf("  n must be 1-100\n"); return 1; }
    while (*args&&*args!=' ') args++;
    while (*args==' ') args++;
    if (!*args) { kprintf("  No command given.\n"); return 1; }

    static const struct { const char *name; int(*fn)(const char*); } rtab[] = {
        {"BEEP",cmd_beep},{"TUNE",cmd_tune},{"ECHO",cmd_echo},{"PRIMES",cmd_primes},{0,0}
    };

    char cname[32]; int ci=0;
    const char *cargs=args;
    while (*cargs&&*cargs!=' '&&ci<31) cname[ci++]=*cargs++;
    cname[ci]=0;
    while (*cargs==' ') cargs++;
    for (int i=0;cname[i];i++) if(cname[i]>='a'&&cname[i]<='z') cname[i]-=32;

    for (int r=0;rtab[r].name;r++) {
        if (kstrcmp(cname,rtab[r].name)==0) {
            for (int i=0;i<n;i++) {
                kprintf("  [%d/%d] ",i+1,n);
                rtab[r].fn(cargs);
            }
            return 0;
        }
    }
    kprintf("  Supported: BEEP TUNE ECHO PRIMES\n");
    return 1;
}
