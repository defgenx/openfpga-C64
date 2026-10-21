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
