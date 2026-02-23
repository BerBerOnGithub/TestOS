#include "klib.h"
#include "../kernel/vga.h"
#include <stdarg.h>

/* ── String ──────────────────────────────────────────── */
size_t kstrlen(const char *s) {
    size_t n = 0; while (s[n]) n++; return n;
}
int kstrcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}
int kstrncmp(const char *a, const char *b, size_t n) {
    while (n-- && *a && *a == *b) { a++; b++; }
    if (!n) return 0;
    return (unsigned char)*a - (unsigned char)*b;
}
char *kstrcpy(char *dst, const char *src) {
    char *r = dst; while ((*dst++ = *src++)); return r;
}
char *kstrcat(char *dst, const char *src) {
    char *r = dst; while (*dst) dst++; while ((*dst++ = *src++)); return r;
}
const char *kstrchr(const char *s, char c) {
    while (*s) { if (*s == c) return s; s++; }
    return 0;
}

/* ── Conversion ─────────────────────────────────────── */
void kutoa(uint32_t val, char *buf, int base) {
    static const char digits[] = "0123456789ABCDEF";
    char tmp[34]; int i = 0;
    if (val == 0) { buf[0]='0'; buf[1]=0; return; }
    while (val) { tmp[i++] = digits[val % base]; val /= base; }
    int j = 0; while (i--) buf[j++] = tmp[i]; buf[j] = 0;
}
void kitoa(int val, char *buf, int base) {
    if (base == 10 && val < 0) { *buf++ = '-'; kutoa((uint32_t)(-val), buf, base); }
    else kutoa((uint32_t)val, buf, base);
}
int katoi(const char *s) {
    int n = 0, neg = 0;
    while (*s == ' ') s++;
    if (*s == '-') { neg = 1; s++; }
    while (*s >= '0' && *s <= '9') n = n * 10 + (*s++ - '0');
    return neg ? -n : n;
}

/* ── Memory ─────────────────────────────────────────── */
void *kmemset(void *dst, int c, size_t n) {
    uint8_t *p = dst; while (n--) *p++ = (uint8_t)c; return dst;
}
void *kmemcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst; const uint8_t *s = src; while (n--) *d++ = *s++; return dst;
}

/* ── Formatted print ─────────────────────────────────── */
void kprintf(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    char buf[32];
    while (*fmt) {
        if (*fmt != '%') { vga_putchar(*fmt++); continue; }
        fmt++;
        switch (*fmt) {
            case 's': { const char *s = va_arg(ap, const char *); vga_puts(s ? s : "(null)"); break; }
            case 'd': kitoa(va_arg(ap, int),      buf, 10); vga_puts(buf); break;
            case 'u': kutoa(va_arg(ap, uint32_t), buf, 10); vga_puts(buf); break;
            case 'x': kutoa(va_arg(ap, uint32_t), buf, 16); vga_puts(buf); break;
            case 'c': vga_putchar((char)va_arg(ap, int)); break;
            case '%': vga_putchar('%'); break;
            default:  vga_putchar(*fmt); break;
        }
        fmt++;
    }
    va_end(ap);
}
