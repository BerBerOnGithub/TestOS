# ClaudeOS v1.0

A real, from-scratch x86 operating system — **no Linux, no BIOS abstractions, no runtime library** underneath it. Just hardware.

```
ClaudeOS boots → real mode → loads kernel → protected mode → CLI shell
```

---

## What it actually is

| Layer | File(s) | What it does |
|---|---|---|
| **Bootloader** | `boot/boot.S` | 512-byte MBR. Loaded by BIOS at 0x7C00. Reads kernel sectors from disk (INT 13h), sets up a GDT, enters 32-bit protected mode, jumps to kernel. |
| **Kernel entry** | `kernel/kernel_entry.S` | First thing the CPU executes at 0x10000. Sets ESP, calls `kmain()`. |
| **VGA driver** | `kernel/vga.c` | Writes directly to the VGA text buffer at physical address 0xB8000. Handles scrolling, colours, hardware cursor via port I/O. |
| **Keyboard driver** | `kernel/keyboard.c` | Reads PS/2 scancodes from port 0x60, translates to ASCII with a US QWERTY table. |
| **Kernel libc** | `libc/klib.c` | Freestanding string/memory/conversion functions + `kprintf()`. No stdlib. |
| **Shell + utilities** | `kernel/kmain.c`, `utils/commands.c` | Command loop + 11 built-in programs. |

---

## Memory layout

```
0x00000000 – 0x000004FF   Real-mode IVT + BDA
0x00007C00 – 0x00007DFF   Bootloader (512 bytes, placed by BIOS)
0x00010000 – 0x0001xxxx   Kernel binary (loaded here by bootloader)
0x0009FFFF                Stack top (grows downward)
0x000A0000 – 0x000BFFFF   VGA RAM
0x000B8000 – 0x000BFFFF   VGA text buffer (80×25, 16 colours)
```

---

## Built-in commands

| Command | Description |
|---|---|
| `HELP` | List all commands |
| `VER` | Display OS version |
| `CLEAR` | Clear the screen |
| `ECHO <text>` | Print text to screen |
| `CALC <a> <op> <b>` | Integer calculator (`+ - * / %`) |
| `MEM` | Read CMOS for memory size, show layout |
| `TIME` | Read RTC clock and PIT counter |
| `COLOR <fg> <bg>` | Change terminal colours (0–15) |
| `SYSINFO` | CPUID vendor, family, model, stepping |
| `BEEP` | Sound the PC speaker at 1 kHz |
| `REBOOT` | Reset via keyboard controller pulse |

---

## Requirements

```
gcc        (tested: GCC 13.x)
as         (GNU assembler — part of binutils)
ld         (GNU linker)
```

To **run** it:
```
qemu-system-i386   (or qemu-system-x86_64)
```

---

## Build

```bash
make
```

Outputs `claudeos.img` — a raw disk image.

---

## Run in QEMU

```bash
make run
# or:
qemu-system-i386 -drive format=raw,file=claudeos.img
```

QEMU flags you might find useful:
```bash
# Show VGA output in a window
qemu-system-i386 -drive format=raw,file=claudeos.img

# No display, debug via serial (if you add a serial driver later)
qemu-system-i386 -drive format=raw,file=claudeos.img -nographic -serial mon:stdio

# Full debug: pause at startup, attach GDB
qemu-system-i386 -drive format=raw,file=claudeos.img -s -S
# then: gdb → target remote :1234 → break *0x10000 → continue
```

---

## Write to real hardware (USB / SD card)

**Warning: this will erase the target device.**

```bash
# Find your USB drive
lsblk

# Write (replace /dev/sdX)
sudo dd if=claudeos.img of=/dev/sdX bs=512 conv=fsync status=progress
sudo sync
```

Boot your machine from that USB. In BIOS/UEFI, enable **Legacy/CSM boot**, disable Secure Boot.

---

## Project structure

```
claudeos/
├── boot/
│   ├── boot.S          Stage-1 bootloader (GNU AS, AT&T syntax)
│   └── boot.ld         Bootloader linker script (→ flat 512-byte binary)
├── kernel/
│   ├── kernel_entry.S  Sets stack, calls kmain()
│   ├── kmain.c         Shell loop, command table
│   ├── vga.c / .h      VGA text-mode driver (direct 0xB8000 writes)
│   └── keyboard.c / .h PS/2 keyboard driver (port 0x60 scancodes)
├── libc/
│   └── klib.c / .h     Freestanding string, printf, memory, conversion
├── utils/
│   └── commands.c / .h All 11 built-in utility programs
├── linker.ld           Kernel linker script (→ flat binary at 0x10000)
├── Makefile
└── README.md
```

---

## What's next (roadmap)

These are the natural next steps for a beginner OS project:

1. **Interrupt Descriptor Table (IDT)** — real interrupt handling instead of polling
2. **Programmable Interval Timer (PIT)** — proper tick-based timekeeping
3. **FAT12 filesystem** — read files from disk
4. **Paging** — virtual memory with 4 KB pages
5. **User mode (Ring 3)** — run untrusted code safely
6. **ELF loader** — load programs from disk into memory
7. **System calls** — user programs talk to the kernel via `int 0x80`
8. **Multitasking** — context switching between processes

---

## Concepts learned

Building this OS teaches you:

- How the BIOS hands control to your bootloader (the 0xAA55 magic)
- Real mode vs protected mode and why the switch matters
- The Global Descriptor Table (GDT) and memory segmentation
- How VGA text mode works (memory-mapped I/O at 0xB8000)
- How PS/2 keyboard scancodes become characters
- How to write C without any standard library (`-ffreestanding`)
- Linker scripts and why object file order matters
- Port I/O (`in`/`out` instructions) for talking to hardware

---

*Built from scratch with just a compiler, an assembler, and a linker.*
