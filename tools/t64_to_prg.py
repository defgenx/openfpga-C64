#!/usr/bin/env python3
"""Convert .t64 tape archives to .prg files the core can load (Program slot).

    python3 tools/t64_to_prg.py                      the Pocket card's Assets/c64/common, found by itself
    python3 tools/t64_to_prg.py <file.t64 | folder>  only these (folders are searched recursively)

Each .prg is written next to its .t64; an existing .prg is never overwritten, so it
can be run again after adding files. A T64 holding several programs gives one .prg
per program (name_2.prg, ...).
"""
import getpass
import os
import string
import struct
import sys
from pathlib import Path

COMMON = Path("Assets") / "c64" / "common"


def find_cards():
    """Mounted volumes that hold Assets/c64/common (same places as install.sh)."""
    if os.name == "nt":
        vols = [Path(f"{d}:/") for d in string.ascii_uppercase[3:]]
    else:
        user = getpass.getuser()
        vols = []
        for base in ("/Volumes", f"/media/{user}", f"/run/media/{user}", "/media", "/mnt"):
            try:
                vols += sorted(Path(base).iterdir())
            except OSError:
                pass
    found = []
    for v in vols:
        try:
            if (v / COMMON).is_dir() and v / COMMON not in found:
                found.append(v / COMMON)
        except OSError:
            pass
    return found


def pick_card():
    cards = find_cards()
    if len(cards) == 1:
        print(f"Pocket card: {cards[0]}")
        return cards[0]
    if not cards:
        sys.exit("no card with Assets/c64/common found - insert the Pocket SD card, or pass a folder")
    for i, c in enumerate(cards, 1):
        print(f"  {i}) {c}")
    if not sys.stdin.isatty():
        sys.exit("several cards found - pass the folder to convert")
    n = input("Number of the card to convert: ").strip()
    if not n.isdigit() or not 1 <= int(n) <= len(cards):
        sys.exit("invalid choice")
    return cards[int(n) - 1]


def entries(data):
    """(start address, payload) for each program in a T64 image."""
    if len(data) < 64 or not data.startswith(b"C64"):
        raise ValueError("not a T64 image")
    max_entries, used = struct.unpack_from("<HH", data, 0x22)
    dirs = []
    for i in range(max(max_entries, used, 1)):
        off = 0x40 + 32 * i
        if off + 32 > len(data):
            break
        etype, _, start, end, _, offset = struct.unpack_from("<BBHHHI", data, off)
        if etype == 1 and 0 < offset < len(data):
            dirs.append((offset, start, end))
    dirs.sort()
    out = []
    for n, (offset, start, end) in enumerate(dirs):
        # the end address is often wrong in T64s made by old tools: cap the length
        # by the next entry's data or the end of the file
        limit = dirs[n + 1][0] if n + 1 < len(dirs) else len(data)
        length = (end - start) & 0xFFFF
        if length == 0 or offset + length > limit:
            length = limit - offset
        out.append((start, data[offset:offset + length]))
    if not out:
        raise ValueError("no program in this T64")
    return out


def convert(path):
    """Number of .prg files written."""
    progs = entries(path.read_bytes())
    written = 0
    for n, (start, payload) in enumerate(progs):
        suffix = "" if n == 0 else f"_{n + 1}"
        dst = path.with_name(f"{path.stem}{suffix}.prg")
        if dst.exists():
            continue
        dst.write_bytes(struct.pack("<H", start) + payload)
        print(f"{path} -> {dst.name} (${start:04X}, {len(payload)} bytes)")
        written += 1
    return written


def main(args):
    if args and args[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    targets = [Path(a) for a in args] or [pick_card()]
    found = written = failed = 0
    for p in targets:
        files = sorted(f for f in p.rglob("*") if f.suffix.lower() == ".t64") if p.is_dir() else [p]
        for f in files:
            if f.name.startswith("._"):   # macOS metadata files on FAT cards
                continue
            found += 1
            try:
                written += convert(f)
            except (ValueError, OSError) as e:
                print(f"{f}: skipped ({e})", file=sys.stderr)
                failed += 1
    print(f"{found} .t64 found, {written} .prg written, {failed} skipped")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
