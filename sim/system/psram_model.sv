// Behavioural model of the Pocket's cram0: a 16-bit asynchronous CellularRAM with a multiplexed
// address (A[21:16] pins + DQ[15:0] while ADV# is low), as driven by psram.sv (agg23).
// 4M x 16 (8 MB) on CE0#. Flags timing violations against the limits psram.sv is written for
// (the parameters at the top of psram.sv, which are the CellularRAM async timings):
//   t_vp  ADV# low pulse >= 5 ns       t_avs address setup before ADV# high >= 5 ns
//   t_avh address hold after ADV# high >= 2 ns   t_cvs CE# low before ADV# high >= 7 ns
//   write: t_wp WE# low >= 45 ns, t_dw data setup before WE# high >= 20 ns, t_aw >= 70 ns from ADV# low
//   read:  data valid 70 ns after ADV# low and 20 ns after OE# low; before that DQ carries
//          garbage, so a controller that samples early reads wrong data (and `err` counts it)
// `err` counts violations; peek16 / peek8 / poke8 are backdoors (byte address, little endian).
`timescale 1ps/1ps

module psram_model (
	input  wire [21:16] a,
	inout  wire [15:0]  dq,
	input  wire         clk,
	input  wire         adv_n,
	input  wire         cre,
	input  wire         ce0_n,
	input  wire         ce1_n,
	input  wire         oe_n,
	input  wire         we_n,
	input  wire         ub_n,
	input  wire         lb_n,
	output wire         wait_o
);
	assign wait_o = 1'b0;

	reg [15:0] mem [0:(1<<22)-1];
	integer i;
	initial for (i = 0; i < (1<<22); i = i + 1) mem[i] = 16'h0000;

	integer err = 0;
	integer n_rd = 0, n_wr = 0;

	function [15:0] peek16(input [21:0] w);
		peek16 = mem[w];
	endfunction
	function [7:0] peek8(input [22:0] b);
		reg [15:0] w;
		begin w = mem[b[22:1]]; peek8 = b[0] ? w[15:8] : w[7:0]; end
	endfunction
	task poke8(input [22:0] b, input [7:0] d);
		reg [15:0] w;
		begin
			w = mem[b[22:1]];
			if (b[0]) w[15:8] = d; else w[7:0] = d;
			mem[b[22:1]] = w;
		end
	endtask

	realtime t_adv_fall, t_adv_rise, t_ce_fall, t_oe_fall, t_we_fall, t_dq_chg, t_a_chg, t_addr_hold;
	reg [21:0] addr_l;
	reg        have_addr = 0;

	// address / data activity (for setup and hold checks)
	always @(dq) t_dq_chg = $realtime;
	always @(a)  t_a_chg  = $realtime;
	always @(dq or a) if (have_addr && (adv_n == 1'b1) && !ce0_n && ($realtime - t_adv_rise) < 2000.0) begin
		// address bus moved less than t_avh after ADV# went high
		err = err + 1; $display("[%0t] PSRAM ERR: address changed %0.1f ns after ADV# high (t_avh 2 ns)", $time, ($realtime - t_adv_rise) / 1000.0);
	end

	always @(negedge ce0_n) t_ce_fall = $realtime;
	always @(negedge adv_n) begin
		t_adv_fall = $realtime;
		if (ce0_n) begin err = err + 1; $display("[%0t] PSRAM ERR: ADV# low with CE# high", $time); end
	end
	always @(posedge adv_n) if (!ce0_n) begin
		t_adv_rise = $realtime;
		if ($realtime - t_adv_fall < 5000.0) begin err = err + 1; $display("[%0t] PSRAM ERR: ADV# pulse %0.1f ns < 5 (t_vp)", $time, ($realtime - t_adv_fall) / 1000.0); end
		if ($realtime - t_dq_chg < 5000.0 || $realtime - t_a_chg < 5000.0) begin err = err + 1; $display("[%0t] PSRAM ERR: address setup < 5 ns (t_avs)", $time); end
		if ($realtime - t_ce_fall < 7000.0) begin err = err + 1; $display("[%0t] PSRAM ERR: CE# low only %0.1f ns before ADV# high (t_cvs 7)", $time, ($realtime - t_ce_fall) / 1000.0); end
		addr_l = {a, dq};
		have_addr = 1;
	end
	// write: the cycle ends on the first rising edge of WE# or CE#. The controller releases the
	// bus and the byte enables on that same clock edge, so the data and the masks are tracked
	// while WE# and CE# are low and used when the cycle ends.
	reg        wr_open = 0;
	reg [15:0] wdata_l;
	reg  [1:0] wmask_l;
	realtime   t_wdata;
	always @(negedge we_n) if (!ce0_n) begin t_we_fall = $realtime; wr_open = 1; end
	always @(negedge ce0_n) if (!we_n) begin t_we_fall = $realtime; wr_open = 1; end
	always @(dq) if (!ce0_n && !we_n) begin wdata_l = dq; t_wdata = $realtime; end
	always @(ub_n or lb_n or ce0_n or we_n) if (!ce0_n && !we_n) wmask_l = {ub_n, lb_n};
	always @(posedge we_n or posedge ce0_n) if (wr_open) begin : wr
		reg [15:0] w;
		wr_open = 0;
		n_wr = n_wr + 1;
		if ($realtime - t_we_fall < 45000.0) begin err = err + 1; $display("[%0t] PSRAM ERR: WE# pulse %0.1f ns < 45 (t_wp)", $time, ($realtime - t_we_fall) / 1000.0); end
		if ($realtime - t_wdata < 20000.0) begin err = err + 1; $display("[%0t] PSRAM ERR: write data setup %0.1f ns < 20 (t_dw)", $time, ($realtime - t_wdata) / 1000.0); end
		if ($realtime - t_adv_fall < 70000.0) begin err = err + 1; $display("[%0t] PSRAM ERR: write ended %0.1f ns after ADV# low < 70 (t_aw)", $time, ($realtime - t_adv_fall) / 1000.0); end
		w = mem[addr_l];
		if (!wmask_l[0]) w[7:0]  = wdata_l[7:0];
		if (!wmask_l[1]) w[15:8] = wdata_l[15:8];
		mem[addr_l] = w;
	end

	// read: DQ driven while CE# and OE# are low and WE# is high
	reg        rd_valid = 0;
	reg [15:0] rd_data;
	wire       rd_drive = !ce0_n && !oe_n && we_n && have_addr;
	assign dq = rd_drive ? (rd_valid ? rd_data : ~mem[addr_l] ^ 16'h5A5A) : 16'hzzzz;

	always @(negedge oe_n) if (!ce0_n && we_n && have_addr) begin : rd
		realtime t_ok, t_now;
		t_oe_fall = $realtime;
		rd_valid = 0;
		rd_data = mem[addr_l];
		n_rd = n_rd + 1;
		// data valid at max(ADV# low + 70 ns, OE# low + 20 ns)
		t_ok = t_adv_fall + 70000.0;
		if (t_oe_fall + 20000.0 > t_ok) t_ok = t_oe_fall + 20000.0;
		if (t_ok > $realtime) #(t_ok - $realtime);
		if (!oe_n && !ce0_n) rd_valid = 1;
	end
	always @(posedge oe_n) begin
		if (rd_valid == 0 && !ce0_n && have_addr) begin
			// OE# released (read ended) before the data was valid: the controller sampled garbage
			err = err + 1; $display("[%0t] PSRAM ERR: read ended %0.1f ns after ADV# low / %0.1f ns after OE# low (need 70 / 20)", $time,
				($realtime - t_adv_fall) / 1000.0, ($realtime - t_oe_fall) / 1000.0);
		end
		rd_valid = 0;
	end

	always @(negedge ce0_n) if (!ce1_n) begin err = err + 1; $display("[%0t] PSRAM ERR: both chip enables low", $time); end
	always @(posedge ce0_n) begin have_addr = 0; end
endmodule
