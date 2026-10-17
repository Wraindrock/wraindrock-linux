#!/usr/bin/env python3
"""Print simple colour statistics for an 8-bit RGB/RGBA PNG.

Used by tests/vm-test.sh to tell the Anaconda installer screen apart from the
installed system's GNOME welcome/login screen. No third-party dependencies:
the frames QEMU writes are truecolour, non-interlaced, 8 bits per channel.
"""

import struct
import sys
import zlib


def load(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos = 8
    idat = b""
    width = height = depth = colour = interlace = None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if depth != 8 or colour not in (2, 6) or interlace != 0:
        raise SystemExit(f"{path}: unsupported PNG (depth={depth} colour={colour} interlace={interlace})")
    channels = 3 if colour == 2 else 4
    raw = zlib.decompress(idat)
    stride = width * channels
    pixels = bytearray(width * height * channels)
    prev = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        ftype = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
            elif ftype != 0:
                raise SystemExit(f"{path}: bad filter {ftype}")
        pixels[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, pixels


def thumbnail(path, size=32):
    width, height, channels, px = load(path)
    out = []
    for gy in range(size):
        y = gy * height // size
        for gx in range(size):
            x = gx * width // size
            o = (y * width + x) * channels
            out.append((px[o], px[o + 1], px[o + 2]))
    return out


def compare(path, ref_path):
    a = thumbnail(path)
    b = thumbnail(ref_path)
    diff = sum(abs(p - q) for p, q in zip(sum(a, ()), sum(b, ()))) / (len(a) * 3)
    print(f"{path} vs {ref_path}: mean abs diff {diff:.2f}")
    return diff


def stats(path):
    width, height, channels, px = load(path)
    n = width * height
    sr = sg = sb = bright = blue = 0
    step = max(1, n // 200000)  # sample at most ~200k pixels
    seen = 0
    for i in range(0, n, step):
        o = i * channels
        r, g, b = px[o], px[o + 1], px[o + 2]
        sr += r
        sg += g
        sb += b
        if (r + g + b) / 3 > 170:
            bright += 1
        if b > 40 and b > r + 15 and r < 70:
            blue += 1
        seen += 1
    print(f"{path} {width}x{height} mean={sr/seen:.1f},{sg/seen:.1f},{sb/seen:.1f} "
          f"bright={bright/seen:.3f} blue={blue/seen:.3f}")


if __name__ == "__main__":
    if len(sys.argv) == 2:
        stats(sys.argv[1])
    elif len(sys.argv) == 3:
        compare(sys.argv[1], sys.argv[2])
    else:
        raise SystemExit("usage: png-stats.py FRAME.png [REFERENCE.png]")
