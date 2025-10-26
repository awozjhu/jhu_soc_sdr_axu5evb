// widths.vh
`ifndef SDR_WIDTHS_VH
`define SDR_WIDTHS_VH
// -----------------------------------------------------------------------------
// Global stream widths & I/Q layout for the SoC SDR project.
// Bitstream legs: AXIS bytes (8 bits).
// Symbol legs:    AXIS complex I/Q in Q1.15 -> TDATA[31:0] = {I[15:0], Q[15:0]}.
// -----------------------------------------------------------------------------

// AXI-Stream beat widths
`define BIT_AXI_W   8            // bytes from PRBS/scrambler/FEC/etc.
`define IQ_W        16           // bits per I or Q component (signed Q1.15)
`define SYM_AXI_W   (2*`IQ_W)    // == 32, {I,Q}

// Derived (TKEEP) widths
`define BIT_TKEEP_W (`BIT_AXI_W/8)   // 1
`define SYM_TKEEP_W (`SYM_AXI_W/8)   // 4

// Constellation bits/symbol (reference)
`define BPSK_BITS_PER_SYM 1
`define QPSK_BITS_PER_SYM 2

// Handy slices/macros for {I,Q} in a 32-bit symbol beat
`define IQ_I_SLICE(_td_)   _td_[`SYM_AXI_W-1:`IQ_W] // I = [31:16]
`define IQ_Q_SLICE(_td_)   _td_[`IQ_W-1:0]          // Q = [15:0]
`define IQ_PACK(_i_,_q_)   {_i_, _q_}               // pack I/Q -> TDATA

// Optional: strongly-typed I/Q in a tiny package (import sdr_types_pkg::*)
package sdr_types_pkg;
  localparam int BIT_AXI_W = `BIT_AXI_W;
  localparam int IQ_W      = `IQ_W;
  localparam int SYM_AXI_W = `SYM_AXI_W;

  typedef logic signed [IQ_W-1:0] iq_comp_t;
  typedef struct packed { iq_comp_t I; iq_comp_t Q; } iq_t;

  function automatic logic [SYM_AXI_W-1:0] pack_iq (iq_t s);
    return {s.I, s.Q};
  endfunction

  function automatic iq_t unpack_iq (logic [SYM_AXI_W-1:0] tdata);
    iq_t r; r.I = tdata[SYM_AXI_W-1:IQ_W]; r.Q = tdata[IQ_W-1:0]; return r;
  endfunction
endpackage
`endif
