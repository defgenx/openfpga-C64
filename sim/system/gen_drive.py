#!/usr/bin/env python3
"""Prepare C64_MiSTer's iec_drive (1541 / 1581) for Verilator:
  * copy rtl/iec_drive/*.sv|*.v to work/drive, with the ROM images (.mif, an Altera attribute
    Verilator ignores) turned into $readmemh of work/roms/*.hex
  * copy iecdrv_via6522.vhd to work/vhdl for the GHDL conversion (ghdl_conv.sh)
"""
import os, re, shutil
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.normpath(os.path.join(here, '../../src/fpga/C64_MiSTer/rtl/iec_drive'))
dst = os.path.join(here, 'work/drive')
rom = os.path.join(here, 'work/roms')
vh = os.path.join(here, 'work/vhdl')
for d in (dst, rom, vh):
    os.makedirs(d, exist_ok=True)


def mif2hex(mif, hexf):
    mem = {}
    depth = 0
    inside = False
    for line in open(mif):
        line = line.strip()
        m = re.match(r'DEPTH\s*=\s*(\d+)', line)
        if m:
            depth = int(m.group(1))
        if line.startswith('CONTENT BEGIN'):
            inside = True
            continue
        if line.startswith('END'):
            break
        if not inside:
            continue
        m = re.match(r'([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f ]+);', line)
        if m:
            for k, v in enumerate(m.group(2).split()):
                mem[int(m.group(1), 16) + k] = int(v, 16)
            continue
        m = re.match(r'\[([0-9A-Fa-f]+)\.\.([0-9A-Fa-f]+)\]\s*:\s*([0-9A-Fa-f]+);', line)
        if m:
            for a in range(int(m.group(1), 16), int(m.group(2), 16) + 1):
                mem[a] = int(m.group(3), 16)
    open(hexf, 'w').write(''.join('%02x\n' % mem.get(i, 0) for i in range(depth)))


for f in os.listdir(src):
    p = os.path.join(src, f)
    if f.endswith('.mif'):
        mif2hex(p, os.path.join(rom, f[:-4] + '.hex'))
    elif f.endswith('.sv') or f.endswith('.v'):
        t = open(p).read()
        t = re.sub(r'"rtl/iec_drive/(\w+)\.mif"', r'"work/roms/\1.hex"', t)
        if f == 'iecdrv_misc.sv':
            old = '(* ram_init_file = INITFILE *) reg [DATAWIDTH-1:0] ram[1<<ADDRWIDTH];'
            assert old in t
            t = t.replace(old, 'reg [DATAWIDTH-1:0] ram[1<<ADDRWIDTH];\ninitial if (INITFILE != " ") $readmemh(INITFILE, ram);')
        if f == 'c1581_drv.sv':
            # c1581_drv leaves T65's rdy / abort_n / nmi_n / so_n open and relies on their VHDL
            # defaults ('1'), which Verilator (2-state, open inputs = 0) does not apply
            old = '\t.irq_n(cia_irq_n & ~via_irq),'
            assert old in t
            t = t.replace(old, old + "\n\t.rdy(1'b1),\n\t.abort_n(1'b1),\n\t.nmi_n(1'b1),\n\t.so_n(1'b1),")
        open(os.path.join(dst, f), 'w').write(t)
shutil.copy(os.path.join(src, 'iecdrv_via6522.vhd'), vh)
print('drive prepared')
