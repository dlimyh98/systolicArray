// vim: set ts=2 sw=2 et :

module ip_pe #(
  parameter AM_ROWS,
  parameter WBUF_SZE,
  parameter ZZZ = 0
) (
  weight_if.pe      wgt,
  activation_if.pe  act,
  compute_if.pe     cmp,
  input clk,
  input rstn
);

  always_ff @(posedge clk) begin:ff_wgt
    if (!rstn) begin:rst
      wgt.c_s <= '1;
      wgt.v_s <= '0;
      wgt.d_s <= 'x;
    end:rst
    else begin:nrst
      wgt.c_s <= (wgt.v_n) ? (wgt.c_n - 'd1) : wgt.c_n; //FIXME: underflow edge
      wgt.v_s <= wgt.v_n;
      wgt.d_s <= wgt.d_n;
    end:nrst
  end:ff_wgt

  always_ff @(posedge clk) begin:ff_act
    if (!rstn) begin
      act.v_e <= 1'b0;
      act.d_e <= 'x;
    end
    else begin
      act.v_e <= act.v_w;
      act.d_e <= act.d_w;
    end
  end:ff_act

  // ------------------------------- WEIGHT BUFFER ------------------------------- //
  // - weight buffer handling is tricky, problem is with the southmost layer's PE (worst-case)
  // - along Y_DIM, all PEs load their weights at the same time, but
  //   the activation data does not reach all PEs similarly (due to systolic nature)
  // - the northmost PE gets activation data first; ie. the more southerly your PE
  //   is located, the more buffering of your weights is required
  // - example is an (8x2) matmul (2x2)
  localparam WBUF_PTR_W = (WBUF_SZE > 1) ? $clog2(WBUF_SZE) : 1;
  typedef logic [WBUF_PTR_W-1:0] wbuf_ptr_t;
  typedef logic [$clog2(AM_ROWS):0] wbuf_cntr_t;

  wbuf_ptr_t wbuf_wptr, wbuf_rptr;
  wbuf_cntr_t wbuf_cntr;
  logic wgt_wr;
  logic [wgt.DAT_W-1:0] wbuf [0:WBUF_SZE-1], wbuf_rdat;

  always_ff @(posedge clk) begin:ff_wbuf
    if (!rstn) wbuf <= '{default: 'x};
    else       wbuf[wbuf_wptr] <= (wgt_wr) ? wgt.d_n : wbuf[wbuf_wptr];
  end:ff_wbuf

  always_ff @(posedge clk) begin:ff_wbuf_wptr
    if (!rstn) wbuf_wptr <= '0;
    else begin:nrst
      casez ({wgt_wr, (wbuf_wptr+'d1 == wbuf_ptr_t'(WBUF_SZE))})
        2'b0z : wbuf_wptr <= wbuf_wptr;
        2'b10 : wbuf_wptr <= wbuf_wptr + 'd1;
        2'b11 : wbuf_wptr <= '0;
      endcase
    end:nrst
  end:ff_wbuf_wptr

  always_ff @(posedge clk) begin:ff_wbuf_rptr
    if (!rstn) {wbuf_cntr, wbuf_rptr} <= '0;
    else begin:nrst
      if (act.v_w) begin:av
        if (wbuf_cntr + 'd1 == wbuf_cntr_t'(AM_ROWS)) begin:astrm_done
          wbuf_cntr <= '0;
          wbuf_rptr <= ( wbuf_rptr+'d1 == wbuf_ptr_t'(WBUF_SZE) ) ? '0 : (wbuf_rptr + 'd1);
        end:astrm_done
        else begin:astrm_ndone
          wbuf_cntr <= wbuf_cntr + 'd1;
          wbuf_rptr <= wbuf_rptr;
        end:astrm_ndone
      end:av
    end:nrst
  end:ff_wbuf_rptr

  assign wbuf_rdat = wbuf[wbuf_rptr];
  assign wgt_wr = (wgt.c_n == 0) && wgt.v_n;

  // ------------------------------- ACTIVATION BUFFER ------------------------------- //
  // TODO: this functionality is not implemented yet
  // - Inverse problem of weight buffer. Consider a (2x3) matmul (3x1) scenario.
  // - Intuitively, the time spent streaming W values down a column of PEs is larger
  //   than the time spent streaming A values across a row of PEs.
  // - Therefore, the A values can be streamed in before the W values for it have even been loaded
  // - Buffering the W values will not help us here, we need to buffer the A values
  // - the worst case scenario is actually the northwest most PE, contrast this with weight buffer soln

  // i think no need cntr. Every streamed in A value is "hit" once against a corresponding B

  localparam ABUF_SZE = 3; // TODO: bring outside and formularize it
  localparam ABUF_PTR_W = (ABUF_SZE > 1) ? $clog2(ABUF_SZE) : 1;
  typedef logic [ABUF_PTR_W-1:0] abuf_ptr_t;

  abuf_ptr_t abuf_wptr, abuf_rptr;
  logic [act.DAT_W-1:0] abuf [0:ABUF_SZE-1], abuf_rdat;

  always_ff @(posedge clk) begin:ff_abuf
    if (!rstn) abuf <= '{default: 'x};
    else       abuf[abuf_wptr] <= (act.v_w) ? act.d_w : abuf[abuf_wptr];
  end:ff_abuf

  //FIXME: incrementation logic guards
  always_ff @(posedge clk) begin:ff_abuf_wptr
    if (!rstn) abuf_wptr <= '0;
    else       abuf_wptr <= (act.v_w) ? (abuf_wptr + 'd1) : abuf_wptr;
  end:ff_abuf_wptr

  always_ff @(posedge clk) begin:ff_abuf_rptr
    if (!rstn) abuf_rptr <= '0;
  end:ff_abuf_rptr

  // ------------------------------- COMPUTE ------------------------------- //
  always_ff @(posedge clk) begin:ff_compute
    if (!rstn) {cmp.psum_s, cmp.psum_v} <= '0;
    else begin:nrst
      if (act.v_w) begin
        /* verilator lint_off WIDTHEXPAND */
        cmp.psum_s <= (act.d_w * wbuf_rdat) + cmp.carr_n; // might not close timing
        /* verilator lint_on WIDTHEXPAND */
        cmp.psum_v <= '1;
      end
      else begin
        cmp.psum_s <= 'x;
        cmp.psum_v <= '0;
      end
    end:nrst
  end:ff_compute

endmodule
