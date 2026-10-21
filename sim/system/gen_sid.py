#!/usr/bin/env python3
"""Verilator cannot parse `function f(wire signed [..] x)` as used in the SID: copy the SID sources
to work/sid with `wire` arguments turned into `input`."""
import os, re, shutil
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.normpath(os.path.join(here, '../../src/fpga/C64_MiSTer/rtl/sid'))
dst = os.path.join(here, 'work/sid')
os.makedirs(dst, exist_ok=True)
for f in os.listdir(src):
    if not f.endswith('.sv'):
        continue
    t = open(os.path.join(src, f)).read()
    while True:
        t2 = re.sub(r'(function[^\n(]*\([^)]*?)\bwire\b', r'\1input', t)
        if t2 == t:
            break
        t = t2
    open(os.path.join(dst, f), 'w').write(t)
