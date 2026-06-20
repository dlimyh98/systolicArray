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

  // - buffer handling is tricky, problem is with the southmost layer's PE (worst-case)
  // - along Y_DIM, all PEs load their weights at the same time, but
  //   the activation data does not reach all PEs similarly (due to systolic nature)
  // - the northmost PE gets activation data first; ie. the more southerly your PE
  //   is located, the more buffering is required
  localparam RPTR_W = (WBUF_SZE > 1) ? $clog2(WBUF_SZE) : 1;
  typedef logic [RPTR_W-1:0] ptr_t;
  typedef logic [$clog2(AM_ROWS):0] cntr_t;

  ptr_t wptr, rptr;
  cntr_t cntr;
  logic wgt_wr;
  logic [wgt.DAT_W-1:0] buff [0:WBUF_SZE-1], buff_rdat;

  always_ff @(posedge clk) begin:ff_buff
    if (!rstn) buff <= '{default: 'x};
    else       buff[wptr] <= (wgt_wr) ? wgt.d_n : buff[wptr];
  end:ff_buff

  always_ff @(posedge clk) begin:ff_wptr
    if (!rstn) wptr <= '0;
    else begin:nrst
      casez ({wgt_wr, (wptr+'d1 == ptr_t'(WBUF_SZE))})
        2'b0z : wptr <= wptr;
        2'b10 : wptr <= wptr + 'd1;
        2'b11 : wptr <= '0;
      endcase
    end:nrst
  end:ff_wptr

  always_ff @(posedge clk) begin:ff_crptr
    if (!rstn) {cntr, rptr} <= '0;
    else begin:nrst
      if (act.v_w) begin:av
        if (cntr + 'd1 == cntr_t'(AM_ROWS)) begin:astrm_done
          cntr <= '0;
          rptr <= ( rptr+'d1 == ptr_t'(WBUF_SZE) ) ? '0 : (rptr + 'd1);
        end:astrm_done
        else begin:astrm_ndone
          cntr <= cntr + 'd1;
          rptr <= rptr;
        end:astrm_ndone
      end:av
    end:nrst
  end:ff_crptr

  assign buff_rdat = buff[rptr];
  assign wgt_wr = (wgt.c_n == 0) && wgt.v_n;

  always_ff @(posedge clk) begin:ff_compute
    if (!rstn) {cmp.psum_s, cmp.psum_v} <= '0;
    else begin:nrst
      if (act.v_w) begin
        /* verilator lint_off WIDTHEXPAND */
        cmp.psum_s <= (act.d_w * buff_rdat) + cmp.carr_n; // might not close timing
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
