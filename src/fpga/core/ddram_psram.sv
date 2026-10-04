//
// ddram_psram.sv - MiSTer DDRAM port on the Pocket's PSRAM (cram0), plus a byte port
//
// C64_MiSTer's 1541 reads its G64 image through MiSTer's DDRAM interface (64-bit
// words, read bursts). Here each 64-bit word is four 16-bit PSRAM accesses through
// agg23's async psram controller. The loader port (c64_media) writes images and
// reads G64 headers; while it has a request pending the drives see DDRAM_BUSY.
//
// DDRAM_ADDR is in 64-bit words from 0x06000000 (drive 8) / 0x06040000 (drive 9),
// so PSRAM byte address = {DDRAM_ADDR[18:0], 3'b000}: 2 MB per drive.
// Byte order: byte n of a 64-bit word is DDRAM_DOUT[8n+7:8n] (little endian, as the
// ARM writes it on MiSTer); in a 16-bit PSRAM word the even byte is the low byte.
//

`default_nettype none

module ddram_psram #(
	parameter real CLOCK_SPEED = 33.0   // MHz, the fastest clk_sys (NTSC)
) (
	input  wire        clk,
	input  wire        reset,

	// MiSTer DDRAM port
	output wire        DDRAM_BUSY,
	input  wire  [7:0] DDRAM_BURSTCNT,
	input  wire [28:0] DDRAM_ADDR,
	output reg  [63:0] DDRAM_DOUT,
	output reg         DDRAM_DOUT_READY,
	input  wire        DDRAM_RD,
	input  wire        DDRAM_WE,
	input  wire [63:0] DDRAM_DIN,
	input  wire  [7:0] DDRAM_BE,

	// loader port: one byte write, or one 16-bit read of the word holding ld_addr
	input  wire        ld_start,        // one-clock pulse; wait for ld_ack before the next
	input  wire        ld_we,
	input  wire [21:0] ld_addr,         // byte address
	input  wire  [7:0] ld_wdata,
	output reg  [15:0] ld_rdata,
	output reg         ld_ack,          // one-clock pulse

	// PSRAM pins
	output wire [21:16] cram_a,
	inout  wire [15:0] cram_dq,
	input  wire        cram_wait,
	output wire        cram_clk,
	output wire        cram_adv_n,
	output wire        cram_cre,
	output wire        cram_ce0_n,
	output wire        cram_ce1_n,
	output wire        cram_oe_n,
	output wire        cram_we_n,
	output wire        cram_ub_n,
	output wire        cram_lb_n
);

reg  [21:0] p_addr;          // 16-bit word address
reg  [15:0] p_wdata;
reg         p_wr_hi, p_wr_lo;
reg         p_write, p_read;
wire        p_busy, p_avail;
wire [15:0] p_q;

psram #(.CLOCK_SPEED(CLOCK_SPEED)) psram (
	.clk             ( clk ),
	.bank_sel        ( 1'b0 ),
	.addr            ( p_addr ),
	.write_en        ( p_write ),
	.data_in         ( p_wdata ),
	.write_high_byte ( p_wr_hi ),
	.write_low_byte  ( p_wr_lo ),
	.read_en         ( p_read ),
	.read_avail      ( p_avail ),
	.data_out        ( p_q ),
	.busy            ( p_busy ),
	.cram_a          ( cram_a ),
	.cram_dq         ( cram_dq ),
	.cram_wait       ( cram_wait ),
	.cram_clk        ( cram_clk ),
	.cram_adv_n      ( cram_adv_n ),
	.cram_cre        ( cram_cre ),
	.cram_ce0_n      ( cram_ce0_n ),
	.cram_ce1_n      ( cram_ce1_n ),
	.cram_oe_n       ( cram_oe_n ),
	.cram_we_n       ( cram_we_n ),
	.cram_ub_n       ( cram_ub_n ),
	.cram_lb_n       ( cram_lb_n )
);

localparam [2:0] S_IDLE = 3'd0, S_RD = 3'd1, S_RD_WAIT = 3'd2, S_WR = 3'd3, S_WR_WAIT = 3'd4,
                 S_LD = 3'd5, S_LD_WAIT = 3'd6;

reg  [2:0] state = S_IDLE;
reg [18:0] qaddr;            // 64-bit word index within the 4 MB window
reg  [7:0] remaining;        // read burst words left
reg  [1:0] lane;             // 16-bit lane of the current 64-bit word
reg [63:0] wdata;
reg  [7:0] be;
reg        issued;           // the PSRAM access for this lane has been started

reg         ld_pending = 1'b0;
reg         ld_we_r;
reg  [21:0] ld_addr_r;
reg   [7:0] ld_wdata_r;

// a request is accepted on a clock where RD/WE is high and BUSY is low
assign DDRAM_BUSY = (state != S_IDLE) || ld_pending || ld_start;

always @(posedge clk) begin
	p_read <= 1'b0;
	p_write <= 1'b0;
	DDRAM_DOUT_READY <= 1'b0;
	ld_ack <= 1'b0;

	if (ld_start) begin
		ld_pending <= 1'b1;
		ld_we_r <= ld_we;
		ld_addr_r <= ld_addr;
		ld_wdata_r <= ld_wdata;
	end

	if (reset) begin
		state <= S_IDLE;
		ld_pending <= 1'b0;
	end else case (state)
	S_IDLE: begin
		issued <= 1'b0;
		lane <= 2'd0;
		if (ld_pending) begin
			state <= S_LD;
		end else if (DDRAM_RD) begin
			qaddr <= DDRAM_ADDR[18:0];
			remaining <= (DDRAM_BURSTCNT == 8'd0) ? 8'd1 : DDRAM_BURSTCNT;
			state <= S_RD;
		end else if (DDRAM_WE) begin
			qaddr <= DDRAM_ADDR[18:0];
			wdata <= DDRAM_DIN;
			be <= DDRAM_BE;
			state <= S_WR;
		end
	end

	// ---- read burst: 4 PSRAM reads per 64-bit word ----
	S_RD: if (!p_busy && !p_read) begin
		p_addr <= {1'b0, qaddr, lane};
		p_read <= 1'b1;
		state <= S_RD_WAIT;
	end

	S_RD_WAIT: if (p_avail) begin
		DDRAM_DOUT[lane*16 +: 16] <= p_q;
		lane <= lane + 2'd1;
		if (lane == 2'd3) begin
			DDRAM_DOUT_READY <= 1'b1;
			qaddr <= qaddr + 19'd1;
			remaining <= remaining - 8'd1;
			state <= (remaining == 8'd1) ? S_IDLE : S_RD;
		end else
			state <= S_RD;
	end

	// ---- write: lanes with no byte enabled are skipped ----
	S_WR: if (!p_busy && !p_write) begin
		if (be[lane*2 +: 2] == 2'b00) begin
			lane <= lane + 2'd1;
			if (lane == 2'd3) state <= S_IDLE;
		end else begin
			p_addr <= {1'b0, qaddr, lane};
			p_wdata <= wdata[lane*16 +: 16];
			p_wr_lo <= be[lane*2];
			p_wr_hi <= be[lane*2 + 1];
			p_write <= 1'b1;
			state <= S_WR_WAIT;
		end
	end

	S_WR_WAIT: if (!p_busy && !p_write) begin
		lane <= lane + 2'd1;
		state <= (lane == 2'd3) ? S_IDLE : S_WR;
	end

	// ---- loader ----
	S_LD: if (!p_busy && !p_read && !p_write) begin
		p_addr <= {1'b0, ld_addr_r[21:1]};
		if (ld_we_r) begin
			p_wdata <= {ld_wdata_r, ld_wdata_r};
			p_wr_lo <= ~ld_addr_r[0];
			p_wr_hi <= ld_addr_r[0];
			p_write <= 1'b1;
		end else
			p_read <= 1'b1;
		state <= S_LD_WAIT;
	end

	S_LD_WAIT: begin
		if (p_avail) ld_rdata <= p_q;
		if (!p_busy && !p_read && !p_write) begin
			ld_ack <= 1'b1;
			ld_pending <= 1'b0;
			state <= S_IDLE;
		end
	end

	default: state <= S_IDLE;
	endcase
end

endmodule

`default_nettype wire
