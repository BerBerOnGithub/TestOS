CC      := gcc
AS      := as
LD      := ld

CFLAGS  := -m32 -std=c11 -ffreestanding -fno-pie -fno-stack-protector -fno-builtin -fno-pic -O2 -Wall -Wextra -I. -Ikernel -Ilibc -Iutils -Wno-unused-parameter
ASFLAGS := --32
LDFLAGS := -m elf_i386 -T linker.ld --oformat binary

C_SRCS   := kernel/vga.c kernel/keyboard.c kernel/timer.c kernel/gfx.c kernel/mouse.c kernel/gui.c kernel/kmain.c libc/klib.c utils/commands.c utils/apps.c
ASM_SRCS := kernel/kernel_entry.S kernel/timer_asm.S
C_OBJS   := $(patsubst %.c, build/%.o, $(C_SRCS))
ASM_OBJS := $(patsubst %.S, build/%.o, $(ASM_SRCS))
KERNEL_OBJS := $(ASM_OBJS) $(C_OBJS)

.PHONY: all run clean

all: claudeos.img
	@echo "  claudeos.img ready -- run: qemu-system-i386 -drive format=raw,file=claudeos.img"

build/kernel.bin: $(KERNEL_OBJS) linker.ld
	$(LD) $(LDFLAGS) -o $@ $(KERNEL_OBJS)

build/kernel_sectors.inc: build/kernel.bin
	python3 -c "import os; print((os.path.getsize('build/kernel.bin')+511)//512)" > $@

build/boot.o: boot/boot.S build/kernel_sectors.inc | build/boot
	$(AS) $(ASFLAGS) --defsym KERNEL_COUNT=$$(cat build/kernel_sectors.inc) boot/boot.S -o $@

build/boot.bin: build/boot.o boot/boot.ld
	$(LD) -m elf_i386 -T boot/boot.ld --oformat binary $< -o $@

claudeos.img: build/boot.bin build/kernel.bin
	cat build/boot.bin build/kernel.bin > build/raw.bin
	python3 pad_image.py build/raw.bin $@

build/kernel/%.o: kernel/%.S | build/kernel
	$(AS) $(ASFLAGS) $< -o $@

build/kernel/%.o: kernel/%.c | build/kernel
	$(CC) $(CFLAGS) -c $< -o $@

build/libc/%.o: libc/%.c | build/libc
	$(CC) $(CFLAGS) -c $< -o $@

build/utils/%.o: utils/%.c | build/utils
	$(CC) $(CFLAGS) -c $< -o $@

build/boot build/kernel build/libc build/utils:
	mkdir -p $@

run: claudeos.img
	qemu-system-i386 -drive format=raw,file=claudeos.img

clean:
	rm -rf build claudeos.img
