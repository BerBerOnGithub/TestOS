#include "commands.h"
#include "../kernel/vga.h"
#include "../kernel/timer.h"
#include "../libc/klib.h"
#include <stdint.h>

/* ── Forward-declared helpers ─────────────────────────── */
static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}
static inline uint8_t inb(uint16_t port) {
    uint8_t v; __asm__ volatile ("inb %1, %0" : "=a"(v) : "Nd"(port)); return v;
}

/* ─────────────────────────────────────────────────────── *
 *  HELP                                                   *
 * ─────────────────────────────────────────────────────── */
int cmd_help(const char *args) {
    (void)args;
    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  ClaudeOS v1.0 - Available Commands\n");
    kprintf("  ===================================\n\n");
    vga_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
    kprintf("  HELP              Show this help screen\n");
    kprintf("  VER               Display OS version\n");
    kprintf("  CLEAR             Clear the screen\n");
    kprintf("  ECHO  [text]      Print text to screen\n");
    kprintf("  CALC  [expr]      Calculator  e.g. CALC 12 + 34\n");
    kprintf("  MEM               Show memory information\n");
    kprintf("  TIME              Show RTC clock + PIT ticks\n");
    kprintf("  COLOR [fg] [bg]   Set text colors (0-15)\n");
    kprintf("  SYSINFO           CPU and system information\n");
    kprintf("  BEEP              Sound PC speaker\n");
    kprintf("  REBOOT            Reboot the computer\n");
    vga_set_color(VGA_COLOR_LIGHT_MAGENTA, VGA_COLOR_BLACK);
    kprintf("\n  --- Apps & Games ---\n\n");
    vga_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
    kprintf("  SNAKE             Playable Snake game (WASD, Q=quit)\n");
    kprintf("  PIANO             PC speaker piano (A-J keys, Q=quit)\n");
    kprintf("  TUNE              Play Ode to Joy on PC speaker\n");
    kprintf("  MANDELBROT        ASCII art Mandelbrot fractal\n");
    kprintf("  PRIMES [n]        Sieve of Eratosthenes up to n\n");
    kprintf("  HEX <addr> [n]    Hex dump of physical memory\n");
    kprintf("  TYPE <text>       Typewriter effect with beeps\n");
    kprintf("  REPEAT <n> <cmd>  Run a command n times\n");
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    kprintf("\n");
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  VER                                                    *
 * ─────────────────────────────────────────────────────── */
int cmd_ver(const char *args) {
    (void)args;
    vga_set_color(VGA_COLOR_WHITE, VGA_COLOR_BLACK);
    kprintf("\n  ClaudeOS Version 1.0  (c) 2025 ClaudeOS Project\n");
    kprintf("  Kernel: claudekernel-1.0  Arch: x86 (32-bit protected mode)\n\n");
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  ECHO                                                   *
 * ─────────────────────────────────────────────────────── */
int cmd_echo(const char *args) {
    /* Skip leading spaces */
    while (*args == ' ') args++;
    kprintf("%s\n", args);
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  CLEAR                                                  *
 * ─────────────────────────────────────────────────────── */
int cmd_clear(const char *args) {
    (void)args;
    vga_clear();
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  CALC  -  simple integer expression: A <op> B           *
 *  Supports: + - * / % and order is left-to-right         *
 * ─────────────────────────────────────────────────────── */
int cmd_calc(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        kprintf("  Usage: CALC <number> <op> <number>\n");
        kprintf("  Ops: + - * / %%\n");
        kprintf("  Example: CALC 100 / 4\n");
        return 1;
    }

    /* Parse: [num] [op] [num] */
    char buf[32]; int i = 0;
    while (*args == ' ') args++;
    while (*args && *args != ' ' && i < 31) buf[i++] = *args++;
    buf[i] = 0;
    int a = katoi(buf);

    while (*args == ' ') args++;
    char op = *args++;

    while (*args == ' ') args++;
    i = 0;
    while (*args && *args != ' ' && i < 31) buf[i++] = *args++;
    buf[i] = 0;
    int b = katoi(buf);

    int result = 0;
    int ok = 1;
    switch (op) {
        case '+': result = a + b; break;
        case '-': result = a - b; break;
        case '*': result = a * b; break;
        case '/':
            if (b == 0) { kprintf("  Error: Division by zero\n"); return 1; }
            result = a / b; break;
        case '%':
            if (b == 0) { kprintf("  Error: Division by zero\n"); return 1; }
            result = a % b; break;
        default:
            kprintf("  Error: Unknown operator '%c'\n", op); ok = 0; break;
    }
    if (ok) {
        vga_set_color(VGA_COLOR_WHITE, VGA_COLOR_BLACK);
        kprintf("  %d %c %d = %d\n", a, op, b, result);
        vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    }
    return ok ? 0 : 1;
}

/* ─────────────────────────────────────────────────────── *
 *  MEM  -  read BIOS memory map via multiboot / CMOS      *
 * ─────────────────────────────────────────────────────── */
int cmd_mem(const char *args) {
    (void)args;

    /* Read conventional memory size from CMOS (port 0x71 regs 0x15/0x16/0x17/0x18) */
    outb(0x70, 0x15); uint8_t lo = inb(0x71);
    outb(0x70, 0x16); uint8_t hi = inb(0x71);
    uint32_t conv_kb = (uint32_t)((hi << 8) | lo);

    outb(0x70, 0x17); uint8_t xlo = inb(0x71);
    outb(0x70, 0x18); uint8_t xhi = inb(0x71);
    uint32_t ext_kb  = (uint32_t)((xhi << 8) | xlo);

    uint32_t total_kb = 640 + ext_kb;   /* conventional base + extended */

    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  Memory Information\n");
    kprintf("  ==================\n");
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    kprintf("  Base memory (conv.)  : %u KB\n", conv_kb ? conv_kb : 640);
    kprintf("  Extended memory      : %u KB  (%u MB)\n", ext_kb, ext_kb / 1024);
    kprintf("  Total visible        : %u KB  (%u MB)\n", total_kb, total_kb / 1024);
    kprintf("  Kernel load address  : 0x10000\n");
    kprintf("  VGA buffer           : 0xB8000\n");
    kprintf("\n");
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  TIME  -  read PIT counter tick count                   *
 * ─────────────────────────────────────────────────────── */
int cmd_time(const char *args) {
    (void)args;

    /* Read PIT channel 0 (latch + read low/high bytes) */
    outb(0x43, 0x00);           /* latch channel 0 */
    uint8_t lo = inb(0x40);
    uint8_t hi = inb(0x40);
    uint16_t pit = (uint16_t)((hi << 8) | lo);

    /* CMOS RTC: read seconds/minutes/hours */
    outb(0x70, 0x00); uint8_t sec  = inb(0x71);
    outb(0x70, 0x02); uint8_t min  = inb(0x71);
    outb(0x70, 0x04); uint8_t hour = inb(0x71);

    /* Values come as BCD - convert */
    sec  = (sec  >> 4) * 10 + (sec  & 0x0F);
    min  = (min  >> 4) * 10 + (min  & 0x0F);
    hour = (hour >> 4) * 10 + (hour & 0x0F);

    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  System Time\n");
    kprintf("  ===========\n");
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    kprintf("  RTC Time       : %u:%u:%u (UTC, BIOS RTC)\n", hour, min, sec);
    kprintf("  PIT Channel 0  : %u (decrements from 65535 at ~1.19 MHz)\n", pit);
    kprintf("\n");
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  COLOR  - change terminal colors                        *
 *  Usage: COLOR <fg 0-15> <bg 0-15>                       *
 * ─────────────────────────────────────────────────────── */
int cmd_color(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        kprintf("  Usage: COLOR <fg 0-15> <bg 0-15>\n");
        kprintf("  Colors: 0=Black 1=Blue 2=Green 3=Cyan 4=Red\n");
        kprintf("          5=Magenta 6=Brown 7=LGrey 8=DGrey 9=LBlue\n");
        kprintf("         10=LGreen 11=LCyan 12=LRed 13=LMagenta\n");
        kprintf("         14=Yellow 15=White\n");
        return 1;
    }
    int fg = katoi(args);
    while (*args && *args != ' ') args++;
    while (*args == ' ') args++;
    int bg = katoi(args);

    if (fg < 0 || fg > 15 || bg < 0 || bg > 15) {
        kprintf("  Error: Colors must be 0-15\n");
        return 1;
    }
    vga_set_color((vga_color_t)fg, (vga_color_t)bg);
    kprintf("  Color set: fg=%d bg=%d\n", fg, bg);
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  SYSINFO                                                *
 * ─────────────────────────────────────────────────────── */
int cmd_sysinfo(const char *args) {
    (void)args;

    /* CPUID to get vendor string */
    uint32_t eax, ebx, ecx, edx;
    __asm__ volatile ("cpuid"
        : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
        : "a"(0));

    char vendor[13];
    kmemcpy(vendor + 0, &ebx, 4);
    kmemcpy(vendor + 4, &edx, 4);
    kmemcpy(vendor + 8, &ecx, 4);
    vendor[12] = 0;

    /* Max CPUID level */
    uint32_t max_leaf = eax;

    /* CPU brand / family */
    uint32_t family = 0, model = 0, stepping = 0;
    if (max_leaf >= 1) {
        __asm__ volatile ("cpuid"
            : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
            : "a"(1));
        stepping = eax & 0xF;
        model    = (eax >> 4) & 0xF;
        family   = (eax >> 8) & 0xF;
    }

    vga_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    kprintf("\n  ClaudeOS System Information\n");
    kprintf("  ===========================\n");
    vga_set_color(VGA_COLOR_LIGHT_GREY, VGA_COLOR_BLACK);
    kprintf("  OS             : ClaudeOS v1.0\n");
    kprintf("  Architecture   : x86 (32-bit Protected Mode)\n");
    kprintf("  CPU Vendor     : %s\n", vendor);
    kprintf("  CPU Family     : %u  Model: %u  Stepping: %u\n", family, model, stepping);
    kprintf("  CPUID max leaf : %u\n", max_leaf);
    kprintf("  VGA Mode       : Text 80x25, 16 colors\n");
    kprintf("  Kernel base    : 0x00010000\n");
    kprintf("  Stack top      : 0x0009FFFF\n");
    kprintf("\n");
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  BEEP  - PC speaker via PIT channel 2                   *
 * ─────────────────────────────────────────────────────── */
int cmd_beep(const char *args) {
    (void)args;

    /* Frequency ~1000 Hz: divisor = 1193180 / 1000 = 1193 */
    uint32_t div = 1193;

    outb(0x43, 0xB6);               /* channel 2, square wave */
    outb(0x42, (uint8_t)(div & 0xFF));
    outb(0x42, (uint8_t)(div >> 8));

    /* Enable speaker */
    uint8_t tmp = inb(0x61);
    outb(0x61, tmp | 0x03);

    timer_sleep(200);   /* 200 ms beep — hardware timed, speed-independent */

    /* Disable speaker */
    outb(0x61, inb(0x61) & ~0x03);

    kprintf("  *BEEP*\n");
    return 0;
}

/* ─────────────────────────────────────────────────────── *
 *  REBOOT  - triple-fault or keyboard controller reset    *
 * ─────────────────────────────────────────────────────── */
int cmd_reboot(const char *args) {
    (void)args;
    kprintf("  Rebooting...\n");
    timer_sleep(500);               /* 500 ms so the message is visible */
    outb(0x64, 0xFE);

    /* Fallback: triple fault via null IDT */
    __asm__ volatile (
        "lidt %0\n"
        "int $0\n"
        : : "m"((uint8_t){0})
    );
    while (1) __asm__ volatile("hlt");
    return 0;
}
