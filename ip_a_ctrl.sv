// vim: set ts=2 sw=2 et :

module ip_a_ctrl #(
  parameter AM_ROWS,
  parameter AM_COLS,
  parameter AM_NUM,
  localparam Y_DIM = AM_COLS,
  parameter ZZZ    = 0
) (
  activation_if.ct ext_a[0:Y_DIM-1],
  input clk,
  input rstn,
  input ssa
);

  localparam DAT_W = ext_a[0].DAT_W;
  logic [DAT_W-1:0] gen_activation [0:AM_NUM-1][0:AM_COLS-1][0:AM_ROWS-1];

  // pointers across Y_DIM of systolic array (activation travels west-east)
  // each pointer holds reference to value(s) of the activation matrix
  localparam NPTR_W = (AM_NUM > 1) ? $clog2(AM_NUM) : 1;
  localparam RPTR_W = (AM_ROWS > 1) ? $clog2(AM_ROWS) : 1;
  typedef logic [NPTR_W-1:0] nptr_t;
  typedef logic [RPTR_W-1:0] rptr_t;
  nptr_t nptr [0:Y_DIM-1], nptr_n;
  rptr_t rptr [0:Y_DIM-1], rptr_n; // row pointer

  typedef enum logic [1:0] {
    S_I, // idle
    S_A, // active
    S_D, // done
    S_X  // invalid
  } afsm_t;
  afsm_t afsm, afsm_n;

  always_ff @(posedge clk) begin:ff_afsm
    if (!rstn) afsm <= S_I;
    else       afsm <= afsm_n;
  end:ff_afsm

  always_comb begin:cb_afsm
    afsm_n = afsm;
    case (afsm)
      S_I : afsm_n = (ssa) ? S_A : S_I; // triggered via ip_w_ctrl
      /*verilator lint_off WIDTHEXPAND */
      S_A : afsm_n = ((nptr[0] == AM_NUM-1) && rptr[0] == AM_ROWS-1) ? S_D : S_A;
      /*verilator lint_on WIDTHEXPAND */
      S_D : afsm_n = S_D;
      default: afsm_n = S_X;
    endcase
  end:cb_afsm

  always_ff @(posedge clk) begin:ff_ctrl
    if (!rstn) {nptr[0], rptr[0]} <= '0;
    else begin:nrst
      nptr[0] <= nptr_n;
      rptr[0] <= rptr_n;
    end:nrst
  end:ff_ctrl

  logic is_active;
  assign is_active = (afsm == S_A);
  always_comb begin:cb_ctrl
    rptr_n = (is_active) ? rptr[0] + 'd1 : rptr[0];
    nptr_n = nptr[0];

    if (rptr[0] == rptr_t'(AM_ROWS-1) && is_active) begin:row_done
      rptr_n = '0;
      nptr_n = nptr[0] + 'd1;
    end:row_done
  end:cb_ctrl

  assign ext_a[0].v_w = is_active;
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
    for (int n=0; n<AM_NUM; n++) begin:gn
      aval = (n==0 || n==2) ? 'd12 : 'd1;
      for (int r=0; r<AM_ROWS; r++) begin:gr
        for (int c=0; c<AM_COLS; c++) begin:gc
          gen_activation[n][c][r] = aval;
          aval = aval + 'd1; //FIXME: will overflow if loop iters not controlled
        end:gc
      end:gr
    end:gn
  end:init_activations

endmodule
