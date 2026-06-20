// vim: set ts=2 sw=2 et :

module ip_r_ctrl #(
  parameter RM_ROWS,
  parameter RM_COLS,
  parameter RM_NUM,
  parameter ZZZ = 0
) (
  result_if.mem      sres[0:RM_COLS-1],
  output logic       ares_v,
  output [DAT_W-1:0] ares_d [0:RM_COLS-1][0:RM_ROWS-1],
  input clk,
  input rstn
);

  localparam DAT_W = sres[0].DAT_W;
  localparam NPTR_W = (RM_NUM > 1) ? $clog2(RM_NUM) : 1;
  localparam RPTR_W = (RM_ROWS > 1) ? $clog2(RM_ROWS) : 1;
  typedef logic [NPTR_W-1:0] nptr_t;
  typedef logic [RPTR_W-1:0] rptr_t;

  logic [DAT_W-1:0] mem [0:RM_COLS-1][0:RM_ROWS-1];
  rptr_t rptr [0:RM_COLS-1], rptr_n [0:RM_COLS-1];

  for (genvar c=0; c<RM_COLS; c++) begin:gen_rptrc
    always_ff @(posedge clk) begin:ff_rptr
      if (!rstn) rptr[c] <= '0;
      else       rptr[c] <= rptr_n[c];
    end:ff_rptr

    always_comb begin:cb_rptr
      casez({sres[c].v, (rptr[c] + 'd1 == rptr_t'(RM_ROWS))})
        2'b0z : rptr_n[c] = rptr[c];
        2'b10 : rptr_n[c] = rptr[c] + 'd1;
        2'b11 : rptr_n[c] = '0;
      endcase
    end:cb_rptr

    always_ff @(posedge clk) begin:ff_mem
      if (!rstn) mem[c] <= '{default: 'x};
      else begin:nrst
        if (sres[c].v)
          mem[c][rptr[c]] = sres[c].d;
      end:nrst
    end:ff_mem
  end:gen_rptrc

  // - for an arbitrary matmul, latency from first valid output from rptr[0] (ie. leftmost)
  //   to last valid output from rptr[RM_COLS-1] (ie. rightmost) is AM_ROWS+WM_COLS-2
  // - AM_ROWS/WM_COLS are related to RM_*, so let's use that instead
  // - NB: -2 accounts for systolic filling
  localparam LTE = RM_ROWS + RM_COLS - 2;

  for (genvar c=0; c<RM_COLS; c++) begin:gen_memc
    for (genvar r=0; r<RM_ROWS; r++) begin:gen_memr

      localparam LTI = LTE - c - r;
      logic [DAT_W-1:0] tmp [0:LTI-1];
      for (genvar lt=0; lt<LTI; lt++) begin:gen_memlt
        always_ff @(posedge clk) begin:ff_dly
          tmp[lt] <= (lt==0) ? mem[c][r] : tmp[lt-1];
        end:ff_dly
      end:gen_memlt
      always_ff @(posedge clk) begin:ff_out
        ares_d[c][r] <= tmp[LTI-1];
      end:ff_out

    end:gen_memr
  end:gen_memc
  assign ares_d[RM_COLS-1][RM_ROWS-1] = mem[RM_COLS-1][RM_ROWS-1];

  // aggregated output valid when an arbitrary matmul is completed, which
  // occurs when last element of bottom right (south-east) PE is streamed out
  always_ff @(posedge clk) begin
    if (!rstn) ares_v <= '0;
    else       ares_v <= (RM_ROWS > 1) ? (rptr[RM_COLS-1] == rptr_t'(RM_ROWS-1))
                                       : sres[RM_COLS-1].v;
  end

endmodule
