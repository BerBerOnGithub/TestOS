# ===========================================================================
# Makefile - ClaudeOS Build System (ISO edition)
# ===========================================================================

ASM      := nasm
ASMFLAGS := -f bin

BOOT_BIN   := build/boot.bin
STAGE2_BIN := build/stage2.bin
KERNEL_BIN := build/kernel.bin
FS_BIN     := build/fs.bin
FLAT_IMG   := build/claudeos_flat.img
ISO        := claudeos.iso

# Sector layout - matches build.bat exactly
KERNEL_START_SECTOR := 4
FS_START_SECTOR     := 804
FS_SECTORS          := 1600
FLAT_SECTORS        := $(shell echo $$(($(FS_START_SECTOR) + $(FS_SECTORS))))

DATA_IMG := data.img

.PHONY: all run clean

all: $(ISO) $(DATA_IMG)

$(DATA_IMG):
	python3 mkdata.py

$(BOOT_BIN): boot.asm | build
	$(ASM) $(ASMFLAGS) -o $@ $<
	@SIZE=$$(wc -c < $@); \
	if [ $$SIZE -ne 512 ]; then echo "ERROR: boot.bin must be 512 bytes"; exit 1; fi
	@echo "[OK] boot.bin (512 bytes)"

$(STAGE2_BIN): stage2.asm | build
	$(ASM) $(ASMFLAGS) -o $@ $<
	@SIZE=$$(wc -c < $@); \
	if [ $$SIZE -gt 1536 ]; then echo "ERROR: stage2.bin exceeds 1536 bytes - will overwrite kernel LBA 4!"; exit 1; fi
	@echo "[OK] stage2.bin ($$(wc -c < $@) bytes)"

$(KERNEL_BIN): kernel.asm | build
	$(ASM) $(ASMFLAGS) -o $@ $<
	@echo "[OK] kernel.bin ($$(wc -c < $@) bytes)"

$(FS_BIN): $(wildcard apps/*) | build
	python3 mkfs.py

# Build flat binary image using Python to match build.bat exactly
$(FLAT_IMG): $(BOOT_BIN) $(STAGE2_BIN) $(KERNEL_BIN) $(FS_BIN)
	python3 -c "\
import sys; \
flat_bytes = $(FLAT_SECTORS) * 512; \
kern_offset = $(KERNEL_START_SECTOR) * 512; \
fs_offset = $(FS_START_SECTOR) * 512; \
flat = bytearray(flat_bytes); \
boot   = open('$(BOOT_BIN)',   'rb').read(); \
stage2 = open('$(STAGE2_BIN)', 'rb').read(); \
kern   = open('$(KERNEL_BIN)', 'rb').read(); \
fs     = open('$(FS_BIN)',     'rb').read(); \
flat[0:len(boot)]                         = boot; \
flat[512:512+len(stage2)]                 = stage2; \
flat[kern_offset:kern_offset+len(kern)]   = kern; \
flat[fs_offset:fs_offset+len(fs)]         = fs; \
open('$(FLAT_IMG)', 'wb').write(flat); \
print('[OK] claudeos_flat.img (' + str(flat_bytes) + ' bytes)'); \
"

# Wrap the flat image in an ISO using El Torito no-emulation boot
$(ISO): $(FLAT_IMG)
	xorriso -as mkisofs \
	    -o $(ISO) \
	    -b claudeos_flat.img \
	    -no-emul-boot \
	    -boot-load-size all \
	    build/
	@echo "$(ISO) built!"

build:
	mkdir -p build

run: $(ISO) $(DATA_IMG)
	qemu-system-x86_64 \
	    -cdrom $(ISO) \
	    -drive format=raw,file=$(DATA_IMG),if=ide,index=3 \
	    -boot d \
	    -m 64M -display sdl -no-reboot \
	    -cpu qemu64 \
	    -smp 1 \
	    -vga std \
	    -rtc base=localtime \
	    -nic user,model=e1000 \
	    -name "ClaudeOS" \
	    -no-reboot

clean:
	rm -rf build $(ISO)