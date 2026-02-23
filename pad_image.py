#!/usr/bin/env python3
"""
pad_image.py  —  pads claudeos.img to a whole number of 512-byte sectors
Usage: python3 pad_image.py <input_raw> <output_img>
"""
import sys, math, os

inp, out = sys.argv[1], sys.argv[2]
raw = open(inp, 'rb').read()

# Pad to at least (kernel_sectors + 2) sectors so INT 13h never reads past EOF
sectors = math.ceil(len(raw) / 512) + 2
padded  = raw + b'\x00' * (sectors * 512 - len(raw))
open(out, 'wb').write(padded)

print(f"  boot+kernel: {len(raw)} bytes")
print(f"  padded to  : {len(padded)} bytes  ({sectors} sectors on disk)")
