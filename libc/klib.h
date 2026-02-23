#ifndef KLIB_H
#define KLIB_H

#include <stdint.h>
#include <stddef.h>

/* ── String ──────────────────────────────────────────── */
size_t   kstrlen(const char *s);
int      kstrcmp(const char *a, const char *b);
int      kstrncmp(const char *a, const char *b, size_t n);
char    *kstrcpy(char *dst, const char *src);
char    *kstrcat(char *dst, const char *src);
const char *kstrchr(const char *s, char c);

/* ── Conversion ─────────────────────────────────────── */
void     kitoa(int val, char *buf, int base);   /* signed */
void     kutoa(uint32_t val, char *buf, int base); /* unsigned */
int      katoi(const char *s);

/* ── Memory ─────────────────────────────────────────── */
void    *kmemset(void *dst, int c, size_t n);
void    *kmemcpy(void *dst, const void *src, size_t n);

/* ── Formatted print (VGA) ───────────────────────────── */
/* Supports: %s %d %u %x %c %% */
void kprintf(const char *fmt, ...);

#endif
