// vim: set ts=2 sw=2 et :

module ip_pe #(
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

  logic [wgt.DAT_W-1:0] ppbuf[0:1]; // ping-pong
  logic wptr, rptr;
  logic wgt_wr;

  always_ff @(posedge clk) begin:ff_pp_ctrl
    if (!rstn) begin:rst
      wptr <= '0; //NB: arbitrary
      ppbuf <= '{default: 'x};
    end:rst
    else begin:nrst
      wptr <= (wgt_wr) ^ wptr;
      if (wgt_wr) ppbuf[wptr] <= wgt.d_n;
    end:nrst
  end:ff_pp_ctrl

  always_comb begin:cb_pp_ctrl
    wgt_wr = (wgt.c_n == 0) && wgt.v_n;
    rptr = !wptr;
  end:cb_pp_ctrl

  always_ff @(posedge clk) begin:ff_compute
    if (!rstn) {cmp.psum_s, cmp.psum_v} <= '0;
    else begin:nrst
      if (act.v_w) begin
        /* verilator lint_off WIDTHEXPAND */
        cmp.psum_s <= (act.d_w * ppbuf[rptr]) + cmp.carr_n; // might not close timing
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
