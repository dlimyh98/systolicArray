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
  //   is located, the more buffering is required
  localparam WBUF_PTR_W = (WBUF_SZE > 1) ? $clog2(WBUF_SZE) : 1;
  typedef logic [WBUF_PTR_W-1:0] wbuf_ptr_t;
  typedef logic [$clog2(AM_ROWS):0] wbuf_cntr_t;

  wbuf_ptr_t wbuf_wptr, wbuf_rptr;
  wbuf_cntr_t wbuf_cntr;
  logic wgt_wr;
  logic [wgt.DAT_W-1:0] wgtbuf [0:WBUF_SZE-1], wgtbuf_rdat;

  always_ff @(posedge clk) begin:ff_wgtbuf
    if (!rstn) wgtbuf <= '{default: 'x};
    else       wgtbuf[wbuf_wptr] <= (wgt_wr) ? wgt.d_n : wgtbuf[wbuf_wptr];
  end:ff_wgtbuf

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

  assign wgtbuf_rdat = wgtbuf[wbuf_rptr];
  assign wgt_wr = (wgt.c_n == 0) && wgt.v_n;

  // ------------------------------- COMPUTE ------------------------------- //
  always_ff @(posedge clk) begin:ff_compute
    if (!rstn) {cmp.psum_s, cmp.psum_v} <= '0;
    else begin:nrst
      if (act.v_w) begin
        /* verilator lint_off WIDTHEXPAND */
        cmp.psum_s <= (act.d_w * wgtbuf_rdat) + cmp.carr_n; // might not close timing
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
