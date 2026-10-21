#!/bin/sh
# runs inside the ghdl container, cwd = work/vhdl
set -e
FILES="T65_Pack.vhd T65_ALU.vhd T65_MCode.vhd T65.vhd cpu_6510.vhd video_vicII_656x.vhd video_sync.vhd fpga64_rgbcolor.vhd fpga64_keyboard.vhd spram.vhd fpga64_buslogic.vhd fpga64_sid_iec.vhd"
ghdl -a --std=08 -fsynopsys -fexplicit -frelaxed $FILES
ghdl synth --std=08 -fsynopsys -fexplicit -frelaxed --out=verilog $FILES -e fpga64_sid_iec > ../fpga64.v
ghdl synth --std=08 -fsynopsys -fexplicit -frelaxed --out=verilog $FILES -e video_sync > ../video_sync.v
# the 1541 / 1581 CPU and VIAs (Verilog instantiates the VHDL entities directly)
ghdl -a --std=08 -fsynopsys -fexplicit -frelaxed iecdrv_via6522.vhd
ghdl synth --std=08 -fsynopsys -fexplicit -frelaxed --out=verilog $FILES -e T65 > ../t65_drv.v
ghdl synth --std=08 -fsynopsys -fexplicit -frelaxed --out=verilog iecdrv_via6522.vhd -e iecdrv_via6522 > ../via_drv.v
