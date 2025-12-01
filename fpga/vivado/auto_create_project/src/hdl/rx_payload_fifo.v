// ============================================================================
//  rx_payload_fifo.v
//  Simple BRAM-based FIFO for GT RX → RX_SHIM buffering
//  - No backpressure on write side (GT cannot stall)
//  - Overflow is recorded but writes are NOT blocked
//  - Safe, synchronous FIFO for use before CDC AXIS FIFO
// ============================================================================

module rx_payload_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 2048                     // recommended: 2048 or 4096
)(
    input  wire                     clk,
    input  wire                     rst,

    // -------------------------
    // WRITE SIDE (RX_SHIM)
    // -------------------------
    input  wire [DATA_WIDTH-1:0]    din,
    input  wire                     wr_en,           // write when RX_CTRL==0
    output wire                     full,            // informational only
    output reg                      overflow_flag,   // asserted on overrun

    // -------------------------
    // READ SIDE (to CDC FIFO)
    // -------------------------
    output wire [DATA_WIDTH-1:0]    dout,
    input  wire                     rd_en,
    output wire                     empty
);

    // =========================================================================
    // Internal memory and pointers
    // =========================================================================
    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_W:0] wptr = 0;      // one extra bit for full/empty disambiguation
    reg [ADDR_W:0] rptr = 0;

    wire [ADDR_W-1:0] waddr = wptr[ADDR_W-1:0];
    wire [ADDR_W-1:0] raddr = rptr[ADDR_W-1:0];

    // =========================================================================
    // FULL / EMPTY logic
    // =========================================================================
    assign empty = (wptr == rptr);

    assign full =
          (wptr[ADDR_W]     != rptr[ADDR_W]) && 
          (wptr[ADDR_W-1:0] == rptr[ADDR_W-1:0]);

    // =========================================================================
    // OUTPUT read port (combinational read from BRAM / inferred RAM)
    // =========================================================================
    assign dout = mem[raddr];

    // =========================================================================
    // FIFO Behavior
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            wptr          <= 0;
            rptr          <= 0;
            overflow_flag <= 1'b0;
        end else begin

            // --------------------------------------------------------------
            // WRITE SIDE — always write, even when FIFO is "full"
            // --------------------------------------------------------------
            if (wr_en) begin
                mem[waddr] <= din;
                wptr       <= wptr + 1;

                // If full, flag overflow (cannot stop GT)
                if (full)
                    overflow_flag <= 1'b1;
            end

            // --------------------------------------------------------------
            // READ SIDE — only advance when rd_en and not empty
            // --------------------------------------------------------------
            if (rd_en && !empty) begin
                rptr <= rptr + 1;
            end
        end
    end

endmodule
