# ClaudeOS v2.0 — Build Guide

A real bootable x86 operating system written in pure assembly. Runs directly
on the CPU — no OS, no runtime, no libraries. Real-mode shell with full BIOS
access, plus a 32-bit protected-mode shell with direct hardware drivers and
a working TCP/IP network stack (in progress).

---

## Step 1 — Install NASM

1. Go to: https://nasm.us/pub/nasm/releasebuilds/?C=M&O=D
2. Click the top folder (highest version number)
3. Download `nasm-X.XX.XX-installer-x64.exe`
4. Run the installer — tick **"Add to PATH"**

Verify:
```
nasm --version
```

---

## Step 2 — Build

```
build.bat
```

Produces `claudeos.img` — a 1.44 MB bootable floppy image.

---

## Step 3 — Run in QEMU

### Basic (no networking)
```
build.bat run
```

### With networking (required for `pci`, `ifconfig`, `ping`)
```
qemu-system-x86_64 ^
  -drive file=claudeos.img,format=raw,if=floppy ^
  -m 32M ^
  -nic user,model=e1000 ^
  -display sdl ^
  -no-reboot
```

### With networking + packet capture (for debugging)
```
qemu-system-x86_64 ^
  -drive file=claudeos.img,format=raw,if=floppy ^
  -m 32M ^
  -netdev user,id=n0 ^
  -device e1000,netdev=n0 ^
  -object filter-dump,id=f0,netdev=n0,file=net.pcap ^
  -display sdl ^
  -no-reboot ^
  -d guest_errors,unimp ^
  -D qemu.log
```

Produces `net.pcap` (open in Wireshark) and `qemu.log` (QEMU error log).

Or add it to `build.bat run` permanently by editing the `qemu-system-x86_64`
line at the bottom of `build.bat` to match the above.

> **Why `-m 32M`?**  The network stack uses memory above 1MB for TX/RX
> descriptor rings and packet buffers. The default `-m 4M` is not enough.

> **Why `model=e1000`?**  ClaudeOS implements an Intel 82540EM driver.
> QEMU's default NIC model must match — `e1000` is the right one.

---

## Step 4 — Flash to USB (optional)

> WARNING: This erases the entire USB drive.

**Rufus:** Select `claudeos.img`, choose **"DD Image mode"**, click START.

**balenaEtcher:** Flash from file → select `claudeos.img` → Flash.

**Boot:** Enable Legacy/CSM mode in BIOS, select USB as boot device.

---

## Real-Mode Shell Commands

| Command              | What it does                              |
|----------------------|-------------------------------------------|
| `help`               | Show all commands (2 pages)               |
| `hello`              | Hello World program                       |
| `run hello.com`      | Same                                      |
| `echo <text>`        | Print text                                |
| `clear`              | Clear the screen                          |
| `color [XX]`         | Set shell colour (e.g. `color 5F`)        |
| `calc <n> <op> <n>`  | Calculator (`+` `-` `*` `/`)             |
| `beep`               | Sound the PC speaker                      |
| `fortune`            | Random quote                              |
| `guess`              | Number guessing game (1–100)              |
| `colors`             | Show all 16 cölöpűre swatches               |
| `ascii`              | ASCII table (32–126)                      |
| `sys`                | System snapshot (date/time/uptime/memory) |
| `date`               | Show RTC date                             |
| `time`               | Show RTC time                             |
| `setdate`            | Set RTC date                              |
| `settime`            | Set RTC time                              |
| `probe`              | Verify you are in real mode               |
| `drivers`            | Show loaded real-mode drivers             |
| `reboot`             | Reboot the machine                        |
| `halt`               | Halt the CPU                              |
| `pm`                 | Switch to 32-bit protected mode           |

---

## Protected-Mode Shell Commands

Type `pm` in the real-mode shell (confirm with `Y`) to enter protected mode.
Type `exit` to return to the real-mode shell.

| Command              | What it does                              |
|----------------------|-------------------------------------------|
| `help`               | Show all PM commands                      |
| `ver`                | Version info                              |
| `clear`              | Clear screen                              |
| `echo <text>`        | Print text                                |
| `calc <n> <op> <n>`  | 32-bit signed calculator                  |
| `probe`              | Write/read above 1MB to confirm 32-bit PM |
| `drivers`            | Show loaded PM drivers                    |
| `pci`                | Enumerate all PCI devices                 |
| `ifconfig`           | Show NIC MAC address and link status      |
| `exit`               | Return to real-mode shell                 |

---

## Driver Architecture

ClaudeOS separates drivers by mode. On mode switch, the outgoing drivers
are shut down and the incoming drivers are initialised.

**Real-mode drivers** (`drivers/rm_drivers.asm`):

| Driver   | Interface         | Notes                        |
|----------|-------------------|------------------------------|
| Screen   | BIOS INT 10h      | VGA text mode 3 (80×25)      |
| Keyboard | BIOS INT 16h      | Buffered input                |
| RTC      | BIOS INT 1Ah      | Date/time read and write      |
| Speaker  | PIT ch.2 + 0x61   | Beep                         |

**Protected-mode drivers** (`pm/pm_drivers.asm`):

| Driver   | Interface         | Notes                        |
|----------|-------------------|------------------------------|
| Screen   | Direct 0xB8000    | CRT controller cursor        |
| Keyboard | Direct 0x60/0x64  | Scan-code translation        |
| PIT      | 0x40–0x43         | 100 Hz tick, ms delay        |
| Speaker  | PIT ch.2 + 0x61   | Beep (no BIOS)               |
| PCI bus  | 0xCF8/0xCFC       | Full bus scan, e1000 detect  |
| e1000    | MMIO via BAR0     | TX/RX rings, MAC from EEPROM |

---

## Network Stack Progress

| Layer     | File                  | Status      |
|-----------|-----------------------|-------------|
| PCI       | `pm/net/pci.asm`      | ✅ Done     |
| e1000 NIC | `pm/net/e1000.asm`    | ✅ Done     |
| Ethernet  | `pm/net/eth.asm`      | ✅ Done     |
| ARP       | `pm/net/arp.asm`      | ✅ Done     |
| IP        | `pm/net/ip.asm`       | ✅ Done     |
| ICMP/ping | `pm/net/icmp.asm`     | ✅ Done     |
| UDP       | `pm/net/udp.asm`      | 🔜 Planned  |

---

## Project Structure

```
claudeos/
├── build.bat                   Windows build + run script
├── Makefile                    Linux/macOS alternative
├── README.md                   This file
├── boot.asm                    512-byte MBR bootloader
├── kernel.asm                  Kernel entry point + includes
│
├── core/                       Real-mode hardware abstractions
│   ├── screen.asm              BIOS VGA output, putc_color, scroll
│   ├── keyboard.asm            BIOS keyboard input, readline
│   ├── string.asm              Print int/hex/BCD, strcmp, startswith
│   └── utils.asm               Parse int/hex, divmod32, rand
│
├── drivers/
│   └── rm_drivers.asm          Real-mode driver registry + cmd_drivers
│
├── shell/
│   └── shell.asm               Prompt, readline dispatcher
│
├── commands/
│   ├── cmd_basic.asm           help, clear, echo, hello, reboot, halt
│   ├── cmd_system.asm          date, time, sys, setdate, settime, pm
│   ├── cmd_tools.asm           calc, color, beep
│   ├── cmd_fun.asm             fortune, guess, ascii, colors
│   └── data.asm                All strings, variables, GDT
│
└── pm/                         32-bit protected mode
    ├── pm_shell.asm            PM entry point, shell loop, dispatcher
    ├── pm_screen.asm           Direct VGA driver
    ├── pm_keyboard.asm         Direct PS/2 driver
    ├── pm_string.asm           32-bit string/number utilities
    ├── pm_commands.asm         PM shell commands
    ├── pm_drivers.asm          PM driver registry
    ├── pm_data.asm             PM strings and variables
    └── net/
        ├── pci.asm             PCI bus enumerator (0xCF8/0xCFC)
        └── e1000.asm           Intel 82540EM NIC driver
```

---

## How It Works

The BIOS loads the MBR (`boot.asm`) at `0x7C00`. The bootloader reads 40
sectors (20 KB) of kernel from disk into `0x8000` using INT 13h, then jumps
there.

The kernel initialises real-mode drivers, draws the banner, and enters a
read-eval-print loop using BIOS interrupts for all I/O.

Typing `pm` shuts down the BIOS drivers, loads the GDT, sets `CR0.PE=1`,
and far-jumps to `pm_entry` at selector `0x08`. The PM shell then
initialises its own drivers — including PCI enumeration and the e1000 NIC —
and runs its own command loop using direct hardware access only.

Typing `exit` in PM reverses the process: PM drivers shut down, `CR0.PE` is
cleared, the real-mode IDT is restored, and control returns to the 16-bit
shell loop.

No C. No libraries. No OS. Just x86 assembly, direct hardware, and the GDT.