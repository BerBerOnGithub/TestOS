# ===========================================================================
# Makefile - ClaudeOS Build System
#
# Requirements:
#   nasm          - Netwide Assembler  (apt install nasm)
#   qemu-system-x86_64  - for 'make run'  (apt install qemu-system-x86)
#   dd, truncate  - standard Unix tools (pre-installed on Linux/macOS)
#
# Usage:
#   make          - build claudeos.img
#   make run      - build and launch in QEMU
#   make clean    - remove build artifacts
# ===========================================================================

ASM     := nasm
ASMFLAGS := -f bin

BOOT_SRC  := boot.asm
KERNEL_SRC := kernel.asm

BOOT_BIN  := build/boot.bin
KERNEL_BIN := build/kernel.bin
DISK_IMG  := claudeos.img

# Disk image: 1.44 MB floppy (2880 × 512-byte sectors)
IMG_SECTORS := 2880
IMG_SIZE    := $(shell expr $(IMG_SECTORS) \* 512)

.PHONY: all run clean

all: $(DISK_IMG)

# --- Build bootloader (must fit in 512 bytes) ---
$(BOOT_BIN): $(BOOT_SRC) | build
	$(ASM) $(ASMFLAGS) -o $@ $<
	@SIZE=$$(wc -c < $@); \
	if [ $$SIZE -ne 512 ]; then \
		echo "ERROR: boot.bin is $$SIZE bytes (must be exactly 512)"; exit 1; \
	fi
	@echo "[OK] boot.bin  (512 bytes)"

# --- Build kernel ---
$(KERNEL_BIN): $(KERNEL_SRC) | build
	$(ASM) $(ASMFLAGS) -o $@ $<
	@SIZE=$$(wc -c < $@); \
	echo "[OK] kernel.bin  ($$SIZE bytes)"

# --- Assemble disk image ---
$(DISK_IMG): $(BOOT_BIN) $(KERNEL_BIN)
	# Create blank floppy image
	dd if=/dev/zero of=$@ bs=512 count=$(IMG_SECTORS) 2>/dev/null
	# Write bootloader to sector 1 (MBR)
	dd if=$(BOOT_BIN) of=$@ bs=512 count=1 conv=notrunc 2>/dev/null
	# Write kernel starting at sector 2
	dd if=$(KERNEL_BIN) of=$@ bs=512 seek=1 conv=notrunc 2>/dev/null
	@echo ""
	@echo "=================================================="
	@echo "  claudeos.img built successfully!"
	@echo "  Run in QEMU:    make run"
	@echo "  Write to USB:   see README.md"
	@echo "=================================================="

build:
	mkdir -p build

# --- Run in QEMU (floppy mode) ---
run: $(DISK_IMG)
	qemu-system-x86_64 \
	    -drive file=$(DISK_IMG),format=raw,if=floppy \
	    -m 4M \
	    -display sdl \
	    -no-reboot \
	    -nic user,model=e1000

# --- Same but headless / serial output (useful for debugging) ---
run-nographic: $(DISK_IMG)
	qemu-system-x86_64 \
	    -drive file=$(DISK_IMG),format=raw,if=floppy \
	    -m 4M \
	    -nographic \
	    -nic user,model=e1000

clean:
	rm -rf build $(DISK_IMG)
	@echo "Cleaned."