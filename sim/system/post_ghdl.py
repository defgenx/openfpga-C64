#!/usr/bin/env python3
"""ghdl keeps the VHDL port case (ntscMode, romL, IOE...), c64_top.sv uses lower case.
Rename those ports (and only those) in module fpga64_sid_iec of work/fpga64.v."""
import re, os
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, 'work/fpga64.v')
t = open(src).read()
i = t.index('module fpga64_sid_iec\n')
head, body = t[:i], t[i:]
for a, b in [('ntscMode', 'ntscmode'), ('romL', 'roml'), ('romH', 'romh'), ('IOE', 'ioe'),
             ('IOF', 'iof'), ('joyA', 'joya'), ('joyB', 'joyb')]:
    body = re.sub(r'\b%s\b' % a, b, body)
out = head + body
out = re.sub(r'\bbreak\b', 'break_s', out)   # reserved word in SystemVerilog
open(os.path.join(here, 'work/fpga64_conv.v'), 'w').write(out)

# ---- the drive's T65 and VIA: names as iec_drive's SystemVerilog uses them -------------------
d = open(os.path.join(here, 'work/t65_drv.v')).read()
d = d.replace('_Brtl', '_Bdrv')        # do not clash with the sub-modules inside fpga64.v
i = d.index('module T65\n')
head, body = d[:i], d[i:]
for a, b in [('Mode', 'mode'), ('Res_n', 'res_n'), ('Enable', 'enable'), ('Clk', 'clk'), ('Rdy', 'rdy'),
             ('Abort_n', 'abort_n'), ('IRQ_n', 'irq_n'), ('NMI_n', 'nmi_n'), ('SO_n', 'so_n'),
             ('R_W_n', 'r_w_n')]:
    body = re.sub(r'(?<![.\w])%s\b' % a, b, body, count=0)
# BCD_en has a VHDL default of '1' that the instantiation relies on
body = body.replace('input  BCD_en,', 'input  BCD_en_unused,', 1)
body = body.replace('output NMI_ack);', 'output NMI_ack);\n  wire BCD_en = 1\'b1;', 1)
open(os.path.join(here, 'work/t65_drv_conv.v'), 'w').write(re.sub(r'\bbreak\b', 'break_s', head + body))
