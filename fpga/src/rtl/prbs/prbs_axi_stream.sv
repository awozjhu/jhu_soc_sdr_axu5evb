// prbs_axi_stream.sv
// AXI4-Lite controlled PRBS generator with AXI-Stream master output.
// Supports PRBS7/15/23/31, optional byte packing, optional TLAST framing.
// Author: Alex Wozneak (project scaffold generated)

`timescale 1ns/1ps

module prbs_axi_stream #(
  parameter int AXIL_ADDR_WIDTH = 6,      // 64-byte register space
  parameter int AXIL_DATA_WIDTH = 32
) (
  input  wire                   clk,
  input  wire                   rst_n,

  // AXI4-Lite slave (control/status)
  input  wire [AXIL_ADDR_WIDTH-1:0] s_axil_awaddr,
  input  wire                        s_axil_awvalid,
  output logic                       s_axil_awready,
  input  wire [AXIL_DATA_WIDTH-1:0] s_axil_wdata,
  input  wire [AXIL_DATA_WIDTH/8-1:0] s_axil_wstrb,
  input  wire                        s_axil_wvalid,
  output logic                       s_axil_wready,
  output logic [1:0]                 s_axil_bresp,
  output logic                       s_axil_bvalid,
  input  wire                        s_axil_bready,
  input  wire [AXIL_ADDR_WIDTH-1:0] s_axil_araddr,
  input  wire                        s_axil_arvalid,
  output logic                       s_axil_arready,
  output logic [AXIL_DATA_WIDTH-1:0] s_axil_rdata,
  output logic [1:0]                 s_axil_rresp,
  output logic                       s_axil_rvalid,
  input  wire                        s_axil_rready,

  // AXI-Stream master (data out)
  output logic [7:0]             m_axis_tdata,  // byte lane; if bit-mode: data[0] holds the bit
  output logic                   m_axis_tvalid,
  input  wire                    m_axis_tready,
  output logic                   m_axis_tlast
);

  // -----------------------------
  // Registers (AXI-Lite map)
  // 0x00 CTRL      : [0] enable, [3:1] poly_sel, [4] pack_bytes, [5] tlast_en
  // 0x04 SEED      : [30:0] seed value (0 auto-fixed to 1)
  // 0x08 FRM_LEN   : [15:0] frame_len_bytes
  // 0x0C STATUS    : [0] running, [1] seed_loaded, [2] seed_zero_fixed,
  //                   [31:16] frame_bytes_rem
  // -----------------------------

  // AXI-Lite simple registers
  localparam CTRL_ADDR    = 6'h00;
  localparam SEED_ADDR    = 6'h04;
  localparam FRMLEN_ADDR  = 6'h08;
  localparam STATUS_ADDR  = 6'h0C;

  // CTRL fields
  logic        ctrl_enable;
  logic [2:0]  ctrl_poly_sel;    // 0=PRBS7,1=PRBS15,2=PRBS23,3=PRBS31
  logic        ctrl_pack_bytes;  // 1=bytes, 0=bit in data[0]
  logic        ctrl_tlast_en;

  // Other CSRs
  logic [30:0] csr_seed;
  logic [15:0] csr_frame_len_bytes;

  // STATUS shadow
  logic        st_running;
  logic        st_seed_loaded;
  logic        st_seed_zero_fixed;
  logic [15:0] st_frame_bytes_rem;

  // AXI-Lite minimal implementation
  // Write channel
  logic aw_hs, w_hs;
  assign aw_hs = s_axil_awvalid & s_axil_awready;
  assign w_hs  = s_axil_wvalid  & s_axil_wready;

  // Write address ready/valid
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axil_awready <= 1'b0; 
    else        s_axil_awready <= (~s_axil_awready) & s_axil_awvalid & s_axil_wvalid; // accept when both valid
  end

  // Write data ready
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axil_wready <= 1'b0;
    else        s_axil_wready <= (~s_axil_wready) & s_axil_awvalid & s_axil_wvalid;
  end

  // Write response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_bvalid <= 1'b0;
      s_axil_bresp  <= 2'b00;
    end else begin
      if (aw_hs & w_hs) begin
        s_axil_bvalid <= 1'b1;
        s_axil_bresp  <= 2'b00; // OKAY
      end else if (s_axil_bvalid & s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end
    end
  end

  // Read address ready
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axil_arready <= 1'b0;
    else        s_axil_arready <= (~s_axil_arready) & s_axil_arvalid;
  end

  // Read data/valid
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_rvalid <= 1'b0;
      s_axil_rresp  <= 2'b00;
      s_axil_rdata  <= '0;
    end else begin
      if (s_axil_arready & s_axil_arvalid) begin
        s_axil_rvalid <= 1'b1;
        s_axil_rresp  <= 2'b00;
        unique case (s_axil_araddr[5:0])
          CTRL_ADDR   : s_axil_rdata <= {26'd0, ctrl_tlast_en, ctrl_pack_bytes, ctrl_poly_sel, ctrl_enable};
          SEED_ADDR   : s_axil_rdata <= {1'b0, csr_seed};
          FRMLEN_ADDR : s_axil_rdata <= {16'd0, csr_frame_len_bytes};
          STATUS_ADDR : s_axil_rdata <= {st_frame_bytes_rem, 13'd0, st_seed_zero_fixed, st_seed_loaded, st_running};
          default     : s_axil_rdata <= 32'hDEADBEEF;
        endcase
      end else if (s_axil_rvalid & s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end

  // CSR write decoding
  logic seed_wr_pulse;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_enable        <= 1'b0;
      ctrl_poly_sel      <= 3'd3;     // default PRBS31
      ctrl_pack_bytes    <= 1'b1;     // default byte mode
      ctrl_tlast_en      <= 1'b0;
      csr_seed           <= 31'd1;    // non-zero default
      csr_frame_len_bytes<= 16'd256;  // default frame length
      seed_wr_pulse      <= 1'b0;
    end else begin
      seed_wr_pulse <= 1'b0;
      if (aw_hs & w_hs) begin
        unique case (s_axil_awaddr[5:0])
          CTRL_ADDR: begin
            if (s_axil_wstrb[0]) begin
              ctrl_enable     <= s_axil_wdata[0];
              ctrl_poly_sel   <= s_axil_wdata[3:1];
              ctrl_pack_bytes <= s_axil_wdata[4];
              ctrl_tlast_en   <= s_axil_wdata[5];
            end
          end
          SEED_ADDR: begin
            // only lower 4 bytes meaningful; keep [30:0]
            csr_seed <= s_axil_wdata[30:0];
            seed_wr_pulse <= 1'b1;
          end
          FRMLEN_ADDR: begin
            if (s_axil_wstrb[1] | s_axil_wstrb[0])
              csr_frame_len_bytes <= s_axil_wdata[15:0];
          end
          default: ;
        endcase
      end
    end
  end

  // -----------------------------
  // PRBS Core + Byte Packer
  // -----------------------------

  // Resolve polynomial taps and length based on ctrl_poly_sel
  logic [4:0] poly_len; // 7,15,23,31
  logic [5:0] tap_a, tap_b; // indices within 0..30

  always_comb begin
    unique case (ctrl_poly_sel)
      3'd0: begin // PRBS7  x^7 + x^6 + 1
        poly_len = 7;
        tap_a    = 6-1; // index from LSB=0; we use lfsr[poly_len-1:0]; taps at (6,5)
        tap_b    = 5-1;
      end
      3'd1: begin // PRBS15 x^15 + x^14 + 1 -> taps (14,13)
        poly_len = 15;
        tap_a    = 14-1;
        tap_b    = 13-1;
      end
      3'd2: begin // PRBS23 x^23 + x^18 + 1 -> taps (22,17)
        poly_len = 23;
        tap_a    = 22-1;
        tap_b    = 17-1;
      end
      default: begin // PRBS31 x^31 + x^28 + 1 -> taps (30,27)
        poly_len = 31;
        tap_a    = 30-1;
        tap_b    = 27-1;
      end
    endcase
  end

  // 31-bit LFSR; only lower poly_len bits are used
  logic [30:0] lfsr_q, lfsr_d;
  logic        feedback_bit;
  logic        lfsr_adv;     // advance when producing/consuming a bit

  // Seed handling
  logic        seed_load;
  logic [30:0] seed_value_fixed;

  assign seed_value_fixed = (csr_seed == 31'd0) ? 31'd1 : csr_seed; // auto-fix zero

  // Seed load policy: allow when disabled OR (optionally) at any time; we choose: only when disabled
  assign seed_load = seed_wr_pulse & ~ctrl_enable;

  // Status flags
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_seed_loaded     <= 1'b0;
      st_seed_zero_fixed <= 1'b0;
    end else begin
      if (seed_load) begin
        st_seed_loaded     <= 1'b1;
        st_seed_zero_fixed <= (csr_seed == 31'd0);
      end
    end
  end

  // LFSR advancement controlled by back-pressure and mode
  // We advance when we actually emit a bit (bit mode) OR when we accept a bit into the packer (byte mode)
  // Both are tied to AXIS handshake (valid & ready) in their respective modes.

  // Byte packer
  logic [7:0]  byte_shift;
  logic [2:0]  bit_cnt;       // 0..7
  logic        pack_full;     // becomes 1 when bit_cnt==7 and a new bit is accepted

  // Frame byte counter (for TLAST)
  logic [15:0] frame_cnt_q, frame_cnt_d;
  logic        frame_reload;

  // Output datapath control
  logic        out_valid_d, out_valid_q;
  logic [7:0]  out_data_d,  out_data_q;
  logic        out_last_d,  out_last_q;

  // Advance conditions per mode
  wire out_fire = out_valid_q & m_axis_tready; // a transfer happened

  // Compute next states
  always_comb begin
    // defaults
    lfsr_d        = lfsr_q;
    feedback_bit  = lfsr_q[tap_a] ^ lfsr_q[tap_b];

    out_valid_d   = out_valid_q;
    out_data_d    = out_data_q;
    out_last_d    = 1'b0; // TLAST asserted only on the cycle of transfer

    frame_cnt_d   = frame_cnt_q;
    frame_reload  = 1'b0;

    st_frame_bytes_rem = frame_cnt_q;

    // Determine when we can accept/emit based on mode
    if (ctrl_enable) begin
      if (ctrl_pack_bytes) begin
        // BYTE MODE: accumulate 8 bits, then present a byte; advance LFSR only when we accept bits
        out_valid_d = out_valid_q; // updated when pack_full
        if (out_valid_q) begin
          // wait for consumer
          if (out_fire) begin
            // Byte consumed, potentially assert TLAST and decrement frame counter
            if (ctrl_tlast_en) begin
              if (frame_cnt_q == 16'd1) begin
                out_last_d   = 1'b1;
                frame_cnt_d  = csr_frame_len_bytes; // reload after firing
                frame_reload = 1'b1;
              end else begin
                frame_cnt_d  = frame_cnt_q - 16'd1;
              end
            end
            out_valid_d = 1'b0; // ready to build next byte
          end
        end else begin
          // building byte
          // We only add a bit when downstream is ready *or* while we don't yet have a full byte (no out_valid)
          // To keep bit-for-bit determinism, we still must stall LFSR if downstream is stalling AND we already have a full byte pending.
          // Here, out_valid_q==0 means we can continue shifting irrespective of tready.
          if (bit_cnt == 3'd7) begin
            // accept 8th bit -> byte ready
            // Next bit will be lfsr_q[0] (define output bit as lsb of LFSR)
            out_data_d  = {lfsr_q[0], byte_shift[7:1]}; // place new bit into bit 0 for little-endian-in-byte
            out_valid_d = 1'b1;
          end
        end
      end else begin
        // BIT MODE: present a bit in data[0] each cycle; hold under back-pressure; advance only on transfer
        if (!out_valid_q) begin
          out_data_d  = {7'd0, lfsr_q[0]};
          out_valid_d = 1'b1;
          // TLAST generation in bit-mode: every 8*frame_len bits (optional); we keep TLAST only in byte mode for simplicity
        end else if (out_fire) begin
          out_valid_d = 1'b0; // will re-generate next cycle
        end
      end
    end else begin
      // disabled
      out_valid_d = 1'b0;
    end

    // Frame counter init when enabling or when programmed
    if (!ctrl_tlast_en) begin
      frame_cnt_d = csr_frame_len_bytes;
    end
  end

  // Bit counter & shift reg advance and LFSR advance control
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr_q   <= 31'd1;
      byte_shift <= 8'd0;
      bit_cnt <= 3'd0;
    end else begin
      if (seed_load) begin
        lfsr_q <= seed_value_fixed;
        bit_cnt <= 3'd0;
        byte_shift <= 8'd0;
      end else if (ctrl_enable) begin
        if (ctrl_pack_bytes) begin
          // advance LFSR and pack bits while we don't have a full byte pending
          if (!out_valid_q) begin
            // capture current bit into byte_shift at position bit_cnt
            byte_shift[bit_cnt] <= lfsr_q[0];
            // advance counters and LFSR
            bit_cnt <= bit_cnt + 3'd1;
            lfsr_q  <= {lfsr_q[29:0], feedback_bit};
            if (bit_cnt == 3'd7) begin
              // byte assembled; next cycle out_valid_d will go high (combinational above)
              bit_cnt <= 3'd0;
            end
          end
          // when out_valid_q==1, we stall until consumed; do not advance LFSR
        end else begin
          // BIT MODE: advance only when we actually transfer (valid & ready)
          if (!out_valid_q || out_fire) begin
            // Produce next bit for next cycle
            lfsr_q <= {lfsr_q[29:0], feedback_bit};
          end
        end
      end
    end
  end

  // Output regs
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid_q <= 1'b0;
      out_data_q  <= 8'd0;
      out_last_q  <= 1'b0;
      frame_cnt_q <= 16'd256;
    end else begin
      out_valid_q <= out_valid_d;
      out_data_q  <= out_data_d;
      out_last_q  <= out_last_d;
      if (seed_load) begin
        frame_cnt_q <= csr_frame_len_bytes;
      end else begin
        frame_cnt_q <= frame_cnt_d;
      end
    end
  end

  // Running status
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_running <= 1'b0;
    end else begin
      st_running <= ctrl_enable;
    end
  end

  // AXIS outputs
  assign m_axis_tvalid = out_valid_q;
  assign m_axis_tdata  = out_data_q;
  assign m_axis_tlast  = (ctrl_pack_bytes & ctrl_tlast_en) ? out_last_q : 1'b0;

endmodule
