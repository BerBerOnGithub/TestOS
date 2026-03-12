# ClaudeOS v2.0 — Build Guide

A real bootable x86 operating system written in pure assembly. Runs directly
on the CPU — no OS, no runtime, no libraries. Real-mode shell with full BIOS
access, plus a 32-bit protected-mode graphical desktop with a window manager,
mouse support, and direct hardware drivers.

---

## Requirements

| Tool   | Get it from                                              |
|--------|----------------------------------------------------------|
| NASM   | https://nasm.us/pub/nasm/releasebuilds/?C=M&O=D         |
| Python | https://www.python.org/downloads/                        |
| QEMU   | https://www.qemu.org/download/#windows                   |

**First-time Python setup** (one time only):
```
pip install pycdlib
```

---

## Step 1 — Build

```
build.bat
```

Produces `claudeos.iso`.

```
build.bat run
```

Builds and launches in QEMU immediately.

---

## Step 2 — Run in QEMU

### Quick launch
```
build.bat run
```

### Full command (copy this into a shortcut or script)
```
qemu-system-x86_64 ^
  -cdrom claudeos.iso ^
  -boot d ^
  -m 64M ^
  -cpu Haswell ^
  -smp 1 ^
  -vga std ^
  -rtc base=localtime ^
  -audiodev id=snd,driver=dsound ^
  -machine pcspk-audiodev=snd ^
  -nic user,model=e1000 ^
  -display sdl,window-close=on ^
  -name "ClaudeOS" ^
  -no-reboot
```

| Flag                            | Why                                               |
|---------------------------------|---------------------------------------------------|
| `-cdrom claudeos.iso -boot d`   | Boot from ISO                                     |
| `-m 64M`                        | Enough RAM for framebuffer + wallpaper            |
| `-cpu Haswell`                  | Spoofs a real Intel Haswell CPU via CPUID         |
| `-smp 1`                        | Single core (ClaudeOS is single-threaded)         |
| `-vga std`                      | Standard VGA — required for VBE 640×480 graphics  |
| `-rtc base=localtime`           | RTC clock shows your real local time              |
| `-audiodev` + `-machine pcspk` | PC speaker audio (beep commands, boot sounds)     |
| `-nic user,model=e1000`         | Intel e1000 NIC for networking commands           |
| `-display sdl,window-close=on` | SDL window with working close button              |
| `-name "ClaudeOS"`              | Sets the QEMU window title                        |
| `-no-reboot`                    | Halts instead of rebooting on triple fault        |

> **Linux/macOS audio:** replace `-audiodev id=snd,driver=dsound` with
> `-audiodev id=snd,driver=pa` (PulseAudio) or `driver=alsa`.

### With packet capture (network debugging)
```
qemu-system-x86_64 ^
  -cdrom claudeos.iso -boot d ^
  -m 64M -cpu Haswell -smp 1 -vga std ^
  -rtc base=localtime ^
  -audiodev id=snd,driver=dsound ^
  -machine pcspk-audiodev=snd ^
  -netdev user,id=n0 ^
  -device e1000,netdev=n0 ^
  -object filter-dump,id=f0,netdev=n0,file=net.pcap ^
  -display sdl,window-close=on ^
  -name "ClaudeOS" ^
  -no-reboot ^
  -d guest_errors,unimp ^
  -D qemu.log
```

Produces `net.pcap` (open in Wireshark) and `qemu.log` (QEMU error log).

---

## Step 3 — Flash to USB (optional)

> WARNING: This erases the entire USB drive.

**Rufus:** Select `claudeos.iso`, mode will auto-select DD — click START.

**balenaEtcher:** Flash from file → select `claudeos.iso` → Flash.

**Boot:** Enable Legacy/CSM mode in BIOS, select USB as boot device.

---

## Real-Mode Shell Commands

| Command              | What it does                              |
|----------------------|-------------------------------------------|
| `help`               | Show all commands                         |
| `echo <text>`        | Print text                                |
| `clear`              | Clear the screen                          |
| `color [XX]`         | Set shell colour (e.g. `color 5F`)        |
| `calc <n> <op> <n>`  | Calculator (`+` `-` `*` `/`)             |
| `beep`               | Sound the PC speaker                      |
| `fortune`            | Random quote                              |
| `guess`              | Number guessing game (1–100)              |
| `colors`             | Show all 16 colour swatches               |
| `ascii`              | ASCII table (32–126)                      |
| `sys`                | System snapshot (date/time/uptime/memory) |
| `date`               | Show RTC date                             |
| `time`               | Show RTC time                             |
| `setdate`            | Set RTC date                              |
| `settime`            | Set RTC time                              |
| `probe`              | Verify real mode                          |
| `drivers`            | Show loaded real-mode drivers             |
| `reboot`             | Reboot the machine                        |
| `halt`               | Halt the CPU                              |
| `pm`                 | Switch to 32-bit protected mode + desktop |

---

## Protected-Mode Desktop

Type `pm` in the real-mode shell to enter the graphical desktop.

- **Mouse** — PS/2 mouse, full cursor support
- **Terminal** — type commands in the terminal window
- **Icons** — click Terminal / Clock / Files on the left sidebar
- **Windows** — drag title bars to move, click ✕ to close
- **Taskbar** — click buttons to switch between open windows

### Terminal Commands (PM)

| Command              | What it does                              |
|----------------------|-------------------------------------------|
| `help`               | Show all PM commands                      |
| `ver`                | Version info                              |
| `clear`              | Clear screen                              |
| `echo <text>`        | Print text                                |
| `calc <n> <op> <n>`  | 32-bit signed calculator                  |
| `probe`              | Confirm 32-bit protected mode             |
| `drivers`            | Show loaded PM drivers                    |
| `pci`                | Enumerate all PCI devices                 |
| `ifconfig`           | Show NIC MAC address and link status      |
| `arp`                | Show ARP cache                            |
| `arping <ip>`        | Send ARP request                          |
| `ping <ip>`          | Send ICMP echo                            |
| `clock`              | Open clock window                         |
| `files`              | Open file browser                         |
| `exit`               | Return to real-mode shell                 |

---

## Wallpaper

Drop a file named `wallpaper.bmp` into the `apps/` folder before building.

**Requirements:**
- Format: BMP, 8-bit indexed (256 colour)
- Size: exactly 640×480 pixels
- Palette: standard 256-colour VGA palette

Any image editor works — GIMP, Photoshop, Paint.NET. Export as
"256 colour BMP" or "8-bit indexed BMP".

---

## Driver Architecture

**Real-mode drivers:**

| Driver   | Interface         | Notes                        |
|----------|-------------------|------------------------------|
| Screen   | BIOS INT 10h      | VGA text mode 3 (80×25)      |
| Keyboard | BIOS INT 16h      | Buffered input               |
| RTC      | BIOS INT 1Ah      | Date/time read and write     |
| Speaker  | PIT ch.2 + 0x61   | Beep                         |

**Protected-mode drivers:**

| Driver   | Interface         | Notes                        |
|----------|-------------------|------------------------------|
| VBE GFX  | VESA BIOS + MMIO  | 640×480 8bpp framebuffer     |
| Mouse    | PS/2 port 0x60    | 3-button, BMP cursor         |
| Keyboard | Direct 0x60/0x64  | Scan-code translation        |
| PIT      | 0x40–0x43         | 100 Hz tick, ms delay        |
| Speaker  | PIT ch.2 + 0x61   | Beep (no BIOS)               |
| PCI bus  | 0xCF8/0xCFC       | Full bus scan, e1000 detect  |
| e1000    | MMIO via BAR0     | TX/RX rings, MAC from EEPROM |

---

## Network Stack

| Layer     | Status      |
|-----------|-------------|
| PCI       | ✅ Done     |
| e1000 NIC | ✅ Done     |
| Ethernet  | ✅ Done     |
| ARP       | ✅ Done     |
| IP        | ✅ Done     |
| ICMP/ping | ✅ Done     |
| UDP       | 🔜 Planned  |

---

## Project Structure

```
claudeos/
├── build.bat                   Windows build + run script
├── Makefile                    Linux/macOS build script
├── mkfs.py                     Filesystem packer
├── mkiso.py                    Pure Python ISO builder
├── README.md                   This file
├── boot.asm                    512-byte MBR bootloader
├── stage2.asm                  Stage 2 loader (LBA, El Torito)
├── kernel.asm                  Kernel entry point + includes
│
├── apps/                       Files packed into ClaudeFS
│   ├── cursor.bmp              Mouse cursor sprite
│   ├── icon_term.bmp           Terminal desktop icon
│   ├── icon_clock.bmp          Clock desktop icon
│   ├── icon_files.bmp          Files desktop icon
│   └── wallpaper.bmp           Desktop wallpaper (optional)
│
├── core/                       Real-mode hardware abstractions
├── drivers/                    Real-mode driver registry
├── shell/                      Real-mode shell
├── commands/                   Real-mode commands
│
└── pm/                         32-bit protected mode
    ├── pm_shell.asm            PM entry, main loop
    ├── wm.asm                  Window manager
    ├── icons.asm               Desktop icons
    ├── terminal.asm            Terminal emulator
    ├── mouse.asm               PS/2 mouse + cursor
    ├── gfx.asm                 Framebuffer primitives
    ├── font.asm                8×8 bitmap font renderer
    └── net/                    Network stack
```

---

## How It Works

The BIOS loads `boot.asm` (512 bytes) at `0x7C00`. It loads `stage2.asm`
which uses INT 13h AH=0x42 (LBA extended read) to load the kernel and
ClaudeFS filesystem into memory.

The kernel initialises real-mode drivers and enters a command shell using
BIOS interrupts for all I/O.

Typing `pm` switches to 32-bit protected mode: GDT loaded, `CR0.PE=1`,
far jump to `pm_entry`. VBE graphics are set up (640×480 8bpp), PS/2 mouse
initialised, and the graphical desktop starts.

Typing `exit` in the PM terminal reverses everything back to real mode.

No C. No libraries. No OS. Just x86 assembly and direct hardware.