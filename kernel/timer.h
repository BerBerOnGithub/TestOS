#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

/*
 * timer.h  —  Hardware clock via PIT channel 0 + IRQ0
 *
 * Call timer_init() once at boot.  After that:
 *   timer_ticks()      → ms elapsed since boot  (uint32_t)
 *   timer_sleep(ms)    → block for ms milliseconds
 *   timer_sleep_us(us) → block for us microseconds (min ~1ms resolution)
 */

/* PIT fires at 1193182 Hz.  We divide to get 1000 Hz → 1 ms per tick. */
#define PIT_HZ       1000
#define PIT_DIVISOR  (1193182 / PIT_HZ)   /* = 1193 */

void     timer_init(void);          /* set up IDT, remap PIC, start PIT    */
uint32_t timer_ticks(void);         /* returns ms since timer_init()        */
void     timer_sleep(uint32_t ms);  /* busy-wait using tick counter         */

#endif
