# Full-system simulation of the Pocket core (core_top) in Verilator.
#   make            build and run all tests
#   make prg|t64|crt|tap|boot   one test (each starts from power-on)
#   make TRACE=1 ...        build with FST tracing (use +dump=<from_us>,<to_us> via ARGS)
# Needs: verilator >= 5, python3, docker (hdlc/ghdl:yosys, only to convert the VHDL).
SRC  = ../../src/fpga
CORE = $(SRC)/core
C64  = $(SRC)/C64_MiSTer/rtl
W    = work
OBJ  = obj
MEDIA = $(CORE)/c64_media.sv
ARGS ?=

VERILOG = \
  $(CORE)/core_top.v $(CORE)/core_bridge_cmd.v $(MEDIA) $(CORE)/c64_top.sv \
  $(CORE)/ddram_psram.sv $(CORE)/psram.sv $(CORE)/gcr_synth.sv $(CORE)/gcr_decode.sv \
  $(CORE)/hid_c64.sv $(CORE)/autostart.sv $(CORE)/osk.sv $(CORE)/c64_video.sv \
  $(SRC)/apf/common.v \
  $(C64)/sdram.v $(C64)/cartridge.v $(C64)/reu.v $(C64)/mos6526.v $(C64)/c1351.v $(C64)/c1530.sv \
  $(C64)/tape_subsystem.sv $(C64)/tap_scanner.sv $(C64)/tap_time_map.sv $(C64)/tape_counter.sv \
  $(C64)/rtcF83.sv $(C64)/drv_overlay.sv $(C64)/am29f040.sv \
  $(W)/sid/sid_top.sv $(W)/sid/sid_voice.sv $(W)/sid/sid_tables.sv $(W)/sid/sid_filter.sv \
  $(W)/sid/sid_envelope.sv $(W)/sid/sid_dac.sv \
  $(W)/fpga64_conv.v $(W)/video_sync.v $(wildcard $(W)/dprom_*.v) \
  stubs.sv sdram_model.sv tb_system.sv

VFLAGS = --binary --timing --top-module tb -Mdir $(W)/$(OBJ) -o sim_system \
  -Wno-fatal -Wno-lint -Wno-style -Wno-DECLFILENAME -Wno-WIDTH -Wno-PINMISSING -Wno-UNOPTFLAT -Wno-PROCASSWIRE \
  -I$(CORE) --x-assign fast --x-initial fast -O2 -j 8 \
  --timescale 1ps/1ps
ifdef TRACE
VFLAGS += --trace-fst
endif

.PHONY: all run boot prg t64 crt tap clean vhdl
all: run

$(W)/vhdl.stamp: gen_sid.py gen_vhdl.py ghdl_conv.sh post_ghdl.py $(wildcard $(C64)/*.vhd) $(wildcard $(C64)/t65/*.vhd)
	python3 gen_vhdl.py
	python3 gen_sid.py
	./ghdl_docker.sh sh ../../ghdl_conv.sh 2> $(W)/ghdl.log || { cat $(W)/ghdl.log; exit 1; }
	python3 post_ghdl.py
	touch $@

vhdl: $(W)/vhdl.stamp

$(W)/$(OBJ)/sim_system: $(W)/vhdl.stamp $(VERILOG) $(wildcard $(CORE)/*.svh)
	verilator $(VFLAGS) $(VERILOG)

run: $(W)/$(OBJ)/sim_system
	$(W)/$(OBJ)/sim_system $(ARGS)

boot prg t64 crt tap: $(W)/$(OBJ)/sim_system
	$(W)/$(OBJ)/sim_system +test=$@ $(ARGS)

clean:
	rm -rf $(W)/obj $(W)/vhdl.stamp
