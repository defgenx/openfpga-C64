#!/usr/bin/env python3
"""Build the disk images and programs of the disk tests into work/disk/ (hex, one byte per line,
for $readmemh in tb_system.sv) plus work/disk/disk.vh with the sizes.

  run.d64 / run.g64   one PRG "TEST": BASIC stub `10 SYS 2061`, code writes $AA/$55 to $C000/$C001
  wb.d64              one PRG "TEST": same, then SAVEs 16 bytes ("OUT", $C100..$C10F, byte i = i ^ $5A)
                      through the KERNAL and writes $77 to $C002 when SAVE has returned
                      ($C003 = carry of SAVE)
  wb2.d64             one PRG "TEST": SAVEs "OUT" ($2000-$37FF, 25 blocks, byte = y ^ page), scratches it
                      (S0:OUT), SAVEs it again (byte = y ^ page ^ $A5); $C003/$C004 = carry of each SAVE,
                      $C002 = $77 at the end
  wb4.d64             one PRG "TEST", tracks 1-17 full in the BAM: SAVEs "OUT" ($2000-$2257, byte = y ^ page ^ $5C),
                      which lands on track 19; $C003 = carry of SAVE, $C002 = $77 at the end
  run.d81             the 1581 variant of run.d64 (if the drive is built with the 1581)
"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, '..'))
import gcr_ref

out = os.path.join(here, 'work/disk')
os.makedirs(out, exist_ok=True)


def basic_stub():
    # 10 SYS 2061 ; code at $080D
    return bytes([0x0B, 0x08, 0x0A, 0x00, 0x9E, 0x32, 0x30, 0x36, 0x31, 0x00, 0x00, 0x00])


def prog_run():
    c = bytearray()
    c += bytes([0xA9, 0xAA, 0x8D, 0x00, 0xC0, 0xA9, 0x55, 0x8D, 0x01, 0xC0])   # sig
    c += bytes([0xA9, 0x05, 0x8D, 0x20, 0xD0])                                 # border green
    pc = 0x080D + len(c)
    c += bytes([0x4C, pc & 255, pc >> 8])                                      # JMP *
    return bytes([0x01, 0x08]) + basic_stub() + bytes(c)


def prog_wb():
    c = bytearray()
    base = 0x080D
    c += bytes([0xA9, 0xAA, 0x8D, 0x00, 0xC0, 0xA9, 0x55, 0x8D, 0x01, 0xC0])   # sig
    c += bytes([0xA2, 0x00])                                                   # LDX #0
    loop = base + len(c)
    c += bytes([0x8A, 0x49, 0x5A, 0x9D, 0x00, 0xC1, 0xE8, 0xE0, 0x10])         # TXA EOR #$5A STA $C100,X INX CPX #16
    off = (loop - (base + len(c) + 2)) & 255
    c += bytes([0xD0, off])                                                    # BNE loop
    # SETNAM: A = 3, X/Y = address of "OUT" (placed after the code)
    setnam_at = len(c)
    c += bytes([0xA9, 0x03, 0xA2, 0x00, 0xA0, 0x00, 0x20, 0xBD, 0xFF])
    c += bytes([0xA9, 0x01, 0xA2, 0x08, 0xA0, 0x01, 0x20, 0xBA, 0xFF])         # SETLFS 1,8,1
    c += bytes([0xA9, 0x00, 0x85, 0xFB, 0xA9, 0xC1, 0x85, 0xFC])               # $FB/$FC = $C100
    c += bytes([0xA9, 0xFB, 0xA2, 0x10, 0xA0, 0xC1, 0x20, 0xD8, 0xFF])         # SAVE, end = $C110
    c += bytes([0xA9, 0x00, 0x2A, 0x8D, 0x03, 0xC0])                           # LDA #0 ROL STA $C003
    c += bytes([0xA9, 0x77, 0x8D, 0x02, 0xC0])                                 # $C002 = $77
    pc = base + len(c)
    c += bytes([0x4C, pc & 255, pc >> 8])                                      # JMP *
    name = base + len(c)
    c += b'OUT'
    c[setnam_at + 3] = name & 255
    c[setnam_at + 5] = name >> 8
    return bytes([0x01, 0x08]) + basic_stub() + bytes(c)


def asm(base, parts):
    """parts: ints (bytes), ('L', name) labels, (kind, name) refs with kind abs / lo / hi / rel."""
    code, fix, labels = bytearray(), [], {}
    for p in parts:
        if isinstance(p, int): code.append(p)
        elif isinstance(p, bytes): code += p
        elif p[0] == 'L': labels[p[1]] = base + len(code)
        else:
            fix.append((len(code), p[0], p[1])); code += bytes(2 if p[0] == 'abs' else 1)
    for at, kind, name in fix:
        a = labels[name]
        if kind == 'abs': code[at:at + 2] = bytes([a & 255, a >> 8])
        elif kind == 'lo': code[at] = a & 255
        elif kind == 'hi': code[at] = a >> 8
        else:
            d = a - (base + at + 1)
            assert -128 <= d < 128
            code[at] = d & 255
    return bytes(code)


def prog_wb2():
    def setnam(n, name): return [0xA9, n, 0xA2, ('lo', name), 0xA0, ('hi', name), 0x20, 0xBD, 0xFF]
    code = asm(0x080D, [
        0xA9, 0xAA, 0x8D, 0x00, 0xC0, 0xA9, 0x55, 0x8D, 0x01, 0xC0,       # sig
        0xA9, 0x00, 0x85, 0xFD, 0x20, ('abs', 'fill'),                    # fill, $FD = 0
        0x20, ('abs', 'save'), 0xA9, 0x00, 0x2A, 0x8D, 0x03, 0xC0,        # SAVE, carry -> $C003
        *setnam(6, 'scr'),
        0xA9, 0x0F, 0xA2, 0x08, 0xA0, 0x0F, 0x20, 0xBA, 0xFF,             # SETLFS 15,8,15
        0x20, 0xC0, 0xFF, 0xA9, 0x0F, 0x20, 0xC3, 0xFF,                   # OPEN, CLOSE 15
        0xA9, 0xA5, 0x85, 0xFD, 0x20, ('abs', 'fill'),                    # fill, $FD = $A5
        0x20, ('abs', 'save'), 0xA9, 0x00, 0x2A, 0x8D, 0x04, 0xC0,        # SAVE, carry -> $C004
        0xA9, 0x77, 0x8D, 0x02, 0xC0,
        ('L', 'end'), 0x4C, ('abs', 'end'),
        # fill: $2000-$37FF, byte = y ^ page ^ ($FD)
        ('L', 'fill'), 0xA9, 0x00, 0x85, 0xFB, 0xA9, 0x20, 0x85, 0xFC, 0xA0, 0x00,
        ('L', 'floop'), 0x98, 0x45, 0xFC, 0x45, 0xFD, 0x91, 0xFB, 0xC8, 0xD0, ('rel', 'floop'),
        0xE6, 0xFC, 0xA5, 0xFC, 0xC9, 0x38, 0xD0, ('rel', 'floop'), 0x60,
        # save: "OUT", 1,8,1, $2000-$37FF
        ('L', 'save'), *setnam(3, 'out'),
        0xA9, 0x01, 0xA2, 0x08, 0xA0, 0x01, 0x20, 0xBA, 0xFF,
        0xA9, 0x00, 0x85, 0xFB, 0xA9, 0x20, 0x85, 0xFC,
        0xA9, 0xFB, 0xA2, 0x00, 0xA0, 0x38, 0x20, 0xD8, 0xFF, 0x60,
        ('L', 'out'), b'OUT', ('L', 'scr'), b'S0:OUT'])
    return bytes([0x01, 0x08]) + basic_stub() + code


def prog_wb4():
    def setnam(n, name): return [0xA9, n, 0xA2, ('lo', name), 0xA0, ('hi', name), 0x20, 0xBD, 0xFF]
    code = asm(0x080D, [
        0xA9, 0xAA, 0x8D, 0x00, 0xC0, 0xA9, 0x55, 0x8D, 0x01, 0xC0,       # sig
        0xA9, 0x00, 0x8D, 0x04, 0xC0, 0x85, 0xFB, 0xA9, 0x20, 0x85, 0xFC, # fill $2000-$22FF: y ^ page ^ $5C
        0xA0, 0x00, ('L', 'floop'), 0x98, 0x45, 0xFC, 0x49, 0x5C, 0x91, 0xFB, 0xC8, 0xD0, ('rel', 'floop'),
        0xE6, 0xFC, 0xA5, 0xFC, 0xC9, 0x23, 0xD0, ('rel', 'floop'),
        *setnam(3, 'out'), 0xA9, 0x01, 0xA2, 0x08, 0xA0, 0x01, 0x20, 0xBA, 0xFF,
        0xA9, 0x00, 0x85, 0xFB, 0xA9, 0x20, 0x85, 0xFC,                   # SAVE $2000-$2257 (600 bytes)
        0xA9, 0xFB, 0xA2, 0x58, 0xA0, 0x22, 0x20, 0xD8, 0xFF, 0xA9, 0x00, 0x2A, 0x8D, 0x03, 0xC0,
        0xA9, 0x77, 0x8D, 0x02, 0xC0,
        ('L', 'end'), 0x4C, ('abs', 'end'),
        ('L', 'out'), b'OUT'])
    return bytes([0x01, 0x08]) + basic_stub() + code


def full_low_tracks(img):
    """Mark tracks 1-17 full in the BAM, so a new file goes to track 19 (19-sector zone)."""
    img = bytearray(img)
    bam = (gcr_ref.START[17]) * 256
    for t in range(1, 18):
        img[bam + 4 * t:bam + 4 * t + 4] = bytes(4)
    return bytes(img)


def build_d64(prg, name=b'TEST'):
    img = bytearray(174848)
    sec_off = lambda t, s: (gcr_ref.START[t - 1] + s) * 256
    # BAM
    bam = sec_off(18, 0)
    img[bam:bam + 4] = bytes([18, 1, 0x41, 0])
    used = {(18, 0), (18, 1), (1, 0)}
    for t in range(1, 36):
        n = gcr_ref.nsec(t - 1)
        bits = [0, 0, 0]
        free = 0
        for s in range(n):
            if (t, s) not in used:
                bits[s // 8] |= 1 << (s % 8)
                free += 1
        img[bam + 4 * t:bam + 4 * t + 4] = bytes([free] + bits)
    img[bam + 0x90:bam + 0xA0] = b'SIMDISK'.ljust(16, b'\xa0')
    img[bam + 0xA0:bam + 0xAB] = bytes([0xA0, 0xA0, 0x53, 0x44, 0xA0, 0x32, 0x41, 0xA0, 0xA0, 0xA0, 0xA0])
    # directory
    d = sec_off(18, 1)
    img[d:d + 2] = bytes([0, 0xFF])
    img[d + 2] = 0x82                       # PRG, closed
    img[d + 3:d + 5] = bytes([1, 0])        # first sector 1/0
    img[d + 5:d + 21] = name.ljust(16, b'\xa0')
    img[d + 0x1E:d + 0x20] = bytes([1, 0])
    # the file: one sector (<= 254 bytes)
    assert len(prg) <= 254
    f = sec_off(1, 0)
    img[f:f + 2] = bytes([0, len(prg) + 1])
    img[f + 2:f + 2 + len(prg)] = prg
    return bytes(img)


def build_d81(prg, name=b'TEST'):
    img = bytearray(819200)
    sec = lambda t, s: ((t - 1) * 40 + s) * 256
    # header 40/0
    h = sec(40, 0)
    img[h:h + 4] = bytes([40, 3, 0x44, 0])
    img[h + 4:h + 20] = b'SIMDISK'.ljust(16, b'\xa0')
    img[h + 0x16:h + 0x18] = b'SD'
    img[h + 0x19] = 0x33; img[h + 0x1A] = 0x44
    # BAM 40/1 and 40/2: bitmaps (all free except what is used)
    used = {(40, 0), (40, 1), (40, 2), (40, 3), (1, 0)}
    for half, bs in ((0, sec(40, 1)), (1, sec(40, 2))):
        img[bs:bs + 2] = bytes([40, 2 if half == 0 else 0]) if half == 0 else bytes([0, 0xFF])
        img[bs + 2] = 0x44; img[bs + 3] = 0xBB
        img[bs + 4:bs + 6] = b'SD'
        img[bs + 6] = 0xC0
        for t in range(1, 41):
            tt = t + 40 * half
            free = 0
            bits = [0] * 5
            for s in range(40):
                if (tt, s) not in used:
                    bits[s // 8] |= 1 << (s % 8)
                    free += 1
            o = bs + 16 + (t - 1) * 6
            img[o] = free
            img[o + 1:o + 6] = bytes(bits)
    # directory 40/3
    d = sec(40, 3)
    img[d:d + 2] = bytes([0, 0xFF])
    img[d + 2] = 0x82
    img[d + 3:d + 5] = bytes([1, 0])
    img[d + 5:d + 21] = name.ljust(16, b'\xa0')
    img[d + 0x1E:d + 0x20] = bytes([1, 0])
    f = sec(1, 0)
    img[f:f + 2] = bytes([0, len(prg) + 1])
    img[f + 2:f + 2 + len(prg)] = prg
    return bytes(img)


def hexfile(name, data):
    with open(os.path.join(out, name), 'w') as f:
        f.write(''.join('%02x\n' % b for b in data))


if __name__ == '__main__':
    run, wb = prog_run(), prog_wb()
    d64_run, d64_wb, d64_wb2 = build_d64(run), build_d64(wb), build_d64(prog_wb2())
    d64_wb4 = full_low_tracks(build_d64(prog_wb4()))
    g64 = gcr_ref.synth_g64(d64_run)
    d81 = build_d81(run)
    hexfile('run.d64.hex', d64_run)
    hexfile('wb.d64.hex', d64_wb)
    hexfile('run.g64.hex', g64)
    hexfile('run.g64_ref.hex', gcr_ref.synth_g64(d64_run))
    hexfile('wb.g64_ref.hex', gcr_ref.synth_g64(d64_wb))
    hexfile('wb2.d64.hex', d64_wb2)
    hexfile('wb2.g64_ref.hex', gcr_ref.synth_g64(d64_wb2))
    hexfile('wb4.d64.hex', d64_wb4)
    hexfile('wb4.g64_ref.hex', gcr_ref.synth_g64(d64_wb4))
    hexfile('run.d81.hex', d81)
    open(os.path.join(out, 'run.g64'), 'wb').write(g64)
    with open(os.path.join(out, 'disk.vh'), 'w') as f:
        f.write('`define D64_SIZE %d\n`define G64_SIZE %d\n`define D81_SIZE %d\n' % (len(d64_run), len(g64), len(d81)))
    print('disk images in', out, 'g64 size', len(g64))
