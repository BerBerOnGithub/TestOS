# timer_asm.S  —  ISR entry stubs for ClaudeOS
#
# GCC's __attribute__((interrupt)) is not available in -m32 freestanding
# without -mgeneral-regs-only, so we write the stubs by hand.
#
# Each stub:
#   1. Saves all registers (pushad)
#   2. Calls the C handler
#   3. Restores all registers (popad)
#   4. Returns from interrupt (iret)

.code32
.section .text

.extern tick_handler
.extern spurious_handler

# ── IRQ0 stub (PIT tick, vector 0x20) ────────────────────
.globl irq0_stub
irq0_stub:
    pusha
    cld
    call tick_handler
    popa
    iret

# ── Default spurious ISR stub (all other vectors) ─────────
.globl isr_default_stub
isr_default_stub:
    pusha
    cld
    call spurious_handler
    popa
    iret
