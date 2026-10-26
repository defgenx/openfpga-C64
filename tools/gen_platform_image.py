#!/usr/bin/env python3
"""Generate the platform image dist/Platforms/_images/c64.bin (a C64 drawn in perspective).

    python3 tools/gen_platform_image.py [preview.png]

APF graphic format (Analogue docs, packaging-a-core, Graphical Asset Formats): 521x165,
16 bits per pixel with the brightness in the upper 8 bits (0xFF00 on, 0x0000 off),
stored rotated 90 degrees counter-clockwise. Words are big-endian, as in icon.bin.
The optional PNG is the image as the Pocket shows it, for checking.
"""
import struct
import sys
import zlib
from pathlib import Path

W, H = 521, 165
SS = 4  # supersampling per axis
OUT = Path(__file__).resolve().parent.parent / "dist/Platforms/_images/c64.bin"

# Body: u along the length (0 left, 1 right), v depth (0 front, 1 back), z height.
# The top slopes up from the front edge to the back, like the breadbin case.
X0, Y0 = 132.0, 152.0        # front-bottom-left corner
LX, LY = 316.0, -14.0        # length vector
DX, DY = 52.0, -78.0         # depth vector
ZF, ZB = 14.0, 30.0          # height at the front and back edges


def proj(u, v, z):
    return (X0 + u * LX + v * DX, Y0 + u * LY + v * DY - z)


def ztop(v):
    return ZF + (ZB - ZF) * v


def top(u, v):
    return proj(u, v, ztop(v))


class Canvas:
    def __init__(self):
        self.w, self.h = W * SS, H * SS
        self.px = bytearray(self.w * self.h)

    def poly(self, pts, level):
        pts = [(x * SS, y * SS) for x, y in pts]
        ys = [p[1] for p in pts]
        for y in range(max(0, int(min(ys))), min(self.h, int(max(ys)) + 1)):
            cy = y + 0.5
            xs = []
            for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
                if (y1 <= cy) != (y2 <= cy):
                    xs.append(x1 + (cy - y1) * (x2 - x1) / (y2 - y1))
            xs.sort()
            row = y * self.w
            for a, b in zip(xs[0::2], xs[1::2]):
                for x in range(max(0, int(a + 0.5)), min(self.w, int(b + 0.5))):
                    self.px[row + x] = level

    def quad_top(self, u0, v0, u1, v1, level):
        self.poly([top(u0, v0), top(u1, v0), top(u1, v1), top(u0, v1)], level)

    def downsample(self):
        out = bytearray(W * H)
        for y in range(H):
            for x in range(W):
                s = 0
                for sy in range(SS):
                    i = (y * SS + sy) * self.w + x * SS
                    s += sum(self.px[i:i + SS])
                out[y * W + x] = (s + SS * SS // 2) // (SS * SS)
        return out


def draw():
    c = Canvas()
    # Faces: front, right side, top.
    c.poly([proj(0, 0, 0), proj(1, 0, 0), proj(1, 0, ZF), proj(0, 0, ZF)], 150)
    c.poly([proj(1, 0, 0), proj(1, 1, 0), proj(1, 1, ZB), proj(1, 0, ZF)], 70)
    c.poly([top(0, 0), top(1, 0), top(1, 1), top(0, 1)], 105)
    # Lip along the front of the top face.
    c.quad_top(0, 0, 1, 0.05, 185)

    # Keyboard: rows of key counts with their left offset in key widths, front row first.
    ku0, ku1, kv0, kv1 = 0.075, 0.80, 0.14, 0.80
    rows = [(1.5, 1), (0.0, 18), (0.75, 17), (0.5, 17), (0.0, 17)]
    unit = (ku1 - ku0) / 18.5
    rv = (kv1 - kv0) / 5
    gap_u, gap_v = unit * 0.16, rv * 0.18
    for r, (off, n) in enumerate(rows):
        v0 = kv0 + r * rv
        if r == 0:  # space bar
            u = ku0 + 3.6 * unit
            c.quad_top(u, v0 + gap_v, u + 9 * unit - gap_u, v0 + rv - gap_v, 235)
            continue
        for k in range(n):
            u = ku0 + (off + k) * unit
            c.quad_top(u + gap_u, v0 + gap_v, u + unit - gap_u, v0 + rv - gap_v, 235)
    # Function keys: one column of four, right of the keyboard.
    fu = ku1 + 0.045
    for r in range(4):
        v0 = kv0 + (r + 0.5) * rv
        c.quad_top(fu, v0 + gap_v, fu + unit * 1.7, v0 + rv - gap_v, 235)

    # Badge with the rainbow stripes, back left.
    bu, bv = 0.08, 0.875
    c.quad_top(bu, bv, bu + 0.17, bv + 0.075, 40)
    for i, level in enumerate((255, 215, 175, 135, 95)):
        su = bu + 0.08 + i * 0.016
        c.quad_top(su, bv + 0.012, su + 0.012, bv + 0.063, level)
    # Power LED, front right.
    c.quad_top(0.93, 0.08, 0.95, 0.11, 255)
    return c.downsample()


def write_bin(img):
    words = bytearray()
    for r in range(W):  # stored row r = image column W-1-r (90 degrees counter-clockwise)
        x = W - 1 - r
        for y in range(H):
            words += struct.pack(">H", img[y * W + x] << 8)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(words)


def write_png(img, path):
    raw = b"".join(b"\0" + bytes(img[y * W:(y + 1) * W]) for y in range(H))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 0, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    img = draw()
    write_bin(img)
    if len(sys.argv) > 1:
        write_png(img, sys.argv[1])
