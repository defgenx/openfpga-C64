// Behavioural 16-bit SDR SDRAM, 4 banks x 8192 rows x 1024 columns (64 MB, the Pocket's chip).
// Honours ACTIVE / READ / WRITE / PRECHARGE / AUTO REFRESH / LOAD MODE, the CAS latency and
// burst length programmed in the mode register, DQM (write mask; read mask with a 2 clock
// latency) and auto-precharge. It checks the protocol rules a controller can break without the
// simulation noticing otherwise (see `err` counter): commands before the mode register is
// loaded, READ/WRITE to a closed bank, ACTIVE to an open bank, tRCD < 2 clocks,
// REFRESH with a bank open.
`timescale 1ps/1ps

module sdram_model (
	input  wire        clk,
	input  wire        cke,
	input  wire        cs_n,
	input  wire        ras_n,
	input  wire        cas_n,
	input  wire        we_n,
	input  wire [1:0]  ba,
	input  wire [12:0] a,
	input  wire [1:0]  dqm,
	inout  wire [15:0] dq
);
	reg [15:0] mem [0:(1<<25)-1];
	integer i;
	initial for (i = 0; i < (1<<25); i = i + 1) mem[i] = 16'h0000;

	// protocol bookkeeping
	integer err = 0;
	reg trace_wr = 0;
	integer n_active = 0, n_read = 0, n_write = 0, n_refresh = 0, n_pre = 0;
	reg        mode_loaded = 0;
	reg [12:0] mode = 0;
	wire [2:0] cl = mode[6:4];
	wire [2:0] bl = mode[2:0];
	wire       wburst_off = mode[9];

	reg        open_b [0:3];
	reg [12:0] row_b  [0:3];
	integer    act_clk [0:3];
	integer    clkn = 0;

	// read pipeline (data is emitted CL edges after the READ command)
	reg        p_v [0:7];
	reg [15:0] p_d [0:7];
	reg [1:0]  dq_h1 = 0, dq_h2 = 0;
	reg [15:0] dq_out = 0;
	reg        dq_oe = 0;
	assign dq = dq_oe ? dq_out : 16'hzzzz;

	// burst continuation state
	integer rd_left = 0, rd_col = 0, rd_bank = 0;
	integer wr_left = 0, wr_col = 0, wr_bank = 0;
	reg rd_ap = 0, wr_ap = 0;

	initial for (i = 0; i < 4; i = i + 1) begin open_b[i] = 0; row_b[i] = 0; act_clk[i] = -100; end
	initial for (i = 0; i < 8; i = i + 1) begin p_v[i] = 0; p_d[i] = 0; end

	function [24:0] widx(input [1:0] b, input [12:0] r, input [9:0] c);
		widx = {b, r, c};
	endfunction

	// byte access with the controller's address map (25 bit byte address of sdram.v):
	// [24] byte select, [23] col[8], [22:21] bank, [20:8] row, [7:0] col[7:0]
	function [24:0] byte2w(input [24:0] ad);
		byte2w = {ad[22:21], ad[20:8], 1'b0, ad[23], ad[7:0]};
	endfunction
	function [7:0] peek8(input [24:0] ad);
		reg [15:0] w;
		begin
			w = mem[byte2w(ad)];
			peek8 = ad[24] ? w[15:8] : w[7:0];
		end
	endfunction
	task poke8(input [24:0] ad, input [7:0] d);
		reg [15:0] w;
		begin
			w = mem[byte2w(ad)];
			if (ad[24]) w[15:8] = d; else w[7:0] = d;
			mem[byte2w(ad)] = w;
		end
	endtask

	wire [2:0] cmd = {ras_n, cas_n, we_n};
	integer k;
	reg [15:0] w;
	reg [9:0] col;

	always @(posedge clk) begin
		clkn <= clkn + 1;
		dq_h1 <= dqm;
		dq_h2 <= dq_h1;

		// emit read data
		dq_oe <= p_v[0];
		if (p_v[0]) dq_out <= {dq_h2[1] ? 8'hzz : p_d[0][15:8], dq_h2[0] ? 8'hzz : p_d[0][7:0]};
		for (k = 0; k < 7; k = k + 1) begin p_v[k] <= p_v[k+1]; p_d[k] <= p_d[k+1]; end
		p_v[7] <= 0;

		if (cke && !cs_n) begin
			case (cmd)
			3'b000: begin // LOAD MODE
				for (k = 0; k < 4; k = k + 1) if (open_b[k]) begin err = err + 1; $display("[%0t] SDRAM ERR: LOAD MODE with bank %0d open", $time, k); end
				mode <= a; mode_loaded <= 1;
				$display("[%0t] SDRAM: mode register = %h (CL=%0d BL=%0d wr-burst-off=%0d)", $time, a, a[6:4], a[2:0], a[9]);
			end
			3'b001: begin // AUTO REFRESH
				n_refresh = n_refresh + 1;
				for (k = 0; k < 4; k = k + 1) if (open_b[k]) begin err = err + 1; $display("[%0t] SDRAM ERR: REFRESH with bank %0d open", $time, k); end
			end
			3'b010: begin // PRECHARGE
				n_pre = n_pre + 1;
				if (a[10]) for (k = 0; k < 4; k = k + 1) open_b[k] <= 0;
				else open_b[ba] <= 0;
			end
			3'b011: begin // ACTIVE
				n_active = n_active + 1;
				if (!mode_loaded) begin err = err + 1; $display("[%0t] SDRAM ERR: ACTIVE before mode register set", $time); end
				if (open_b[ba]) begin err = err + 1; $display("[%0t] SDRAM ERR: ACTIVE to open bank %0d", $time, ba); end
				open_b[ba] <= 1; row_b[ba] <= a; act_clk[ba] = clkn;
			end
			3'b101: begin // READ
				n_read = n_read + 1;
				if (!mode_loaded) begin err = err + 1; $display("[%0t] SDRAM ERR: READ before mode register set", $time); end
				if (!open_b[ba]) begin err = err + 1; $display("[%0t] SDRAM ERR: READ to closed bank %0d", $time, ba); end
				else if (clkn - act_clk[ba] < 2) begin err = err + 1; $display("[%0t] SDRAM ERR: tRCD violated (%0d clk)", $time, clkn - act_clk[ba]); end
				col = a[9:0];
				p_v[cl-1] <= 1; p_d[cl-1] <= mem[widx(ba, row_b[ba], col)];
				rd_left <= (bl == 0) ? 0 : (1 << bl) - 1; rd_col <= col + 1; rd_bank <= ba; rd_ap <= a[10];
				if (a[10]) open_b[ba] <= 0;
			end
			3'b100: begin // WRITE
				n_write = n_write + 1;
				if (!mode_loaded) begin err = err + 1; $display("[%0t] SDRAM ERR: WRITE before mode register set", $time); end
				if (!open_b[ba]) begin err = err + 1; $display("[%0t] SDRAM ERR: WRITE to closed bank %0d", $time, ba); end
				else if (clkn - act_clk[ba] < 2) begin err = err + 1; $display("[%0t] SDRAM ERR: tRCD violated on write (%0d clk)", $time, clkn - act_clk[ba]); end
				col = a[9:0];
				w = mem[widx(ba, row_b[ba], col)];
				if (!dqm[0]) w[7:0]  = dq[7:0];
				if (!dqm[1]) w[15:8] = dq[15:8];
				mem[widx(ba, row_b[ba], col)] = w;
				if (trace_wr && row_b[ba] == 13'h008 && ba == 0 && col[8] == 0 && col[7:0] <= 8'h30)
					$display("[%0t] SDRAM WR byte addr %h <= %h (dqm=%b)", $time, {1'b0, col[8], ba, row_b[ba], col[7:0]}, dqm[0] ? dq[15:8] : dq[7:0], dqm);
				if (a[10]) open_b[ba] <= 0;
			end
			3'b110: ; // BURST TERMINATE
			default: ;
			endcase
		end
		// burst continuation for reads
		if (rd_left > 0 && cmd == 3'b111) begin
			p_v[cl-1] <= 1; p_d[cl-1] <= mem[widx(rd_bank[1:0], row_b[rd_bank], rd_col[9:0])];
			rd_col <= rd_col + 1; rd_left <= rd_left - 1;
		end
	end
endmodule
