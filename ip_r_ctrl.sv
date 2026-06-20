// vim: set ts=2 sw=2 et :

module ip_r_ctrl #(
  parameter RM_ROWS,
  parameter RM_COLS,
  parameter RM_NUM,
  parameter ZZZ = 0
) (
  result_if.mem  res[0:RM_COLS-1],
  input clk,
  input rstn,
  output logic rvld_pulse
);

  localparam DAT_W = res[0].DAT_W;
  localparam NPTR_W = (RM_NUM > 1) ? $clog2(RM_NUM) : 1;
  localparam RPTR_W = (RM_ROWS > 1) ? $clog2(RM_ROWS) : 1;
  typedef logic [NPTR_W-1:0] nptr_t;
  typedef logic [RPTR_W-1:0] rptr_t;

  logic [DAT_W-1:0] mem [0:RM_COLS-1][0:RM_ROWS-1];
  rptr_t rptr [0:RM_COLS-1], rptr_n [0:RM_COLS-1];

  for (genvar c=0; c<RM_COLS; c++) begin:gc
    always_ff @(posedge clk) begin:ff_rptr
      if (!rstn) rptr[c] <= '0;
      else       rptr[c] <= rptr_n[c];
    end:ff_rptr

    always_comb begin:cb_rptr
      rptr_n[c] = (res[c].v) ? rptr[c] + 'd1 : rptr[c];
    end:cb_rptr

    always_ff @(posedge clk) begin:ff_mem
      if (!rstn) mem[c] <= '{default: 'x};
      else begin:nrst
        if (res[c].v)
          mem[c][rptr[c]] = res[c].d;
      end:nrst
    end:ff_mem
  end:gc

  // output valid when an arbitrary matmul is completed
  always_ff @(posedge clk) begin
    if (!rstn) rvld_pulse <= '0;
    else       rvld_pulse <= (rptr[RM_COLS-1] == rptr_t'(RM_ROWS-1));
  end

endmodule
