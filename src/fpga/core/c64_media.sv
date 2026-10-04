//
// c64_media.sv - files and disk images over APF target commands
//
// Every data slot is "deferload": this module pulls files with Dataslot Read and
// writes disks back with Dataslot Write, so all transfers are paced by the core.
// It stands in for what MiSTer's ARM does for the C64 core:
//   - PRG / CRT / TAP / System ROM are streamed into c64_top's ioctl download port;
//   - G64 images are copied into PSRAM, D64 images are converted to G64 there
//     (gcr_synth), where the 1541s read them through the DDRAM port;
//   - D81 sectors are served to the 1581 on sd_rd / sd_wr;
//   - a 1541 track flushed on sd_wr is written to the G64 file, or decoded back
//     into D64 sectors (gcr_decode).
// See docs/architecture.md for the sequences.
//
// Bridge map:
//   0x1000_0000-0x1000_1FFF  read buffer  (APF writes into it)
//   0x1000_4000-0x1000_5FFF  write buffer (APF reads from it)
//

`default_nettype none

module c64_media (
	input  wire        clk_74a,
	input  wire        clk_sys,

	// APF bridge (clk_74a)
	input  wire [31:0] bridge_addr,
	input  wire        bridge_wr,
	input  wire [31:0] bridge_wr_data,
	output reg  [31:0] bridge_rd_data,

	// target commands (clk_74a)
	output reg         target_dataslot_read,
	output reg         target_dataslot_write,
	output reg  [15:0] target_dataslot_id,
	output reg  [31:0] target_dataslot_slotoffset,
	output reg  [31:0] target_dataslot_bridgeaddr,
	output reg  [31:0] target_dataslot_length,
	input  wire        target_dataslot_done,

	// host notifications (clk_74a)
	input  wire        dataslot_update,
	input  wire [15:0] dataslot_update_id,
	input  wire [31:0] dataslot_update_size,
	input  wire        dataslot_allcomplete,
	output reg   [9:0] datatable_addr,
	input  wire [31:0] datatable_q,

	// C64 side (clk_sys)
	output reg         ioctl_download,
	output reg   [7:0] ioctl_index,
	output reg         ioctl_wr,
	output reg  [24:0] ioctl_addr,
	output reg   [7:0] ioctl_data,
	output reg  [31:0] ioctl_file_ext,
	input  wire        ioctl_wait,

	input  wire [31:0] sd_lba[2],
	input  wire  [1:0] sd_rd,
	input  wire  [1:0] sd_wr,
	output reg   [1:0] sd_ack,
	output wire [13:0] sd_buff_addr,
	output reg   [7:0] sd_buff_dout,
	input  wire  [7:0] sd_buff_din[2],
	output reg         sd_buff_wr,
	output reg   [1:0] img_mounted,
	output reg  [31:0] img_size,
	output reg   [1:0] img_type,

	// PSRAM loader port (ddram_psram)
	output reg         ld_start,
	output reg         ld_we,
	output reg  [21:0] ld_addr,
	output reg   [7:0] ld_wdata,
	input  wire [15:0] ld_rdata,
	input  wire        ld_ack,

	output wire        busy            // a file or image is being loaded
);

// Slot ids, kept in sync with data.json
localparam [15:0] SLOT_PRG = 16'd0;
localparam [15:0] SLOT_CRT = 16'd1;
localparam [15:0] SLOT_D8  = 16'd2;
localparam [15:0] SLOT_D9  = 16'd3;
localparam [15:0] SLOT_TAP = 16'd4;
localparam [15:0] SLOT_ROM = 16'd5;

localparam [31:0] RBUF_ADDR = 32'h1000_0000;
localparam [31:0] WBUF_ADDR = 32'h1000_4000;

/* ------------------------------------------------------------------------ */
/* Buffers: one byte lane per RAM so the 32-bit bridge side and the 8-bit   */
/* C64 side infer plain dual-clock M10K blocks.                             */
/* ------------------------------------------------------------------------ */

reg [7:0] rbuf0[2048], rbuf1[2048], rbuf2[2048], rbuf3[2048];
wire      rbuf_we = bridge_wr && bridge_addr[31:13] == RBUF_ADDR[31:13];

always @(posedge clk_74a) if (rbuf_we) begin
	rbuf0[bridge_addr[12:2]] <= bridge_wr_data[31:24];
	rbuf1[bridge_addr[12:2]] <= bridge_wr_data[23:16];
	rbuf2[bridge_addr[12:2]] <= bridge_wr_data[15:8];
	rbuf3[bridge_addr[12:2]] <= bridge_wr_data[7:0];
end

reg [12:0] rbuf_raddr;
reg  [7:0] rq0, rq1, rq2, rq3;
reg  [1:0] rbuf_lane;
always @(posedge clk_sys) begin
	rq0 <= rbuf0[rbuf_raddr[12:2]];
	rq1 <= rbuf1[rbuf_raddr[12:2]];
	rq2 <= rbuf2[rbuf_raddr[12:2]];
	rq3 <= rbuf3[rbuf_raddr[12:2]];
	rbuf_lane <= rbuf_raddr[1:0];
end
// valid two clocks after rbuf_raddr changes
wire [7:0] rbuf_q = rbuf_lane == 2'd0 ? rq0 : rbuf_lane == 2'd1 ? rq1 : rbuf_lane == 2'd2 ? rq2 : rq3;

reg [7:0] wbuf0[2048], wbuf1[2048], wbuf2[2048], wbuf3[2048];
reg        wbuf_we;
reg [12:0] wbuf_waddr;
reg  [7:0] wbuf_wdata;
always @(posedge clk_sys) if (wbuf_we) begin
	case (wbuf_waddr[1:0])
		2'd0: wbuf0[wbuf_waddr[12:2]] <= wbuf_wdata;
		2'd1: wbuf1[wbuf_waddr[12:2]] <= wbuf_wdata;
		2'd2: wbuf2[wbuf_waddr[12:2]] <= wbuf_wdata;
		2'd3: wbuf3[wbuf_waddr[12:2]] <= wbuf_wdata;
	endcase
end

always @(posedge clk_74a)
	bridge_rd_data <= {wbuf0[bridge_addr[12:2]], wbuf1[bridge_addr[12:2]], wbuf2[bridge_addr[12:2]], wbuf3[bridge_addr[12:2]]};

/* ------------------------------------------------------------------------ */
/* clk_74a: slot sizes and the target command engine                        */
/* ------------------------------------------------------------------------ */

reg        boot_ready_74;
reg [31:0] size_74[6];
reg  [5:0] upd_t_74;             // toggles when a slot has a new file

reg  [5:0] dt_idx;
reg  [2:0] dt_phase;
reg        dt_scanning;
reg [15:0] dt_id;

always @(posedge clk_74a) begin
	if (dataslot_allcomplete && !boot_ready_74 && !dt_scanning) begin
		dt_scanning <= 1'b1;
		dt_idx <= 6'd0;
		dt_phase <= 3'd0;
	end

	// datatable: two words per slot, {id} then {size}; q valid 2 clocks after the address
	if (dt_scanning) begin
		dt_phase <= dt_phase + 3'd1;
		case (dt_phase)
			3'd0: datatable_addr <= {3'd0, dt_idx, 1'b0};
			3'd3: begin
				dt_id <= datatable_q[15:0];
				datatable_addr <= {3'd0, dt_idx, 1'b1};
			end
			3'd7: begin
				if (dt_id < 16'd6 && datatable_q != 0) begin
					size_74[dt_id[2:0]] <= datatable_q;
					upd_t_74[dt_id[2:0]] <= ~upd_t_74[dt_id[2:0]];
				end
				dt_idx <= dt_idx + 6'd1;
				if (dt_idx == 6'd31) begin
					dt_scanning <= 1'b0;
					boot_ready_74 <= 1'b1;
				end
			end
			default: ;
		endcase
	end

	if (dataslot_update && dataslot_update_id < 16'd6) begin
		size_74[dataslot_update_id[2:0]] <= dataslot_update_size;
		upd_t_74[dataslot_update_id[2:0]] <= ~upd_t_74[dataslot_update_id[2:0]];
	end
end

// request from clk_sys: parameters are held stable while req_t != ack_t
reg        req_t;
reg        req_write;
reg [15:0] req_slot;
reg [31:0] req_offset;
reg [31:0] req_length;
reg [31:0] req_bridgeaddr;
reg        ack_t_74;

reg  [2:0] req_t_s;
always @(posedge clk_74a) req_t_s <= {req_t_s[1:0], req_t};

localparam E_IDLE = 2'd0, E_START = 2'd1, E_WAIT_LOW = 2'd2, E_WAIT_DONE = 2'd3;
reg [1:0] estate;

always @(posedge clk_74a) begin
	target_dataslot_read  <= 1'b0;
	target_dataslot_write <= 1'b0;

	case (estate)
		E_IDLE: if (req_t_s[2] != ack_t_74) begin
			target_dataslot_id         <= req_slot;
			target_dataslot_slotoffset <= req_offset;
			target_dataslot_length     <= req_length;
			target_dataslot_bridgeaddr <= req_bridgeaddr;
			estate <= E_START;
		end
		E_START: begin
			if (req_write) target_dataslot_write <= 1'b1;
			else           target_dataslot_read  <= 1'b1;
			estate <= E_WAIT_LOW;
		end
		// done stays high from the previous command until the bridge starts this one
		E_WAIT_LOW:  if (!target_dataslot_done) estate <= E_WAIT_DONE;
		E_WAIT_DONE: if (target_dataslot_done) begin
			ack_t_74 <= req_t_s[2];
			estate <= E_IDLE;
		end
	endcase
end

/* ------------------------------------------------------------------------ */
/* clk_sys                                                                  */
/* ------------------------------------------------------------------------ */

reg [2:0] ack_t_s, boot_s;
reg [2:0] upd_s[6];
always @(posedge clk_sys) begin
	integer i;
	ack_t_s <= {ack_t_s[1:0], ack_t_74};
	boot_s  <= {boot_s[1:0], boot_ready_74};
	for (i = 0; i < 6; i = i + 1) upd_s[i] <= {upd_s[i][1:0], upd_t_74[i]};
end
wire req_busy = req_t != ack_t_s[2];

// D64 geometry (track_f = 0-based track)
function [9:0] d64_start(input [5:0] tf);
	d64_start = (tf < 6'd17) ? {4'd0, tf} * 10'd21 :
	            (tf < 6'd24) ? 10'd357 + {4'd0, tf - 6'd17} * 10'd19 :
	            (tf < 6'd30) ? 10'd490 + {4'd0, tf - 6'd24} * 10'd18 :
	                           10'd598 + {4'd0, tf - 6'd30} * 10'd17;
endfunction
function [4:0] d64_nsec(input [5:0] tf);
	d64_nsec = (tf < 6'd17) ? 5'd21 : (tf < 6'd24) ? 5'd19 : (tf < 6'd30) ? 5'd18 : 5'd17;
endfunction
// GCR bytes of a synthesized track (gcr_synth), without the 2 length bytes
function [13:0] d64_gcr_size(input [5:0] tf);
	d64_gcr_size = (tf < 6'd17) ? 14'd7602 : (tf < 6'd24) ? 14'd7049 : (tf < 6'd30) ? 14'd6588 : 14'd6171;
endfunction
function [1:0] d64_speed(input [5:0] tf);
	d64_speed = (tf < 6'd17) ? 2'd3 : (tf < 6'd24) ? 2'd2 : (tf < 6'd30) ? 2'd1 : 2'd0;
endfunction

localparam [1:0] DT_NONE = 2'd0, DT_G64 = 2'd1, DT_D64 = 2'd2, DT_D81 = 2'd3;

reg  [1:0] dtype[2];
reg  [5:0] dtracks[2];           // D64 tracks: 35 / 40 / 42

reg  [5:0] upd_seen;
reg  [5:0] pending;

// gcr_synth: D64 track in rbuf -> bytes to PSRAM
reg        gs_start;
reg  [5:0] gs_track;
reg  [4:0] gs_nsec;
reg  [7:0] id0, id1;
wire       gs_busy;
wire [12:0] gs_rb_addr;
wire       gs_strobe;
wire [7:0] gs_byte;
reg        gs_done;

gcr_synth gcr_synth (
	.clk        ( clk_sys ),
	.start      ( gs_start ),
	.track      ( gs_track ),
	.nsec       ( gs_nsec ),
	.id0        ( id0 ),
	.id1        ( id1 ),
	.busy       ( gs_busy ),
	.rb_addr    ( gs_rb_addr ),
	.rb_q       ( rbuf_q ),
	.out_strobe ( gs_strobe ),
	.out_byte   ( gs_byte ),
	.out_done   ( gs_done )
);

// gcr_decode: flushed track in the drive's buffer -> D64 sectors in wbuf
reg         gd_start;
reg  [13:0] gd_size;
wire        gd_busy;
wire [13:0] gd_sb_addr;
wire        gd_we;
wire [12:0] gd_addr;
wire  [7:0] gd_data;
wire [20:0] gd_valid;
reg         cur_drive;

gcr_decode gcr_decode (
	.clk        ( clk_sys ),
	.start      ( gd_start ),
	.track_size ( gd_size ),
	.nsec       ( gs_nsec ),
	.busy       ( gd_busy ),
	.sb_addr    ( gd_sb_addr ),
	.sb_q       ( sd_buff_din[cur_drive] ),
	.wb_we      ( gd_we ),
	.wb_addr    ( gd_addr ),
	.wb_data    ( gd_data ),
	.valid      ( gd_valid )
);

reg         decoding;
reg  [13:0] buf_addr;
assign sd_buff_addr = decoding ? gd_sb_addr : buf_addr;

localparam [5:0]
	S_BOOT      = 6'd0,
	S_IDLE      = 6'd1,
	S_REQ_WAIT  = 6'd2,   // wait for a target command, then go to ret
	S_LD_WAIT   = 6'd3,   // wait for a PSRAM loader access, then go to ret
	// ioctl download
	S_DL_CHUNK  = 6'd4,
	S_DL_BYTE   = 6'd5,
	S_DL_SEND   = 6'd6,
	S_DL_PACE   = 6'd7,
	S_DL_END    = 6'd8,
	// mount
	S_MT_START  = 6'd9,
	S_MT_MAGIC  = 6'd10,
	S_MT_KIND   = 6'd11,
	S_G64_CHUNK = 6'd12,
	S_G64_BYTE  = 6'd13,
	S_G64_PUT   = 6'd14,
	S_D64_ID    = 6'd15,
	S_D64_HDR   = 6'd16,
	S_D64_HPUT  = 6'd17,
	S_D64_TRK   = 6'd18,
	S_D64_LEN   = 6'd19,
	S_D64_GCR   = 6'd20,
	S_MT_PULSE  = 6'd21,
	// drive service
	S_RD81      = 6'd22,
	S_RD81_DATA = 6'd23,
	S_WR81_DATA = 6'd24,
	S_WR_LEN    = 6'd25,
	S_WR_G64    = 6'd26,
	S_WR_G64_CP = 6'd27,
	S_WR_D64    = 6'd28,
	S_WR_D64_WR = 6'd29,
	S_SD_END    = 6'd30;

reg  [5:0] state;
reg  [5:0] ret;
reg  [2:0] slot;                 // file being downloaded
reg [31:0] fsize;
reg [31:0] foff;                 // file offset of the chunk in rbuf
reg [13:0] clen;                 // bytes in the chunk
reg [13:0] ci;                   // byte index in the chunk
reg  [3:0] cnt;
reg        drive;                // drive being mounted or served
reg [31:0] word;                 // scratch for header fields
reg  [9:0] hi;                   // header byte index (D64 header)
reg  [6:0] ht;                   // half-track index
reg [20:0] cur;                  // running G64 data offset
reg  [5:0] tf;                   // D64 track being converted
reg [13:0] tsize;                // flushed track length
reg [31:0] g64_off;
reg [15:0] g64_max;
reg  [4:0] sec;

wire [21:0] dbase = {drive, 21'd0};   // 2 MB per drive
wire [13:0] tf_gcr_size = d64_gcr_size(tf);
// G64 header being written: half-track of byte hi, and whether the D64 has that track
wire  [9:0] hdr_rel = (hi < 10'd348) ? hi - 10'd12 : hi - 10'd348;
wire  [6:0] hdr_t = hdr_rel[8:2];
wire        hdr_has_track = !hdr_t[0] && hdr_t[6:1] < dtracks[drive];

initial begin
	state = S_BOOT;
	req_t = 1'b0;
	ack_t_74 = 1'b0;
	estate = E_IDLE;
	boot_ready_74 = 1'b0;
	dt_scanning = 1'b0;
	upd_t_74 = 6'd0;
	upd_seen = 6'd0;
	pending = 6'd0;
	img_mounted = 2'b00;
	sd_ack = 2'b00;
	ioctl_download = 1'b0;
	ioctl_wr = 1'b0;
	decoding = 1'b0;
	dtype[0] = DT_NONE;
	dtype[1] = DT_NONE;
end

assign busy = ioctl_download || (state >= S_MT_START && state <= S_MT_PULSE);

wire [63:0] MAGIC = "GCR-1541";

always @(posedge clk_sys) begin
	integer i;
	reg [13:0] n;

	ioctl_wr <= 1'b0;
	wbuf_we <= 1'b0;
	sd_buff_wr <= 1'b0;
	ld_start <= 1'b0;
	gs_start <= 1'b0;
	gs_done <= 1'b0;
	gd_start <= 1'b0;

	for (i = 0; i < 6; i = i + 1)
		if (upd_s[i][2] != upd_seen[i]) begin
			upd_seen[i] <= upd_s[i][2];
			pending[i] <= 1'b1;
		end

	// decoded D64 bytes go straight to wbuf
	if (gd_we) begin
		wbuf_we <= 1'b1;
		wbuf_waddr <= gd_addr;
		wbuf_wdata <= gd_data;
	end

	case (state)
	S_BOOT: if (boot_s[2]) state <= S_IDLE;

	S_IDLE: begin
		sd_ack <= 2'b00;
		decoding <= 1'b0;
		if (|sd_wr) begin
			drive <= !sd_wr[0];
			cur_drive <= !sd_wr[0];
			sd_ack[!sd_wr[0]] <= 1'b1;
			ci <= 14'd0;
			cnt <= 4'd0;
			if (dtype[!sd_wr[0]] == DT_D81) state <= S_WR81_DATA;
			else if (dtype[!sd_wr[0]] == DT_NONE) state <= S_SD_END;
			else state <= S_WR_LEN;
		end else if (|sd_rd) begin
			drive <= !sd_rd[0];
			cur_drive <= !sd_rd[0];
			sd_ack[!sd_rd[0]] <= 1'b1;
			state <= (dtype[!sd_rd[0]] == DT_D81) ? S_RD81 : S_SD_END;
		end else if (pending[SLOT_D8] || pending[SLOT_D9]) begin
			drive <= !pending[SLOT_D8];
			state <= S_MT_START;
		end else if (pending[SLOT_ROM] || pending[SLOT_CRT] || pending[SLOT_TAP] || pending[SLOT_PRG]) begin
			slot <= pending[SLOT_ROM] ? SLOT_ROM[2:0] : pending[SLOT_CRT] ? SLOT_CRT[2:0] :
			        pending[SLOT_TAP] ? SLOT_TAP[2:0] : SLOT_PRG[2:0];
			state <= S_DL_CHUNK;
			foff <= 32'd0;
			ioctl_addr <= 25'd0;
		end
	end

	S_REQ_WAIT: if (!req_busy) state <= ret;
	S_LD_WAIT:  if (ld_ack) state <= ret;

	// ---------------- ioctl download: 8 KB chunks ----------------
	S_DL_CHUNK: if (!req_busy) begin
		if (foff == 32'd0 && size_74[slot] == 32'd0) begin
			pending[slot] <= 1'b0;
			state <= S_IDLE;
		end else begin
			if (foff == 32'd0) begin
				fsize <= size_74[slot];
				pending[slot] <= 1'b0;
				ioctl_index <= slot == SLOT_PRG[2:0] ? 8'h01 : slot == SLOT_CRT[2:0] ? 8'h41 :
				               slot == SLOT_TAP[2:0] ? 8'hC1 : 8'h08;
				ioctl_file_ext <= slot == SLOT_CRT[2:0] ? ".CRT" : slot == SLOT_TAP[2:0] ? ".TAP" :
				                  slot == SLOT_PRG[2:0] ? ".PRG" : ".ROM";
				ioctl_download <= 1'b1;
				n = (size_74[slot] > 32'd8192) ? 14'd8192 : size_74[slot][13:0];
			end else
				n = (fsize - foff > 32'd8192) ? 14'd8192 : 14'(fsize - foff);
			clen <= n;
			ci <= 14'd0;
			req_write      <= 1'b0;
			req_slot       <= {13'd0, slot};
			req_offset     <= foff;
			req_length     <= {18'd0, n};
			req_bridgeaddr <= RBUF_ADDR;
			req_t          <= ~req_t;
			ret            <= S_DL_BYTE;
			cnt            <= 4'd0;
			state          <= S_REQ_WAIT;
		end
	end

	S_DL_BYTE: begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd0) rbuf_raddr <= ci[12:0];
		if (cnt == 4'd2) begin
			ioctl_data <= rbuf_q;
			state <= S_DL_SEND;
		end
	end

	S_DL_SEND: if (!ioctl_wait) begin
		ioctl_wr <= 1'b1;
		cnt <= 4'd0;
		state <= S_DL_PACE;
	end

	// give the core time to raise ioctl_wait for this byte
	S_DL_PACE: begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd3) begin
			cnt <= 4'd0;
			ioctl_addr <= ioctl_addr + 25'd1;
			ci <= ci + 14'd1;
			if (ci + 14'd1 == clen) begin
				foff <= foff + {18'd0, clen};
				state <= (foff + {18'd0, clen} >= fsize) ? S_DL_END : S_DL_CHUNK;
			end else
				state <= S_DL_BYTE;
		end
	end

	S_DL_END: if (!ioctl_wait) begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd15) begin
			ioctl_download <= 1'b0;
			state <= S_IDLE;
		end
	end

	// ---------------- disk mount ----------------
	S_MT_START: if (!req_busy) begin
		pending[drive ? SLOT_D9 : SLOT_D8] <= 1'b0;
		fsize <= size_74[drive ? SLOT_D9 : SLOT_D8];
		dtype[drive] <= DT_NONE;
		if (size_74[drive ? SLOT_D9 : SLOT_D8] == 32'd0) begin
			img_size <= 32'd0;
			cnt <= 4'd0;
			state <= S_MT_PULSE;
		end else begin
			n = (size_74[drive ? SLOT_D9 : SLOT_D8] > 32'd8192) ? 14'd8192 : size_74[drive ? SLOT_D9 : SLOT_D8][13:0];
			clen <= n;
			foff <= 32'd0;
			req_write      <= 1'b0;
			req_slot       <= drive ? SLOT_D9 : SLOT_D8;
			req_offset     <= 32'd0;
			req_length     <= {18'd0, n};
			req_bridgeaddr <= RBUF_ADDR;
			req_t          <= ~req_t;
			ret            <= S_MT_MAGIC;
			ci             <= 14'd0;
			cnt            <= 4'd0;
			word           <= 32'd1;     // magic still matching
			state          <= S_REQ_WAIT;
		end
	end

	// compare the first 8 bytes with "GCR-1541"
	S_MT_MAGIC: begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd0) rbuf_raddr <= ci[12:0];
		if (cnt == 4'd2) begin
			cnt <= 4'd0;
			if (rbuf_q != MAGIC[(7 - ci[2:0]) * 8 +: 8]) word[0] <= 1'b0;
			ci <= ci + 14'd1;
			if (ci == 14'd7) state <= S_MT_KIND;
		end
	end

	S_MT_KIND: begin
		img_size <= fsize;
		ci <= 14'd0;
		cnt <= 4'd0;
		if (word[0]) begin
			dtype[drive] <= DT_G64;
			img_type <= 2'b01;
			state <= S_G64_BYTE;          // the first chunk is already in rbuf
		end else if (fsize >= 32'd819200) begin
			dtype[drive] <= DT_D81;
			img_type <= 2'b11;
			state <= S_MT_PULSE;
		end else if (fsize >= 32'd174848) begin
			dtype[drive] <= DT_D64;
			dtracks[drive] <= (fsize <= 32'd175531) ? 6'd35 : (fsize <= 32'd197376) ? 6'd40 : 6'd42;
			img_type <= 2'b01;
			state <= S_D64_ID;
		end else begin
			img_size <= 32'd0;              // not a disk image: leave the drive empty
			state <= S_MT_PULSE;
		end
	end

	// ---- G64: copy the file (up to 2 MB) into PSRAM ----
	S_G64_CHUNK: if (!req_busy) begin
		n = (fsize - foff > 32'd8192) ? 14'd8192 : 14'(fsize - foff);
		clen <= n;
		ci <= 14'd0;
		cnt <= 4'd0;
		req_write      <= 1'b0;
		req_slot       <= drive ? SLOT_D9 : SLOT_D8;
		req_offset     <= foff;
		req_length     <= {18'd0, n};
		req_bridgeaddr <= RBUF_ADDR;
		req_t          <= ~req_t;
		ret            <= S_G64_BYTE;
		state          <= S_REQ_WAIT;
	end

	S_G64_BYTE: begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd0) rbuf_raddr <= ci[12:0];
		if (cnt == 4'd2) begin
			cnt <= 4'd0;
			ld_we <= 1'b1;
			ld_addr <= dbase + foff[20:0] + {7'd0, ci};
			ld_wdata <= rbuf_q;
			ld_start <= 1'b1;
			ret <= S_G64_PUT;
			state <= S_LD_WAIT;
		end
	end

	S_G64_PUT: begin
		ci <= ci + 14'd1;
		if (ci + 14'd1 == clen) begin
			foff <= foff + {18'd0, clen};
			if (foff + {18'd0, clen} >= fsize || foff + {18'd0, clen} >= 32'h200000) state <= S_MT_PULSE;
			else state <= S_G64_CHUNK;
		end else
			state <= S_G64_BYTE;
	end

	// ---- D64: disk id from track 18 sector 0, then a synthesized G64 ----
	S_D64_ID: if (!req_busy) begin
		if (cnt == 4'd0) begin
			req_write      <= 1'b0;
			req_slot       <= drive ? SLOT_D9 : SLOT_D8;
			req_offset     <= 32'h16500;
			req_length     <= 32'd256;
			req_bridgeaddr <= RBUF_ADDR;
			req_t          <= ~req_t;
			ret            <= S_D64_ID;
			cnt            <= 4'd1;
			state          <= S_REQ_WAIT;
		end else begin
			cnt <= cnt + 4'd1;
			if (cnt == 4'd1) rbuf_raddr <= 13'hA2;
			if (cnt == 4'd3) begin id0 <= rbuf_q; rbuf_raddr <= 13'hA3; end
			if (cnt == 4'd5) begin
				id1 <= rbuf_q;
				hi <= 10'd0;
				ht <= 7'd0;
				cur <= 21'd684;
				state <= S_D64_HDR;
			end
		end
	end

	// header: 12 bytes, then for each half-track its offset (12 + 4t) and speed (348 + 4t)
	S_D64_HDR: begin
		ld_we <= 1'b1;
		ld_addr <= dbase + {12'd0, hi};
		if (hi < 10'd8)
			ld_wdata <= MAGIC[(7 - hi[2:0]) * 8 +: 8];
		else if (hi < 10'd12)
			ld_wdata <= (hi == 10'd9) ? 8'd84 : 8'h00;
		else if (hi < 10'd348) begin
			// offset of half-track hdr_t; the running offset is latched at its first byte
			if (hi[1:0] == 2'd0) begin
				word <= hdr_has_track ? {11'd0, cur} : 32'd0;
				if (hdr_has_track) cur <= cur + 21'd2 + {7'd0, d64_gcr_size(hdr_t[6:1])};
				ld_wdata <= hdr_has_track ? cur[7:0] : 8'h00;
			end else
				ld_wdata <= word[{hi[1:0], 3'b000} +: 8];
		end else
			ld_wdata <= (hi[1:0] == 2'd0 && hdr_has_track) ? {6'd0, d64_speed(hdr_t[6:1])} : 8'h00;
		ld_start <= 1'b1;
		ret <= S_D64_HPUT;
		state <= S_LD_WAIT;
	end

	S_D64_HPUT: begin
		hi <= hi + 10'd1;
		if (hi == 10'd683) begin
			tf <= 6'd0;
			cur <= 21'd684;
			state <= S_D64_TRK;
		end else
			state <= S_D64_HDR;
	end

	// one track: read its sectors, write the length, then the GCR bytes
	S_D64_TRK: if (!req_busy) begin
		if (tf == dtracks[drive]) state <= S_MT_PULSE;
		else begin
			gs_track       <= tf + 6'd1;
			gs_nsec        <= d64_nsec(tf);
			req_write      <= 1'b0;
			req_slot       <= drive ? SLOT_D9 : SLOT_D8;
			req_offset     <= {14'd0, d64_start(tf), 8'd0};
			req_length     <= {19'd0, d64_nsec(tf), 8'd0};
			req_bridgeaddr <= RBUF_ADDR;
			req_t          <= ~req_t;
			ret            <= S_D64_LEN;
			cnt            <= 4'd0;
			state          <= S_REQ_WAIT;
		end
	end

	S_D64_LEN: begin
		ld_we <= 1'b1;
		ld_addr <= dbase + cur + {20'd0, cnt[0]};
		ld_wdata <= cnt[0] ? {2'd0, tf_gcr_size[13:8]} : tf_gcr_size[7:0];
		ld_start <= 1'b1;
		cnt <= cnt + 4'd1;
		ret <= cnt[0] ? S_D64_GCR : S_D64_LEN;
		if (cnt[0]) begin
			gs_start <= 1'b1;
			cur <= cur + 21'd2;
			cnt <= 4'd0;
		end
		state <= S_LD_WAIT;
	end

	// gcr_synth emits bytes; each goes to PSRAM before it is acknowledged
	S_D64_GCR: begin
		rbuf_raddr <= gs_rb_addr;
		if (cnt == 4'd0) begin
			if (gs_strobe && !gs_done && !ld_start) begin
				ld_we <= 1'b1;
				ld_addr <= dbase + cur;
				ld_wdata <= gs_byte;
				ld_start <= 1'b1;
				cnt <= 4'd1;
			end else if (!gs_busy && !gs_strobe && !gs_start) begin
				tf <= tf + 6'd1;
				state <= S_D64_TRK;
			end
		end else if (ld_ack) begin
			cur <= cur + 21'd1;
			gs_done <= 1'b1;
			cnt <= 4'd0;
		end
	end

	S_MT_PULSE: begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd1) img_mounted[drive] <= 1'b1;
		if (cnt == 4'd9) begin
			img_mounted <= 2'b00;
			state <= S_IDLE;
		end
	end

	// ---------------- 1581: 512-byte sectors ----------------
	S_RD81: if (!req_busy) begin
		req_write      <= 1'b0;
		req_slot       <= drive ? SLOT_D9 : SLOT_D8;
		req_offset     <= {sd_lba[drive][23:0], 8'd0};
		req_length     <= 32'd512;
		req_bridgeaddr <= RBUF_ADDR;
		req_t          <= ~req_t;
		ret            <= S_RD81_DATA;
		ci             <= 14'd0;
		cnt            <= 4'd0;
		state          <= S_REQ_WAIT;
	end

	S_RD81_DATA: begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd0) rbuf_raddr <= ci[12:0];
		if (cnt == 4'd2) begin
			cnt <= 4'd0;
			buf_addr <= ci;
			sd_buff_dout <= rbuf_q;
			sd_buff_wr <= 1'b1;
			ci <= ci + 14'd1;
			if (ci == 14'd511) state <= S_SD_END;
		end
	end

	S_WR81_DATA: begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd0) buf_addr <= ci;
		if (cnt == 4'd2) begin
			cnt <= 4'd0;
			wbuf_we <= 1'b1;
			wbuf_waddr <= ci[12:0];
			wbuf_wdata <= sd_buff_din[drive];
			ci <= ci + 14'd1;
			if (ci == 14'd511) begin
				req_write      <= 1'b1;
				req_slot       <= drive ? SLOT_D9 : SLOT_D8;
				req_offset     <= {sd_lba[drive][23:0], 8'd0};
				req_length     <= 32'd512;
				req_bridgeaddr <= WBUF_ADDR;
				req_t          <= ~req_t;
				ret            <= S_SD_END;
				state          <= S_REQ_WAIT;
			end
		end
	end

	// ---------------- 1541 track write-back ----------------
	// the drive's buffer: 2-byte length, then the GCR track
	S_WR_LEN: begin
		cnt <= cnt + 4'd1;
		if (cnt == 4'd0) buf_addr <= 14'd0;
		if (cnt == 4'd2) begin tsize[7:0] <= sd_buff_din[drive]; buf_addr <= 14'd1; end
		if (cnt == 4'd4) begin
			tsize[13:8] <= sd_buff_din[drive][5:0];
			cnt <= 4'd0;
			hi <= 10'd0;
			state <= (dtype[drive] == DT_G64) ? S_WR_G64 : S_WR_D64;
		end
	end

	// G64: the track's file offset and the image's max track size from the header in PSRAM
	S_WR_G64: begin
		if (sd_lba[drive] >= 32'd84) state <= S_SD_END;
		else begin
			ld_we <= 1'b0;
			ld_start <= 1'b1;
			ret <= S_WR_G64;
			state <= S_LD_WAIT;
			case (hi)
				10'd0: ld_addr <= dbase + 22'd10;
				10'd1: begin g64_max <= ld_rdata; ld_addr <= dbase + 22'd12 + {12'd0, sd_lba[drive][6:0], 2'b00}; end
				10'd2: begin g64_off[15:0] <= ld_rdata; ld_addr <= dbase + 22'd14 + {12'd0, sd_lba[drive][6:0], 2'b00}; end
				default: begin
					g64_off[31:16] <= ld_rdata;
					ld_start <= 1'b0;
					ci <= 14'd0;
					cnt <= 4'd0;
					state <= S_WR_G64_CP;
				end
			endcase
			hi <= hi + 10'd1;
		end
	end

	S_WR_G64_CP: begin
		// bytes to write: length + 2, at most the image's track space
		n = (tsize > 14'd8190) ? 14'd8192 : tsize + 14'd2;
		if (g64_max != 16'd0 && {2'd0, n} > g64_max + 16'd2) n = 14'(g64_max + 16'd2);
		if (g64_off == 32'd0 || tsize <= 14'd8) state <= S_SD_END;
		else begin
			cnt <= cnt + 4'd1;
			if (cnt == 4'd0) buf_addr <= ci;
			if (cnt == 4'd2) begin
				cnt <= 4'd0;
				wbuf_we <= 1'b1;
				wbuf_waddr <= ci[12:0];
				wbuf_wdata <= sd_buff_din[drive];
				ci <= ci + 14'd1;
				if (ci + 14'd1 == n) begin
					req_write      <= 1'b1;
					req_slot       <= drive ? SLOT_D9 : SLOT_D8;
					req_offset     <= g64_off;
					req_length     <= {18'd0, n};
					req_bridgeaddr <= WBUF_ADDR;
					req_t          <= ~req_t;
					ret            <= S_SD_END;
					state          <= S_REQ_WAIT;
				end
			end
		end
	end

	// D64: decode the track into wbuf, then write each sector found
	S_WR_D64: begin
		if (sd_lba[drive][0] || sd_lba[drive] >= {25'd0, dtracks[drive], 1'b0} ||
		    tsize <= 14'd8 || tsize > 14'd8190) state <= S_SD_END;
		else if (hi == 10'd0) begin
			tf <= sd_lba[drive][6:1];
			gs_nsec <= d64_nsec(sd_lba[drive][6:1]);
			gd_size <= tsize;
			decoding <= 1'b1;
			hi <= 10'd1;
		end else if (hi == 10'd1) begin
			gd_start <= 1'b1;
			hi <= 10'd2;
		end else if (hi == 10'd2) begin
			hi <= 10'd3;                    // gd_busy rises
		end else if (!gd_busy) begin
			decoding <= 1'b0;
			sec <= 5'd0;
			state <= S_WR_D64_WR;
		end
	end

	S_WR_D64_WR: if (!req_busy) begin
		if (sec == gs_nsec) state <= S_SD_END;
		else begin
			sec <= sec + 5'd1;
			if (gd_valid[sec]) begin
				req_write      <= 1'b1;
				req_slot       <= drive ? SLOT_D9 : SLOT_D8;
				req_offset     <= {14'd0, d64_start(tf) + {5'd0, sec}, 8'd0};
				req_length     <= 32'd256;
				req_bridgeaddr <= WBUF_ADDR + {19'd0, sec, 8'd0};
				req_t          <= ~req_t;
				ret            <= S_WR_D64_WR;
				state          <= S_REQ_WAIT;
			end
		end
	end

	// dropping the ack completes the drive's request
	S_SD_END: begin
		sd_ack <= 2'b00;
		decoding <= 1'b0;
		if (!sd_rd[drive] && !sd_wr[drive]) state <= S_IDLE;
	end

	default: state <= S_BOOT;
	endcase
end

endmodule

`default_nettype wire
