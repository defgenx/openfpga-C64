# Simulation of the Pocket-specific modules (Icarus Verilog, nvc for the VIC-II)
CORE = ../src/fpga/core
C64  = ../src/fpga/C64_MiSTer/rtl

all: gcr media video hid autostart osk

# gcr_synth byte-exact against Main_MiSTer's D64 -> GCR; gcr_decode at any bit rotation
gcr:
	python3 run_gcr.py

# c64_media + ddram_psram: PRG streaming, D64 / G64 / D81 mount and write-back
media:
	python3 run_media.py

# c64_video fed with C64_MiSTer's own VIC-II and video_sync (traced with nvc)
video: vic/trace_0.txt vic/trace_1.txt video/video_tb.vvp
	for n in 0 1; do for b in 1 0; do \
		vvp -n video/video_tb.vvp +trace=vic/trace_$$n.txt +ntsc=$$n +borders=$$b +ppm=video/frame_n$${n}_b$${b}.ppm | grep -v finish; \
	done; done
	python3 ppm2png.py video/frame_n0_b1.ppm video/frame_pal.png

video/video_tb.vvp: video_tb.sv $(CORE)/c64_video.sv
	mkdir -p video
	iverilog -g2012 -o $@ video_tb.sv $(CORE)/c64_video.sv

vic/trace_%.txt: vic/tb_vic.vhd
	cd vic && nvc -a ../$(C64)/video_vicII_656x.vhd ../$(C64)/video_sync.vhd tb_vic.vhd -e tb_vic -gNTSC=$* -gTRACE=1 -r 2>/dev/null | grep "^frame" | tail -1
	mv vic/trace.txt $@

# hid_c64: make/break events and mouse reports
hid:
	iverilog -g2012 -o hid_tb.vvp hid_tb.sv $(CORE)/hid_c64.sv
	vvp -n hid_tb.vvp | grep -v finish
	rm -f hid_tb.vvp

# autostart: LOAD/RUN typed at the prompt only
autostart:
	iverilog -g2012 -o autostart_tb.vvp autostart_tb.sv $(CORE)/autostart.sv
	vvp -n autostart_tb.vvp | grep -v finish
	rm -f autostart_tb.vvp

# on-screen keyboard and loading screen rendered to sim/video/*.png (docs/osk.png)
osk:
	mkdir -p video
	iverilog -g2012 -I$(CORE) -o osk_tb.vvp osk_tb.sv $(CORE)/osk.sv
	vvp -n osk_tb.vvp | grep -v finish
	rm -f osk_tb.vvp
	python3 ppm2png.py video/osk_frame.ppm video/osk_frame.png
	python3 ppm2png.py video/load_frame.ppm video/load_frame.png

clean:
	rm -rf gcr media video vic/trace_*.txt vic/*.ppm vic/work __pycache__

.PHONY: all gcr media video hid autostart osk clean
