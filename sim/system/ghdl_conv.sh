#!/bin/sh
# runs inside the ghdl container, cwd = work/vhdl
set -e
FILES="T65_Pack.vhd T65_ALU.vhd T65_MCode.vhd T65.vhd cpu_6510.vhd video_vicII_656x.vhd video_sync.vhd fpga64_rgbcolor.vhd fpga64_keyboard.vhd spram.vhd fpga64_buslogic.vhd fpga64_sid_iec.vhd"
ghdl -a --std=08 -fsynopsys -fexplicit -frelaxed $FILES
ghdl synth --std=08 -fsynopsys -fexplicit -frelaxed --out=verilog $FILES -e fpga64_sid_iec > ../fpga64.v
ghdl synth --std=08 -fsynopsys -fexplicit -frelaxed --out=verilog $FILES -e video_sync > ../video_sync.v
