#!/usr/bin/env python3
"""Run gcr_tb: gcr_synth must match gcr_ref.synth_track byte for byte; gcr_decode must
find every sector of a track at any bit rotation, and report a sector whose header
is damaged as missing."""
import random
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import gcr_ref

HERE = Path(__file__).parent
W = HERE / "gcr"
W.mkdir(exist_ok=True)
CORE = HERE.parent / "src/fpga/core"


def hexfile(p, data):
    p.write_text("".join(f"{b:02x}\n" for b in data))


def readhex(p):
    words = [l.split("//")[0].strip() for l in p.read_text().splitlines()]
    return bytes(int(x, 16) for w in words for x in w.split() if not x.startswith("@"))


def sim(args):
    subprocess.run(["vvp", "-n", str(W / "gcr_tb.vvp")] + args, check=True, stdout=subprocess.DEVNULL)


def rotate_bits(data, k):
    v = int.from_bytes(data, "big")
    n = len(data) * 8
    v = ((v << k) | (v >> (n - k))) & ((1 << n) - 1)
    return v.to_bytes(len(data), "big")


subprocess.run(["iverilog", "-g2012", "-o", str(W / "gcr_tb.vvp"), str(HERE / "gcr_tb.sv"),
                str(CORE / "gcr_synth.sv"), str(CORE / "gcr_decode.sv")], check=True)
rng = random.Random(64)
fail = 0
for track in (1, 17, 18, 24, 25, 30, 31, 35, 40):
    tf = track - 1
    ns = gcr_ref.nsec(tf)
    data = bytes(rng.randrange(256) for _ in range(ns * 256))
    id0, id1 = rng.randrange(256), rng.randrange(256)
    exp = gcr_ref.synth_track(data, track, id0, id1)
    hexfile(W / "trk.hex", data)
    sim([f"+track={track}", f"+nsec={ns}", f"+id0={id0}", f"+id1={id1}",
         f"+trk={W / 'trk.hex'}", f"+out={W / 'out.hex'}"])
    got = readhex(W / "out.hex")
    ok = got == exp
    fail += not ok
    print(f"synth  track {track:2}: {len(got)} bytes {'OK' if ok else 'MISMATCH'}")

    for rot in (0, 3, 13 * 8 + 5):
        g = rotate_bits(exp, rot)
        damaged = None
        if rot == 3:
            # damage the header of sector 5: its data block must not be decoded
            pos = 5 * (len(exp) // ns) + 5
            g = bytearray(rotate_bits(exp, 0))
            g[pos] ^= 0xFF
            g = rotate_bits(bytes(g), rot)
            damaged = 5
        hexfile(W / "buf.hex", len(g).to_bytes(2, "little") + g)
        sim([f"+nsec={ns}", f"+buf={W / 'buf.hex'}", f"+sec={W / 'sec.hex'}", f"+mask={W / 'mask.hex'}"])
        secs = readhex(W / "sec.hex")
        mask = int((W / "mask.hex").read_text().split()[0], 16)
        exp_mask = ((1 << ns) - 1) & ~((1 << damaged) if damaged is not None else 0)
        ok = mask == exp_mask and all(secs[s * 256:(s + 1) * 256] == data[s * 256:(s + 1) * 256]
                                      for s in range(ns) if exp_mask >> s & 1)
        ref = gcr_ref.decode_track(g, ns)
        ok = ok and sorted(ref) == [s for s in range(ns) if exp_mask >> s & 1]
        fail += not ok
        print(f"decode track {track:2} rot {rot:3}: mask {mask:06x} {'OK' if ok else 'MISMATCH'}")

print("gcr: all OK" if not fail else f"gcr: {fail} FAILED")
sys.exit(1 if fail else 0)
