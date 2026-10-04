#!/usr/bin/env python3
"""Run media_tb and check every transfer against gcr_ref (Main_MiSTer's algorithms)."""
import random
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import gcr_ref

HERE = Path(__file__).parent
W = HERE / "media"
W.mkdir(exist_ok=True)
CORE = HERE.parent / "src/fpga/core"
rng = random.Random(1982)


def hexfile(p, data):
    p.write_text("".join(f"{b:02x}\n" for b in data))


def readhex(p):
    words = [l.split("//")[0].strip() for l in p.read_text().splitlines()]
    return bytes(int(x, 16) for w in words for x in w.split() if not x.startswith("@"))


def rnd(n):
    return bytes(rng.randrange(256) for _ in range(n))


def rotate_bits(data, k):
    v = int.from_bytes(data, "big")
    n = len(data) * 8
    return (((v << k) | (v >> (n - k))) & ((1 << n) - 1)).to_bytes(len(data), "big")


prg = rnd(3000)
d64 = bytearray(rnd(174848))
g64_src = bytearray(rnd(174848))
g64 = gcr_ref.synth_g64(bytes(g64_src))
d81 = rnd(819200)
hexfile(W / "slot0.hex", prg)
hexfile(W / "slot2.hex", d64)
hexfile(W / "slot3.hex", g64)
hexfile(W / "slot2_d81.hex", d81)

# D64 flush of track 18 (19 sectors), not byte aligned
id0, id1 = d64[0x165A2], d64[0x165A3]
new18 = rnd(19 * 256)
t18 = rotate_bits(gcr_ref.synth_track(new18, 18, id0, id1), 5)
hexfile(W / "bg_d64.hex", len(t18).to_bytes(2, "little") + t18)
# G64 flush of track 1
new1 = gcr_ref.synth_track(rnd(21 * 256), 1, 0x30, 0x31)
bg_g64 = len(new1).to_bytes(2, "little") + new1
hexfile(W / "bg_g64.hex", bg_g64)
# D81 sector write
w81 = rnd(512)
hexfile(W / "bg_d81.hex", w81)

files = [CORE / f for f in ("c64_media.sv", "gcr_synth.sv", "gcr_decode.sv", "ddram_psram.sv", "psram.sv")]
subprocess.run(["iverilog", "-g2012", "-o", str(W / "media_tb.vvp"), str(HERE / "media_tb.sv")] + [str(f) for f in files],
               check=True)
out = subprocess.run(["vvp", "-n", str(W / "media_tb.vvp"), f"+dir={W}", f"+prg={len(prg)}", f"+d8={len(d64)}",
                      f"+d9={len(g64)}"], check=True, capture_output=True, text=True).stdout
print("".join(l + "\n" for l in out.splitlines() if not l.startswith(("Instantiated", "  ", "INFO", "\t"))))

fail = []
def check(name, ok):
    print(f"{name:42} {'OK' if ok else 'FAIL'}")
    if not ok:
        fail.append(name)

check("no FAIL from the bench", "FAIL" not in out)
lines = [l.split() for l in (W / "ioctl.txt").read_text().splitlines()]
check("prg: index 01, every byte in order",
      len(lines) == len(prg) and all(l[0] == "01" and int(l[1], 16) == i and int(l[2], 16) == prg[i]
                                     for i, l in enumerate(lines)))

dd = b"".join(int(x.replace("x", "0"), 16).to_bytes(8, "little") for x in (W / "d64_ddram.hex").read_text().split())
exp = gcr_ref.synth_g64(bytes(d64))
check(f"d64: PSRAM image = synthesized G64 ({len(exp)} B)", dd[:len(exp)] == exp)

d64_out = readhex(W / "slot2_d64.hex")
s18 = gcr_ref.START[17] * 256
d64_exp = bytes(d64[:s18]) + new18 + bytes(d64[s18 + len(new18):])
check("d64 write-back: track 18 replaced, rest kept", d64_out == d64_exp)

gd = b"".join(int(x.replace("x", "0"), 16).to_bytes(8, "little") for x in (W / "g64_ddram.hex").read_text().split())
check("g64: PSRAM image = file", gd[:len(g64)] == g64)
g64_out = readhex(W / "slot3_out.hex")
off = int.from_bytes(g64[12:16], "little")
g64_exp = g64[:off] + bg_g64 + g64[off + len(bg_g64):]
check("g64 write-back: track 1 at its file offset", g64_out == g64_exp)

check("d81: blocks 20-21 read", readhex(W / "rd81.hex") == d81[20 * 256:22 * 256])
d81_out = readhex(W / "slot2_out.hex")
check("d81: blocks 40-41 written, rest kept", d81_out == d81[:40 * 256] + w81 + d81[42 * 256:])

print("media: all OK" if not fail else f"media: {len(fail)} FAILED")
sys.exit(1 if fail else 0)
