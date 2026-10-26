# Full-system simulation (Verilator)

`core_top` (the real Pocket top: `core_bridge_cmd`, `c64_media`, `ddram_psram`, `c64_top`,
`autostart`, `hid_c64`, video) with the real C64 machine from C64_MiSTer, an Analogue APF host/target
model and a 16-bit SDR SDRAM model. It exercises the PRG / T64 / CRT / TAP path that `sim/media_tb.sv`
only covers against a model of the C64 side.

    make -C sim/system            # build (first time: converts the VHDL in Docker) and run all tests
    make -C sim/system prg        # boot + PRG only (also: boot, t64, crt, tap, turbo)
    make -C sim/system TRACE=1 ARGS="+dump_from=637000 +dump_to=640000"   # FST in work/system.fst

A run takes ~2 minutes of wall time per simulated second of C64 time (boot is 0.58 s sim time).
Needs verilator >= 5.052, python3, docker with `hdlc/ghdl:yosys`.

## What is real, converted, stubbed

| Part | How |
|------|-----|
| core_top, core_bridge_cmd, c64_media, c64_top, ddram_psram/psram, autostart, hid_c64, osk, c64_video | real RTL, unmodified |
| sdram.v, cartridge.v, reu.v, mos6526.v, c1351, c1530, tape_subsystem/tap_scanner/tap_time_map/tape_counter, rtcF83, SID | real RTL (SID: copies in `work/sid` with `function(wire ..)` turned into `input`, which Verilator cannot parse) |
| fpga64_sid_iec (6510/T65, VIC-II, buslogic, keyboard, rgbcolor), video_sync | VHDL converted with `ghdl synth --out=verilog` (`gen_vhdl.py`, `ghdl_conv.sh`, `post_ghdl.py`). Patches on the copy only: `work.T65` instantiation, static port actual, `when others` on a few case statements, ports renamed to the lower case c64_top.sv uses |
| kernal / chargen ROMs (`dprom`) | `dprom` replaced by generated Verilog ROMs (`work/dprom_*.v`) loaded with `$readmemh` from the `.mif` files converted by `gen_vhdl.py` |
| pll_c64 / pll_cfg | stub: PAL 31.526 MHz clk_sys (31720 ps), clk64 exactly 2x with coinciding rising edges, locked at 20 us. The reconfiguration is modelled: pll_cfg keeps K (register 7) and 'start' (register 2); the PLL drops `locked` for 60 us and then runs at 74.25 MHz x (7 + K/2^32) / 9 for clk64 (NTSC: 32.727 MHz clk_sys) |
| mf_datatable, altddio_out, scfifo | behavioural models (`stubs.sv`) |
| SDRAM chip | `sdram_model.sv`: 4 banks x 8192 x 1024 x 16, CL / BL from the mode register, DQM, auto-precharge; counts protocol errors (tRCD, closed bank, open-bank ACTIVE, mode register not set); `peek8` backdoor uses the controller's address map |
| iec_drive (1541 + 1581, Dolphin ROM, parallel port) | real RTL from `rtl/iec_drive` (`gen_drive.py`: ROM `.mif` -> `$readmemh`); its VHDL (`T65`, `iecdrv_via6522`) converted with GHDL like the C64 (`t65_drv_conv.v`, `via_drv.v`; `BCD_en` tied to its VHDL default 1) |
| sound_i2s | stubbed (no audio) |
| PSRAM (cram0) | real `ddram_psram`/`psram` on `psram_model.sv`: 8 MB async CellularRAM, multiplexed address, checks t_vp/t_avs/t_avh/t_cvs/t_wp/t_dw/t_aw and the 70/20 ns read access times (data is garbage before it is valid), `err` counter, peek8/poke8 backdoors |
| APF | `tb_system.sv`: bridge read/write, host commands (poll for 0x4F4B), datatable, target-command servicing (see below) |

## APF model: what was assumed

* Boot order: `0x0010` reset enter, `0x0011` reset exit, datatable (id/size per slot, size 0), `0x008F`
  (`+order=1` puts reset exit last). The task text gave this order; real APF may differ.
* Target commands are polled by reading `0xF8001000` every ~0.7 us; `0x0140` is acknowledged at once with `0x6F6B0000`.
* `0x0180` read: parameters from `0xF8001020..2C`, then `0x62750000`, then the data as 32 bit bridge
  writes (first byte in bits 31:24, one word every `+gap` = 2 clk_74a cycles, bytes past the length are 0), then `0x6F6B0000`.
* A file pick: datatable words `{id}`, `{size}` at `0xF8002000 + 8*slot`, then host command `0x008A`.
  `core_bridge_cmd` holds `dataslot_update` for 2 cycles; that is the template's behaviour, not a guess.
* Real APF bridge timing (gaps between writes, polling period, latency of the SD card) is not modelled.

## Files

`tb_system.sv` testbench and APF model, `sdram_model.sv`, `stubs.sv`, `gen_vhdl.py` / `ghdl_conv.sh` /
`ghdl_docker.sh` / `post_ghdl.py` (VHDL conversion), `gen_sid.py`.
Everything generated is under `work/` (git-ignored).

## Tests

| target | what | sim time / wall time (several runs in parallel on a busy machine) |
|--------|------|------|
| `make` (boot, turbo, prg x2, t64, crt, tap) | default suite on one boot, with the real 1541/1581 present | 4 s / 8.5 min, 30 checks |
| ntsc | Video register = NTSC: PLL reconfig (K written, `locked` drops), C64 reset, 32.73 MHz, READY, PRG | 2 s / 4 min, 15 checks |
| disk | D64 picked (0x008A) at the prompt, G64 built by c64_media in PSRAM == `sim/gcr_ref.py`, autostart LOAD"*",8,1 + RUN, signature | 5 s / 16 min, 9 checks; signature 4.2 s after the mount |
| g64 | the same program as a G64: copied byte for byte into PSRAM | 5 s / 16 min, 9 checks |
| dboot | disk already in the datatable at boot (persisted disk, boot scan) | 4.4 s / 15 min, 6 checks |
| wb | program SAVEs "OUT" over IEC; the D64 held by the APF model must hold file, directory entry and BAM | 9 s / 25 min, 15 checks; flush 0.23 s after SAVE returns |
| d81 | the same disk as D81 (1581) | 5 s / 13 min, 9 checks |

`gen_disk.py` writes the images and programs (`work/disk/*.hex`, `disk.vh`). The APF model also serves
Dataslot Write (0x0184): it reads the core's write buffer over the bridge and updates the slot's file.

`+screen=1` prints the C64 screen text once per simulated second (useful while a LOAD runs).
c1581_drv.sv is copied with T65's open `rdy/abort_n/nmi_n/so_n` tied to 1: they rely on VHDL port defaults
that Verilator does not apply (without it the 1581 CPU is halted and LOAD hangs at SEARCHING FOR *).
