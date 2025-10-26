// sdr_chain.sv — Single-IP SDR top with AXIS source select (RX vs ALT)
// - One AXI-Lite for all SDR regs (extend as you add blocks).
// - AXIS RX (from DMA/MM2S) and AXIS ALT (e.g., PRBS IP) feed a 2:1 mux.
// - CTRL.SRC_SEL selects which slave drives M_AXIS_TX.
// - Handshake-safe: we only assert tready on the selected source.
// - Sticky RUNNING and TX counters increment on accepted beats.
//
// SRC_SEL mapping (CTRL[7:4]):
//   0 = S_AXIS_RX (DMA/MM2S path)
//   1 = S_AXIS_ALT (e.g., PRBS M_AXIS)
//   (others reserved; default 0)

`timescale 1ns/1ps
module sdr_chain #(
  parameter int AXIL_ADDR_WIDTH = 12,              // 4KB aperture
  parameter int AXIL_DATA_WIDTH = 32,
  parameter int AXIS_BYTES      = 8                // 8 bytes = 64b bus
)(
  // Clock / Reset (single domain)
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF S_AXI:S_AXIS_RX:S_AXIS_ALT:M_AXIS_TX, FREQ_HZ=100000000, PHASE=0.0" *)
  input  wire clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW" *)
  input  wire rst_n,

  // AXI4-Lite slave (control/status)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR"  *)
  input  wire [AXIL_ADDR_WIDTH-1:0] s_axil_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
  input  wire                        s_axil_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
  output logic                       s_axil_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA"   *)
  input  wire [AXIL_DATA_WIDTH-1:0] s_axil_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB"   *)
  input  wire [AXIL_DATA_WIDTH/8-1:0] s_axil_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID"  *)
  input  wire                        s_axil_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY"  *)
  output logic                       s_axil_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP"   *)
  output logic [1:0]                 s_axil_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID"  *)
  output logic                       s_axil_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY"  *)
  input  wire                        s_axil_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR"  *)
  input  wire [AXIL_ADDR_WIDTH-1:0] s_axil_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
  input  wire                        s_axil_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
  output logic                       s_axil_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA"   *)
  output logic [AXIL_DATA_WIDTH-1:0] s_axil_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP"   *)
  output logic [1:0]                 s_axil_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID"  *)
  output logic                       s_axil_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY"  *)
  input  wire                        s_axil_rready,
  // (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, DATA_WIDTH=32, PROTOCOL=AXI4LITE, ADDR_WIDTH=12, FREQ_HZ=100000000" *) output wire _saxi_params_unused,

  // AXIS Slave (RX from DMA/MM2S or other upstream)
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX TDATA"  *)
  input  wire [AXIS_BYTES*8-1:0]     s_axis_rx_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX TKEEP"  *)
  input  wire [AXIS_BYTES-1:0]       s_axis_rx_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX TVALID" *)
  input  wire                        s_axis_rx_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX TREADY" *)
  output wire                        s_axis_rx_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX TLAST"  *)
  input  wire                        s_axis_rx_tlast,

  // AXIS Slave ALT (e.g., PRBS IP output)
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_ALT TDATA"  *)
  input  wire [AXIS_BYTES*8-1:0]     s_axis_alt_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_ALT TKEEP"  *)
  input  wire [AXIS_BYTES-1:0]       s_axis_alt_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_ALT TVALID" *)
  input  wire                        s_axis_alt_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_ALT TREADY" *)
  output wire                        s_axis_alt_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_ALT TLAST"  *)
  input  wire                        s_axis_alt_tlast,

  // AXIS Master (TX to downstream / DMA S2MM / Aurora)
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX TDATA"  *)
  output wire [AXIS_BYTES*8-1:0]     m_axis_tx_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX TKEEP"  *)
  output wire [AXIS_BYTES-1:0]       m_axis_tx_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX TVALID" *)
  output wire                        m_axis_tx_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX TREADY" *)
  input  wire                        m_axis_tx_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX TLAST"  *)
  output wire                        m_axis_tx_tlast
  // (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_TX, TDATA_NUM_BYTES=8, HAS_TKEEP=1, HAS_TLAST=1" *) output wire _maxis_params_unused
);

  // -----------------------------
  // AXI-Lite register map (extend here)
  // -----------------------------
  localparam CTRL_ADDR      = 12'h000;   // CTRL     : [0] ENABLE, [7:4] SRC_SEL
  localparam STATUS_ADDR    = 12'h004;   // STATUS   : R/W1C sticky [0] RUNNING
  localparam BYTES_TX_ADDR  = 12'h010;   // BYTE_COUNT (accepted TX bytes)
  localparam FRAMES_TX_ADDR = 12'h014;   // FRAME_COUNT (accepted TLASTs)

  // CTRL/STATUS
  logic        ctrl_enable;
  logic [3:0]  ctrl_src_sel;    // 0=RX, 1=ALT
  logic        st_running;      // sticky R/W1C (set on first accepted TX)

  // Counters
  logic [31:0] tx_byte_count;
  logic [31:0] tx_frame_count;

  // -----------------------------
  // Robust AXI-Lite (decoupled AW/W)
  // -----------------------------
  logic                   aw_h, w_h;
  logic [AXIL_ADDR_WIDTH-1:0] aw_addr_q;
  logic [AXIL_DATA_WIDTH-1:0] w_data_q;
  logic [AXIL_DATA_WIDTH/8-1:0] w_strb_q;

  // AW
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_h <= 1'b0; s_axil_awready <= 1'b1; aw_addr_q <= '0;
    end else begin
      if (!aw_h && s_axil_awvalid && s_axil_awready) begin
        aw_h <= 1'b1; aw_addr_q <= s_axil_awaddr; s_axil_awready <= 1'b0;
      end else if (aw_h && w_h && !s_axil_bvalid) begin
        s_axil_awready <= 1'b1; aw_h <= 1'b0;
      end
    end
  end

  // W
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_h <= 1'b0; s_axil_wready <= 1'b1; w_data_q <= '0; w_strb_q <= '0;
    end else begin
      if (!w_h && s_axil_wvalid && s_axil_wready) begin
        w_h <= 1'b1; w_data_q <= s_axil_wdata; w_strb_q <= s_axil_wstrb; s_axil_wready <= 1'b0;
      end else if (aw_h && w_h && !s_axil_bvalid) begin
        s_axil_wready <= 1'b1; w_h <= 1'b0;
      end
    end
  end

  // Write commit + BRESP
  wire wr_fire = aw_h && w_h && !s_axil_bvalid;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_bvalid <= 1'b0; s_axil_bresp <= 2'b00;
      ctrl_enable <= 1'b0; ctrl_src_sel <= 4'd0;
      st_running <= 1'b0;
    end else begin
      if (wr_fire) begin
        unique case (aw_addr_q[AXIL_ADDR_WIDTH-1:0])
          CTRL_ADDR: begin
            if (w_strb_q[0]) begin
              ctrl_enable  <= w_data_q[0];
              ctrl_src_sel <= w_data_q[7:4];
            end
          end
          STATUS_ADDR: begin
            if (w_strb_q[0]) begin
              if (w_data_q[0]) st_running <= 1'b0; // W1C
            end
          end
          default: ;
        endcase
        s_axil_bvalid <= 1'b1; s_axil_bresp <= 2'b00;
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end
    end
  end

  // Read channel
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_arready <= 1'b1; s_axil_rvalid <= 1'b0; s_axil_rdata <= '0; s_axil_rresp <= 2'b00;
    end else begin
      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b1; s_axil_rresp <= 2'b00;
        unique case (s_axil_araddr[AXIL_ADDR_WIDTH-1:0])
          CTRL_ADDR      : s_axil_rdata <= {24'd0, ctrl_src_sel, 3'd0, ctrl_enable};
          STATUS_ADDR    : s_axil_rdata <= {31'd0, st_running};
          BYTES_TX_ADDR  : s_axil_rdata <= tx_byte_count;
          FRAMES_TX_ADDR : s_axil_rdata <= tx_frame_count;
          default        : s_axil_rdata <= 32'hDEAD_0000 | s_axil_araddr[15:0];
        endcase
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0; s_axil_arready <= 1'b1;
      end
    end
  end

  /* synthesis translate_off */
  initial if (0) $display("%0h %0h %0h", s_axil_wdata, s_axil_wstrb, s_axil_araddr);
  /* synthesis translate_on */

  // -----------------------------
  // 2:1 AXIS source MUX + 1-stage register slice to TX
  // -----------------------------
  localparam int DW = AXIS_BYTES*8;

  // Select lines
  wire sel_rx  = (ctrl_src_sel == 4'd0);
  wire sel_alt = (ctrl_src_sel == 4'd1);

  // Selected source view
  wire             src_valid = sel_rx ? s_axis_rx_tvalid : s_axis_alt_tvalid;
  wire [DW-1:0]    src_data  = sel_rx ? s_axis_rx_tdata  : s_axis_alt_tdata;
  wire [AXIS_BYTES-1:0] src_keep  = sel_rx ? s_axis_rx_tkeep  : s_axis_alt_tkeep;
  wire             src_last  = sel_rx ? s_axis_rx_tlast  : s_axis_alt_tlast;

  // Ready only to the selected source, and only when we can load
  logic [DW-1:0]       data_q;
  logic [AXIS_BYTES-1:0] keep_q;
  logic last_q, valid_q;

  wire can_load  = (~valid_q) || m_axis_tx_tready;
  assign s_axis_rx_tready  = ctrl_enable && sel_rx  && can_load;
  assign s_axis_alt_tready = ctrl_enable && sel_alt && can_load;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= 1'b0; data_q <= '0; keep_q <= '0; last_q <= 1'b0;
    end else begin
      if (ctrl_enable && can_load && src_valid) begin
        data_q  <= src_data;
        keep_q  <= src_keep;
        last_q  <= src_last;
        valid_q <= 1'b1;
      end else if (m_axis_tx_tready && valid_q) begin
        valid_q <= 1'b0;
      end
    end
  end

  assign m_axis_tx_tvalid = valid_q;
  assign m_axis_tx_tdata  = data_q;
  assign m_axis_tx_tkeep  = keep_q;
  assign m_axis_tx_tlast  = last_q;

  // -----------------------------
  // Sticky RUNNING + counters (handshake-based)
  // -----------------------------
  wire tx_fire = m_axis_tx_tvalid & m_axis_tx_tready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_running      <= 1'b0;
      tx_byte_count   <= 32'd0;
      tx_frame_count  <= 32'd0;
    end else begin
      if (tx_fire) begin
        st_running    <= 1'b1;                        // first handshake sets RUNNING
        tx_byte_count <= tx_byte_count + AXIS_BYTES;  // count bytes, not beats
        if (m_axis_tx_tlast) tx_frame_count <= tx_frame_count + 32'd1;
      end
      // (W1C for st_running handled in AXI write above)
    end
  end

endmodule
