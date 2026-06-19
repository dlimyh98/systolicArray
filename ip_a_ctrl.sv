// vim: set ts=2 sw=2 et :

module ip_a_ctrl #(
  parameter AM_ROWS,
  parameter AM_COLS,
  localparam Y_DIM = AM_COLS,
  parameter ZZZ    = 0
) (
  activation_if.ct ext_a[0:Y_DIM-1],
  input clk,
  input rstn,
  input ssa
);

  localparam DAT_W = ext_a[0].DAT_W;
  localparam NUM_A_MATRICES = 2;
  logic [DAT_W-1:0] gen_activation [0:NUM_A_MATRICES-1][0:AM_COLS-1][0:AM_ROWS-1];

  // pointers across Y_DIM of systolic array (activation travels west-east)
  // each pointer holds reference to value(s) of the activation matrix
  logic [$clog2(NUM_A_MATRICES)-1:0] nptr [0:Y_DIM-1], nptr_n;
  logic [$clog2(AM_ROWS)-1:0] rptr [0:Y_DIM-1], rptr_n; // row pointer

  // ext_a[0], increment along the matrix 0th column (top-down)
  // ext_a[1], increment along the matrix 1st column (top-down)

  assign ext_a[0].d_w = gen_activation[nptr[0]][0][rptr[0]];

  always_ff @(posedge clk) begin:ff_ctrl
    if (!rstn) {nptr[0], rptr[0]} <= '0;
    else begin:nrst
      nptr[0] <= nptr_n;
      rptr[0] <= rptr_n;
    end:nrst
  end:ff_ctrl

  always_comb begin:cb_ctrl
    rptr_n = (ssa) ? rptr[0] + 'd1 : rptr[0];
    nptr_n = nptr[0];

    if (rptr[0] == AM_ROWS-1) begin
      rptr_n = '0;
      nptr_n = nptr[0] + 'd1;
    end
  end:cb_ctrl

  assign ext_a[0].v_w = ssa;
  assign ext_a[0].d_w = gen_activation[nptr[0]][0][rptr[0]];
  for (genvar y=1; y<Y_DIM; y++) begin
    always_ff @(posedge clk) begin
      nptr[y] <= nptr[y-1];
      rptr[y] <= rptr[y-1];
      ext_a[y].v_w <= ext_a[y-1].v_w;
    end
    assign ext_a[y].d_w = gen_activation[nptr[y]][y][rptr[y]];
  end

  // let's cheat, we'll store activations to controller memory first
  // non-synthesizable, need to replace
  initial begin:init_activations
    logic [DAT_W-1:0] aval;
    for (int n=0; n<NUM_A_MATRICES; n++) begin:gn
      aval = 'd12;
      for (int r=0; r<AM_ROWS; r++) begin:gr
        for (int c=0; c<AM_COLS; c++) begin:gc
          gen_activation[n][c][r] = aval;
          aval = aval + 'd1; //FIXME: will overflow if loop iters not controlled
        end:gc
      end:gr
    end:gn
  end:init_activations

endmodule
