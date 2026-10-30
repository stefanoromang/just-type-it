# Builds AppIcon.ico (same design as the Mac icon) – Stefano Roman Gunness · MIT License
import struct, zlib, math, sys
def png(size):
    px = bytearray()
    for y in range(size):
        px.append(0)
        for x in range(size):
            inset = size*0.09; r = size*0.2
            cx = min(max(x+0.5, inset+r), size-inset-r); cy = min(max(y+0.5, inset+r), size-inset-r)
            inside = (x+0.5-cx)**2 + (y+0.5-cy)**2 <= r*r
            if not inside: px += b'\0\0\0\0'; continue
            t = (x + (size-y)) / (2*size)
            R = int(23 + (13-23)*t); G = int(184 + (120-184)*t); B = int(135 + (158-135)*t)
            u, v = (x+0.5)/size, (y+0.5)/size
            white = False
            for i, w in enumerate([0.53, 0.42, 0.27]):
                yy = 0.30 + 0.135*i
                if abs(v-yy) < 0.032 and 0.24 <= u <= 0.24+w: white = True
            def seg(ax, ay, bx, by, th=0.038):
                dx, dy = bx-ax, by-ay; tt = max(0, min(1, ((u-ax)*dx+(v-ay)*dy)/(dx*dx+dy*dy)))
                return math.hypot(u-(ax+tt*dx), v-(ay+tt*dy)) < th
            if seg(0.50, 0.66, 0.60, 0.75) or seg(0.60, 0.75, 0.80, 0.56): white = True
            px += bytes([255,255,255,255]) if white else bytes([R,G,B,255])
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t+d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(px), 9)) + chunk(b'IEND', b'')
sizes = [16, 24, 32, 48, 64, 128, 256]
imgs = [png(s) for s in sizes]
out = struct.pack('<HHH', 0, 1, len(sizes)); off = 6 + 16*len(sizes)
for s, d in zip(sizes, imgs):
    out += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(d), off); off += len(d)
open(sys.argv[1], 'wb').write(out + b''.join(imgs))
