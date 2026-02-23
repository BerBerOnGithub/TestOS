/*
 * timer.c  —  Hardware clock for ClaudeOS
 *
 * Sets up:
 *   IDT   — 256 interrupt gates (all → default spurious handler)
 *   PIC   — remaps 8259A so IRQ0-7 → vectors 0x20-0x27
 *   PIT   — channel 0 at 1000 Hz (1 ms per tick)
 *
 * ISR stubs are in timer_asm.S (pure asm pushad/popad wrappers).
 * The C handler tick_handler() is called from there.
 */

#include "timer.h"
#include <stdint.h>

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0,%1"::"a"(val),"Nd"(port));
}
static inline uint8_t inb(uint16_t port) {
    uint8_t v; __asm__ volatile ("inb %1,%0":"=a"(v):"Nd"(port)); return v;
}
static inline void io_wait(void) { outb(0x80, 0); }

/* ── Tick counter ────────────────────────────────────────── */
volatile uint32_t tick_count = 0;

/* Called from assembly IRQ0 stub */
void tick_handler(void) {
    tick_count++;
    outb(0x20, 0x20);   /* EOI → master PIC */
}

/* Called from assembly default stub */
void spurious_handler(void) {
    outb(0xA0, 0x20);
    outb(0x20, 0x20);
}

/* ── IDT ─────────────────────────────────────────────────── */
typedef struct __attribute__((packed)) {
    uint16_t offset_low;
    uint16_t selector;
    uint8_t  zero;
    uint8_t  type_attr;   /* 0x8E = present, ring0, 32-bit interrupt gate */
    uint16_t offset_high;
} idt_entry_t;

typedef struct __attribute__((packed)) {
    uint16_t limit;
    uint32_t base;
} idt_ptr_t;

static idt_entry_t idt[256];
static idt_ptr_t   idt_ptr;

/* Declared in timer_asm.S */
extern void isr_default_stub(void);
extern void irq0_stub(void);

static void idt_set_gate(uint8_t num, uint32_t handler) {
    idt[num].offset_low  = (uint16_t)(handler & 0xFFFF);
    idt[num].selector    = 0x08;
    idt[num].zero        = 0;
    idt[num].type_attr   = 0x8E;
    idt[num].offset_high = (uint16_t)(handler >> 16);
}

/* ── PIC remap ───────────────────────────────────────────── */
static void pic_remap(void) {
    uint8_t m1 = inb(0x21), m2 = inb(0xA1);
    outb(0x20, 0x11); io_wait();   /* ICW1: init */
    outb(0xA0, 0x11); io_wait();
    outb(0x21, 0x20); io_wait();   /* ICW2: master offset → 0x20 */
    outb(0xA1, 0x28); io_wait();   /* ICW2: slave  offset → 0x28 */
    outb(0x21, 0x04); io_wait();   /* ICW3: slave on IRQ2 */
    outb(0xA1, 0x02); io_wait();   /* ICW3: slave cascade id */
    outb(0x21, 0x01); io_wait();   /* ICW4: 8086 mode */
    outb(0xA1, 0x01); io_wait();
    outb(0x21, m1 & ~0x01);        /* restore masks, unmask IRQ0 */
    outb(0xA1, m2);
}

/* ── PIT channel 0 ───────────────────────────────────────── */
static void pit_init(void) {
    /* Mode 2 (rate generator), channel 0, lo/hi byte */
    outb(0x43, 0x34);
    outb(0x40, (uint8_t)(PIT_DIVISOR & 0xFF));
    outb(0x40, (uint8_t)(PIT_DIVISOR >> 8));
}

/* ── Public API ──────────────────────────────────────────── */
void timer_init(void) {
    /* Fill all 256 IDT slots with the spurious handler */
    uint32_t def = (uint32_t)isr_default_stub;
    for (int i = 0; i < 256; i++) idt_set_gate((uint8_t)i, def);

    /* IRQ0 (vector 0x20) → real tick handler */
    idt_set_gate(0x20, (uint32_t)irq0_stub);

    idt_ptr.limit = sizeof(idt) - 1;
    idt_ptr.base  = (uint32_t)&idt;
    __asm__ volatile ("lidt %0" : : "m"(idt_ptr));

    pic_remap();
    pit_init();
    __asm__ volatile ("sti");
}

uint32_t timer_ticks(void) {
    return tick_count;
}

void timer_sleep(uint32_t ms) {
    uint32_t target = tick_count + ms;
    while (tick_count < target)
        __asm__ volatile ("hlt");
}
