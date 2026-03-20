import struct
from PIL import Image

path = r'scr0001.jpeg'
with open(path, 'rb') as f:
    data = f.read()

offset = struct.unpack_from('<I', data, 10)[0]
w = struct.unpack_from('<i', data, 18)[0]
h_val = struct.unpack_from('<i', data, 22)[0]
bpp = struct.unpack_from('<H', data, 28)[0]
abs_h = abs(h_val)

# Read palette (256 entries, BGRA)
palette_off = 54
palette = []
for i in range(256):
    b = data[palette_off + i*4]
    g = data[palette_off + i*4 + 1]
    r = data[palette_off + i*4 + 2]
    palette.append((r, g, b))

pixels = data[offset:]
img = Image.new('RGB', (w, abs_h))

for y in range(abs_h):
    for x in range(w):
        if h_val > 0:
            # bottom-up: BMP row 0 = image bottom
            idx = pixels[(abs_h - 1 - y) * w + x]
        else:
            idx = pixels[y * w + x]
        img.putpixel((x, y), palette[idx])

out = r'scr0001_converted.png'
img.save(out)
print(f'Saved {out} ({w}x{abs_h})')
