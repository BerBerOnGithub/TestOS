# ===========================================================================
# Makefile - ClaudeOS Build System
# ===========================================================================

ASM      := nasm
ASMFLAGS := -f bin

BOOT_BIN   := build/boot.bin
STAGE2_BIN := build/stage2.bin
KERNEL_BIN := build/kernel.bin
FS_BIN     := build/fs.bin
DISK_IMG   := claudeos.img

IMG_SECTORS := 2880

KERNEL_SECTORS := 200
FS_START_SECTOR := $(shell echo $$((3 + $(KERNEL_SECTORS))))

.PHONY: all run clean

all: $(DISK_IMG)

$(BOOT_BIN): boot.asm | build
	$(ASM) $(ASMFLAGS) -o $@ $<
	@SIZE=$$(wc -c < $@); \
	if [ $$SIZE -ne 512 ]; then echo "ERROR: boot.bin must be 512 bytes"; exit 1; fi
	@echo "[OK] boot.bin (512 bytes)"

$(STAGE2_BIN): stage2.asm | build
	$(ASM) $(ASMFLAGS) -o $@ $<
	@echo "[OK] stage2.bin ($$(wc -c < $@) bytes)"

$(KERNEL_BIN): kernel.asm | build
	$(ASM) $(ASMFLAGS) -o $@ $<
	@echo "[OK] kernel.bin ($$(wc -c < $@) bytes)"

$(FS_BIN): $(wildcard apps/*.bin) | build
	python3 mkfs.py

$(DISK_IMG): $(BOOT_BIN) $(STAGE2_BIN) $(KERNEL_BIN) $(FS_BIN)
	dd if=/dev/zero      of=$@ bs=512 count=$(IMG_SECTORS)    2>/dev/null
	dd if=$(BOOT_BIN)    of=$@ bs=512 count=1  conv=notrunc   2>/dev/null
	dd if=$(STAGE2_BIN)  of=$@ bs=512 seek=1   conv=notrunc   2>/dev/null
	dd if=$(KERNEL_BIN)  of=$@ bs=512 seek=3   conv=notrunc   2>/dev/null
	dd if=$(FS_BIN)      of=$@ bs=512 seek=$(FS_START_SECTOR) conv=notrunc 2>/dev/null
	@echo "claudeos.img built!"

build:
	mkdir -p build

run: $(DISK_IMG)
	qemu-system-x86_64 \
	    -drive file=$(DISK_IMG),format=raw,if=floppy \
	    -m 32M -display sdl -no-reboot \
	    -nic user,model=e1000

clean:
	rm -rf build $(DISK_IMG)