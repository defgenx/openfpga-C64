# Architecture

This core is [C64_MiSTer](https://github.com/MiSTer-devel/C64_MiSTer) with a new board layer for the
Analogue Pocket. The machine — everything under `rtl/` (FPGA64, 6510, VIC-II, CIAs, SIDs, cartridge,
REU, tape, 1541/1581 drives) — is used **unmodified**, as a git submodule pinned in
`src/fpga/C64_MiSTer`. Only `c64.sv` (the `emu` top) and the MiSTer framework under `sys/` are replaced.

```
apf_top (Analogue)
└── core_top                      src/fpga/core/core_top.v
    ├── pll_c64 + pll_cfg         74.25 MHz -> clk_sys 31.53 (PAL) / 32.73 (NTSC), clk_sys_90, clk64, clk48
    ├── core_bridge_cmd           Analogue host/target command handler (template, unchanged)
    ├── c64_media                 files and disk images over target commands (stands in for the ARM)
    │   ├── gcr_synth             D64 track -> GCR (Main_MiSTer's c64_synthesize_gcr_track)
    │   └── gcr_decode            flushed GCR track -> D64 sectors (Main_MiSTer's c64_writeGCR)
    ├── ddram_psram               MiSTer's DDRAM port on the Pocket's PSRAM (agg23's psram.sv)
    ├── hid_c64                   Dock keyboard/mouse + pad -> ps2_key / ps2_mouse words
    ├── autostart                 types LOAD"*",8,1 / RUN for a disk or tape picked at the BASIC prompt
    ├── osk_ctrl / osk_overlay    on-screen keyboard
    ├── c64_video                 VIC-II output -> APF scaler (fixed windows, slot select)
    ├── sound_i2s                 16-bit stereo -> Pocket I2S DAC (agg23, MIT)
    └── c64_top                   c64.sv's machine without hps_io / scaler / HDMI
```

`c64_top.sv` is derived from `c64.sv` and keeps its logic (memory loader, PRG injection and RUN,
cartridge header parsing, REU, drives, tape, DigiMax, audio mix) as is. Its `status[]` input keeps
c64.sv's bit map, so that logic reads unchanged; `core_top` builds it from the menu registers. When
updating the submodule, diff `c64.sv` against the version the splice was made from and carry changes over.

## What replaces the MiSTer framework

| MiSTer (ARM + `hps_io`)                         | Pocket                                                    |
|-------------------------------------------------|-----------------------------------------------------------|
| file download (`ioctl_*`)                       | `c64_media` pulls the slot in 8 KB chunks and replays it on the same ports, honouring `ioctl_wait` |
| ARM loads a G64, or converts a D64 to G64, into DDR3 | `c64_media` copies the G64 / runs `gcr_synth` into PSRAM |
| 1541 reads the image through `DDRAM_*`           | `ddram_psram`: 64-bit words as four 16-bit PSRAM accesses |
| 1541 track flush (`sd_wr`, 8 KB, lba = half-track) | written to the G64 at the track's offset, or decoded by `gcr_decode` and written as D64 sectors |
| 1581 sectors (`sd_rd` / `sd_wr`)                 | 512-byte Dataslot Read / Write                            |
| `img_mounted` / `img_size`                       | datatable scan at boot, Dataslot Update (0x008A) when a file is picked |
| OSD `status` bits                                | `interact.json` registers at `0x8000_00xx`                |
| PS/2 keyboard / mouse                            | Dock HID reports re-encoded by `hid_c64`                  |
| USB joysticks                                    | Pocket pads 1-4                                           |
| PLL reconfiguration for NTSC                     | same, from `clk_74a`, with K values for a 74.25 MHz reference |

## Media

All slots (`data.json`) are `deferload`, so APF never pushes data at its own pace: the core asks for
exactly what it can consume with target commands. Bridge buffers: read `0x1000_0000`–`0x1000_1FFF`,
write `0x1000_4000`–`0x1000_5FFF`. The command engine runs on `clk_74a`, everything else on `clk_sys`;
requests cross as a toggle handshake whose parameters are held stable until the acknowledge returns.

| Slot | File        | ioctl index | Handling |
|------|-------------|-------------|----------|
| 0    | Program     | `0x01`      | streamed; c64.sv resets, waits for the kernal, injects the PRG and types RUN |
| 1    | Cartridge   | `0x41`      | streamed (file extension `.CRT`) |
| 2    | Disk        | –           | G64 / D64 / D81 by content (below), drive 8 |
| 4    | Tape        | `0xC1`      | streamed into SDRAM; the tape subsystem plays it |
| 5    | System ROM  | `0x08`      | streamed: first 16 KB to the C64 ROM, the rest to the 1541 |

A disk is a **G64** if it starts with `GCR-1541`, a **D81** if it is at least 819,200 bytes, otherwise a
**D64** (35, 40 or 42 tracks by size). Then:

* G64: copied byte for byte into PSRAM at `drive * 2 MB`.
* D64: the disk id is read from track 18 sector 0 (`$165A2`), a G64 header is written (offset and speed
  tables for 84 half-tracks, whole tracks only), then each track's sectors are read in one Dataslot Read
  and converted by `gcr_synth`. The result is byte-identical to the image Main_MiSTer builds in DDR3
  (`sim/run_media.py` checks it).
* D81: nothing to prepare; the 1581 reads sectors on demand.

Then `img_mounted` pulses with `img_type` 01 (1541) or 11 (1581), and C64_MiSTer's drives take over.

While a file streams or an image is prepared (not for D81, which needs no preparation), `loading`,
`load_kind` and `load_pct` drive the loading screen in `osk_overlay`. The percentage avoids a divider:
work done is added ×100 to an accumulator, and each time it reaches the total one percent is counted
(BCD) and the total subtracted.

### 1541 write-back

C64_MiSTer's `c1541_track` writes a modified track into its image (PSRAM here) itself, then flushes it
in the background with `sd_wr` (lba = half-track, 8 KB: a 2-byte length and the GCR bytes). `c64_media`
keeps `sd_ack` high while it reads that buffer, then:

* G64: writes length + 2 bytes at the track's offset from the image header, capped at the header's
  maximum track size.
* D64: `gcr_decode` scans the track twice (it is circular) bit by bit: a sync is 10 or more 1 bits, a
  header block gives the sector, the next data block is its 256 bytes. Each sector found is written to
  the file at its D64 offset. Main_MiSTer writes the whole track and zero-fills sectors it does not find;
  here they are left untouched.

## Memory

C64 RAM, cartridges (`0x200000`), tapes (`0x400000`) and the REU (`0x1000000`) live in the Pocket's
64 MB SDRAM, driven by C64_MiSTer's own `sdram.v` at clk64, which uses the low 32 MB. That controller puts
DQM on A12/A11 (MiSTer's SDRAM boards wire it there); the Pocket has separate DQM pins, so they carry the
same two bits. It drives the SDRAM clock as an inverted clk64 through a DDIO register. **This is the
first thing to look at if the C64 crashes on hardware.**

The G64 images of both drives live in PSRAM `cram0` (2 MB each). PSRAM is used in its default
asynchronous mode; one 64-bit DDRAM word takes four accesses (~0.6 µs), so a whole track loads in about
0.65 ms, well under the ~2 ms that timing-sensitive protections tolerate on a half-track step.

## Clocks

`pll_c64` is MiSTer's reconfigurable fractional PLL re-targeted to the 74.25 MHz reference: VCO =
74.25 × 7.643140 MHz (÷2 = 567.503 MHz), outputs ÷12 clk48, ÷9 clk64, ÷18 clk_sys and clk_sys_90. NTSC rewrites only
the fractional K (register 7) with the values in `pll_c64.v`, after the same 150 ms settle as c64.sv; the
C64 is reset when the standard changes. The APF video clock is clk_sys; `video_rgb_clock_90` is a fourth
PLL output, ÷18 shifted by 4.5 VCO cycles (90°). It must come from the PLL: the scaler samples the 12-bit
DDR video bus on its edges, and a clock made in logic has no fixed phase, which garbles the whole picture.

## Settings

Each `interact.json` entry writes its own register; all are read back, so APF shows (and saves) whatever
the core holds.

| Address      | Setting             | Values (c64.sv status bits)                         |
|--------------|---------------------|-----------------------------------------------------|
| `0x80000000` | Reset               | any write (status[0] pulse)                         |
| `0x80000004` | Reset & Detach Cart | any write (status[17] pulse)                        |
| `0x80000008` | Model               | 0 C64, 1 C64C (status[13], [16], [35:34], [45])     |
| `0x8000000C` | Video               | 0 PAL, 1 NTSC (PLL reconfiguration)                 |
| `0x80000010` | Joystick Port       | 0 port 2, 1 port 1 (status[3] = swap)               |
| `0x80000014` | Pad Mode            | 0 joystick, 1 mouse, 2 keys                         |
| `0x80000018` | Second SID          | status[22:20]: 0 off, 1 DE00, 2 D420, 3 D500, 4 DF00 |
| `0x8000001C` | Autostart           | 0 off, 1 on (autostart.sv)                          |
| `0x80000020` | REU                 | status[54:53]                                       |
| `0x80000024` | Write Protect       | status[76]                                          |
| `0x80000028` | Borders             | 0 hide, 1 show (c64_video)                          |
| `0x8000002C` | Palette             | status[84:82]                                       |
| `0x80000030` | Drive Display       | status[86:85]: 0 activity, 1 if mounted, 3 off      |
| `0x80000034` | Tape Play/Pause     | any write (status[7] pulse)                         |
| `0x80000038` | Turbo               | status[47:46]: 0 off, 1 C128, 2 smart               |
| `0x8000003C` | Reset All Settings  | any write: every register to its default, then a reset |

Bits not listed keep c64.sv's defaults (all 0): loadable System ROM, parallel drive port enabled, drives
enabled when a disk is mounted, PRG autorun, tape autoplay.

## Not ported

**One drive.** MiSTer builds two drives, each both a 1541 and a 1581, plus an OPL2. On the Pocket's
5CEBA4 that is ~21,800 ALMs for 18,480: `c64_top.sv` builds `iec_drive` with `DRIVES(1)` (drive 8; drive 9's
`sd_*` ports read as idle) and no OPL3. `c64_media` still handles a second drive (slot 3), as the media test
shows, should a smaller drive build make room for it.

User port RS-232 (UP9600 / VIC-1011), external IEC and SNAC, paddles, EasyFlash save-back
(`ioctl_upload`), the tape ADC input, `.t64` (MiSTer converts it on the ARM; here `convert-t64` / `tools/t64_to_prg.py` does it once on a computer) and the drive overlay's DDRAM
debug view are tied off in `c64_top.sv` / `core_top.v`.
