#!/usr/bin/env python3
"""Reference models for the GCR tests: a port of Main_MiSTer's support/c64/c64.cpp.

  synth_track(data, track_h, id0, id1)   -> c64_synthesize_gcr_track()
  synth_g64(d64)                          -> c64_synthesize_g64_image() (the DDRAM image)
  decode_track(gcr, nsec)                 -> the D64 branch of c64_writeGCR(), but
                                             returning only the sectors it found
Also usable on its own:  gcr_ref.py in.d64 out.g64
"""
import sys

GCR = [0x0A, 0x0B, 0x12, 0x13, 0x0E, 0x0F, 0x16, 0x17, 0x09, 0x19, 0x1A, 0x1B, 0x0D, 0x1D, 0x1E, 0x15]
BIN = {c: n for n, c in enumerate(GCR)}

START = [0, 21, 42, 63, 84, 105, 126, 147, 168, 189, 210, 231, 252, 273, 294, 315, 336, 357, 376, 395, 414,
         433, 452, 471, 490, 508, 526, 544, 562, 580, 598, 615, 632, 649, 666, 683, 700, 717, 734, 751, 768,
         785, 802]


def nsec(tf):
    return START[tf + 1] - START[tf]


def tracks_of(size):
    return 35 if size <= 683 * 257 else 40 if size <= 768 * 257 else 42


def gcr_group(b4):
    v = 0
    for b in b4:
        v = (v << 10) | (GCR[b >> 4] << 5) | GCR[b & 15]
    return [(v >> s) & 0xFF for s in (32, 24, 16, 8, 0)]


def synth_track(data, track_h, id0, id1):
    out = []
    for sec in range(len(data) // 256):
        out += [0xFF] * 5
        out += gcr_group([0x08, sec ^ track_h ^ id0 ^ id1, sec, track_h])
        out += gcr_group([id1, id0, 0x0F, 0x0F])
        out += [0x55] * 9
        out += [0xFF] * 5
        blk = [0x07] + list(data[sec * 256:(sec + 1) * 256])
        cs = 0
        for b in blk[1:]:
            cs ^= b
        blk += [cs, 0, 0]
        for i in range(0, 260, 4):
            out += gcr_group(blk[i:i + 4])
        gap = 8 if track_h < 18 else 17 if track_h < 25 else 12 if track_h < 31 else 9
        out += [0x55] * gap
    return bytes(out)


def synth_g64(d64):
    tracks = tracks_of(len(d64))
    id0, id1 = d64[0x165A2], d64[0x165A3]
    img = bytearray(12 + 84 * 8)
    img[0:8] = b"GCR-1541"
    img[9] = 84
    off = 12 + 84 * 8
    for t in range(84):
        tf = t >> 1
        if t & 1 or tf >= tracks:
            continue
        g = synth_track(d64[START[tf] * 256:START[tf + 1] * 256], tf + 1, id0, id1)
        img[12 + t * 4:16 + t * 4] = off.to_bytes(4, "little")
        speed = 3 if tf < 17 else 2 if tf < 24 else 1 if tf < 30 else 0
        img[12 + 336 + t * 4:16 + 336 + t * 4] = speed.to_bytes(4, "little")
        img += len(g).to_bytes(2, "little") + g
        off += len(g) + 2
    return bytes(img)


def decode_track(gcr, nsec_cnt):
    """Bit-level decode: sync = 10+ ones; returns {sector: 256 bytes}."""
    bits = []
    for b in gcr + gcr:                      # circular: two revolutions
        bits += [(b >> (7 - i)) & 1 for i in range(8)]
    found = {}
    ones = 0
    i = 0
    hdr_sec = None
    while i < len(bits):
        b = bits[i]
        if b:
            ones += 1
            i += 1
            continue
        if ones < 10:
            ones = 0
            i += 1
            continue
        ones = 0
        # block starts at bit i
        def byte_at(k):
            p = i + k * 10
            if p + 10 > len(bits):
                return None
            v = 0
            for x in bits[p:p + 10]:
                v = (v << 1) | x
            return (BIN.get(v >> 5, 0) << 4) | BIN.get(v & 31, 0)
        t = byte_at(0)
        if t == 0x08:
            s = byte_at(2)
            hdr_sec = s if s is not None and s < nsec_cnt else None
        elif t == 0x07 and hdr_sec is not None:
            data = [byte_at(k) for k in range(1, 257)]
            if None not in data:
                found[hdr_sec] = bytes(data)
            hdr_sec = None
        i += 1
    return found


if __name__ == "__main__":
    src = open(sys.argv[1], "rb").read()
    open(sys.argv[2], "wb").write(synth_g64(src))
