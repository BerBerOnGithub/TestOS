#!/usr/bin/env python3
"""Send screendump command to QEMU monitor and convert PPM to BMP-
import socket, time, sys, struct, os

MONITOR_HOST = '127.0.0.1'
MONITOR_PORT = 55555
OUT_PPM = r'D:\Program Files\qemu\screen.ppm'
OUT_BMP = r'D:\Program Files\qemu\screen.bmp'

def qemu_screendump():
    s = socket.socket()
    s.connect((MONITOR_HOST, MONITOR_PORT))
    time.sleep(0.3)
    s.recv(4096)  # banner
    cmd = f'screendump {OUT_PPM}\n'
    s.send(cmd.encode())
    time.sleep(0.5)
    s.recv(4096)
    s.close()
    print(f"Screendump saved to {OUT_PPM}")

def ppm_to_bmp(ppm_path, bmp_path):
    with open(ppm_path, 'rb') as f:
        # Parse PPM header
        assert f.readline().strip() == b'P6'
        dims = f.readline().split()
        w, h = int(dims[0]), int(dims[1])
        maxval = int(f.readline().strip())
        rgb_data = f.read()  # w*h*3 bytes, top-to-bottom

    print(f"PPM: {w}x{h}, maxval={maxval}")

    # Build 8bpp BMP with quantized palette... 
    # Actually just save as 24bpp BMP (no palette needed)
    row_size = w * 3
    # BMP rows must be multiple of 4 bytes
    pad = (4 - (row_size % 4)) % 4
    bmp_row = row_size + pad
    pixel_data_size = bmp_row * h
    file_size = 54 + pixel_data_size

    with open(bmp_path, 'wb') as f:
        # File header
        f.write(b'BM')
        f.write(struct.pack('<I', file_size))
        f.write(struct.pack('<HH', 0, 0))
        f.write(struct.pack('<I', 54))
        # Info header
        f.write(struct.pack('<I', 40))
        f.write(struct.pack('<ii', w, -h))  # negative height = top-down
        f.write(struct.pack('<HH', 1, 24))
        f.write(struct.pack('<I', 0))  # no compression
        f.write(struct.pack('<I', pixel_data_size))
        f.write(struct.pack('<ii', 2835, 2835))
        f.write(struct.pack('<II', 0, 0))
        # Pixel data: PPM is RGB top-to-bottom, BMP needs BGR
        for y in range(h):
            row_start = y * w * 3
            row = rgb_data[row_start:row_start + w*3]
            for x in range(w):
                r, g, b = row[x*3], row[x*3+1], row[x*3+2]
                f.write(bytes([b, g, r]))
            f.write(b'\x00' * pad)

    print(f"BMP saved to {bmp_path}")

if __name__ == '__main__':
    qemu_screendump()
    time.sleep(0.5)
    if os.path.exists(OUT_PPM):
        ppm_to_bmp(OUT_PPM, OUT_BMP)
        print("Done! Open", OUT_BMP)
    else:
        print("ERROR: PPM not created")
