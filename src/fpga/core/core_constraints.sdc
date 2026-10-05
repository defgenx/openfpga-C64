#
# user core constraints
#
# pll_c64 outputs (derive_pll_clocks): [0] clk48, [1] clk64, [2] clk_sys, [3] clk_sys_90. They share
# one VCO, so they stay in one clock group with the clocks derived from clk64.
#

set PLL_OUT "ic|pll|altera_pll_i|*"
set CLK64   [get_pins -compatibility_mode "$PLL_OUT\[1\].*|divclk"]

# SDRAM: sdram.v drives dram_clk as an inverted clk64 through a DDIO register,
# as on MiSTer, so the pin is an inverted copy of clk64
create_generated_clock -name dram_clk_pin -source $CLK64 -invert [get_ports {dram_clk}]
set_input_delay  -clock dram_clk_pin -max 6.4 [get_ports {dram_dq[*]}]
set_input_delay  -clock dram_clk_pin -min 3.2 [get_ports {dram_dq[*]}]
set_output_delay -clock dram_clk_pin -max 1.5 [get_ports {dram_dq[*] dram_a[*] dram_ba[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n}]
set_output_delay -clock dram_clk_pin -min -0.8 [get_ports {dram_dq[*] dram_a[*] dram_ba[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n}]
# sdram.v samples read data three clk64 cycles after the READ command, one cycle
# after the edge the analyser picks by default
set_multicycle_path -from [get_clocks dram_clk_pin] -to [get_clocks "$PLL_OUT\[1\].*|divclk"] -setup 2
set_multicycle_path -from [get_clocks dram_clk_pin] -to [get_clocks "$PLL_OUT\[1\].*|divclk"] -hold 1

# PSRAM (cram0) is asynchronous: ddram_psram holds address and data for whole clk_sys cycles
set_false_path -to   [get_ports {cram0_*}]
set_false_path -from [get_ports {cram0_dq[*]}]

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group [get_clocks "$PLL_OUT dram_clk_pin"]
