# Full-system simulation (Verilator)

`core_top` (the real Pocket top: `core_bridge_cmd`, `c64_media`, `ddram_psram`, `c64_top`,
`autostart`, `hid_c64`, video) with the real C64 machine from C64_MiSTer, an Analogue APF host/target
model and a 16-bit SDR SDRAM model. It exercises the PRG / T64 / CRT / TAP path that `sim/media_tb.sv`
only covers against a model of the C64 side.

    make -C sim/system            # build (first time: converts the VHDL in Docker) and run all tests
    make -C sim/system prg        # boot + PRG only (also: boot, t64, crt, tap)
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
| pll_c64 / pll_cfg | stub: clk_sys 31.526 MHz (31720 ps), clk64 exactly 2x with coinciding rising edges, locked at 20 us, reconfiguration ignored (PAL only) |
| mf_datatable, altddio_out, scfifo | behavioural models (`stubs.sv`) |
| SDRAM chip | `sdram_model.sv`: 4 banks x 8192 x 1024 x 16, CL / BL from the mode register, DQM, auto-precharge; counts protocol errors (tRCD, closed bank, open-bank ACTIVE, mode register not set); `peek8` backdoor uses the controller's address map |
| iec_drive | **stubbed idle** (IEC released, `disk_ready` = 1 as c1541_multi reports with the drive in reset). The drive is not part of these tests |
| sound_i2s | stubbed (no audio) |
| PSRAM (cram0) | real `ddram_psram`/`psram`, but no chip model: pins float, nothing is read or written without a disk |
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
