// vim: set ts=2 sw=2 et :

module ip_w_ctrl #(
  parameter WM_ROWS,
  parameter WM_COLS,
  parameter Y_DIM,
  localparam X_DIM = WM_COLS,
  parameter ZZZ    = 0
) (
  weight_if.ct ext_w[0:X_DIM-1],
  input clk,
  input rstn,
  output logic ssa // start streaming activation data
);

  localparam DAT_W = ext_w[0].DAT_W;
  localparam NUM_W_MATRICES = 2;
  logic [DAT_W-1:0] gen_weights [0:NUM_W_MATRICES-1][0:WM_COLS-1][0:WM_ROWS-1];

  // pointers across X_DIM of systolic array (weights travel north-south)
  // each pointer holds reference to value(s) of the weight matrix
  localparam NPTR_W = (NUM_W_MATRICES > 1) ? $clog2(NUM_W_MATRICES) : 1;
  localparam RPTR_W = (WM_ROWS > 1) ? $clog2(WM_ROWS) : 1;
  typedef logic [NPTR_W-1:0] nptr_t;
  typedef logic [RPTR_W-1:0] rptr_t;

  nptr_t nptr [0:X_DIM-1], nptr_n;
  rptr_t rptr [0:X_DIM-1], rptr_n; // row pointer

  typedef enum logic [1:0] {
    S_I, // idle
    S_A, // active
    S_D, // done
    S_X  // invalid
  } wfsm_t;
  wfsm_t wfsm, wfsm_n;

  always_ff @(posedge clk) begin:ff_wfsm
    if (!rstn) wfsm <= S_I;
    else       wfsm <= wfsm_n;
  end:ff_wfsm

  always_comb begin:cb_wfsm
    wfsm_n = wfsm;
    case (wfsm)
      S_I : wfsm_n = (rstn) ? S_A : S_I; // activated out of reset
      /*verilator lint_off WIDTHEXPAND */
      S_A : wfsm_n = ((nptr[0] == NUM_W_MATRICES-1) && rptr[0] == '0) ? S_D : S_A;
      /*verilator lint_on WIDTHEXPAND */
      S_D : wfsm_n = S_D;
      default: wfsm_n = S_X;
    endcase
  end:cb_wfsm

  logic is_active;
  assign is_active = (wfsm == S_A);

  // signal to ip_a_ctrl to begin streaming activation data
  // the latency is a function of the systolic array's Y_DIM
  logic [Y_DIM-1:0] ssa_d;
  for (genvar y=0; y<Y_DIM; y++) begin:gen_ssa
    always_ff @(posedge clk) begin
      if (!rstn) ssa_d[y] <= '0;
      else       ssa_d[y] <= (y==0) ? is_active : ssa_d[y-1];
    end
  end:gen_ssa
  assign ssa = ssa_d[Y_DIM-1];

  always_ff @(posedge clk) begin:ff_ctrl
    if (!rstn) begin:rst
      nptr[0] <= '0;
      rptr[0] <= rptr_t'(WM_ROWS-1);
    end:rst
    else begin:nrst
      nptr[0] <= nptr_n;
      rptr[0] <= rptr_n;
    end:nrst
  end:ff_ctrl

  always_comb begin:cb_ctrl
    rptr_n = (is_active) ? rptr[0] - 'd1 : rptr[0];
    nptr_n = nptr[0];

    if (rptr[0] == 0) begin
      rptr_n = rptr_t'(WM_ROWS-1);
      nptr_n = nptr[0] + 'd1;
    end
  end:cb_ctrl

  assign ext_w[0].v_n = is_active;
  assign ext_w[0].d_n = gen_weights[nptr[0]][0][rptr[0]];
  assign ext_w[0].c_n = (ext_w[0].v_n) ? rptr[0] : 'x;
  for (genvar x=1; x<X_DIM; x++) begin
    always_ff @(posedge clk) begin
      nptr[x] <= nptr[x-1];
      rptr[x] <= rptr[x-1];
      ext_w[x].v_n <= ext_w[x-1].v_n;
      ext_w[x].c_n <= ext_w[x-1].c_n;
    end
    assign ext_w[x].d_n = gen_weights[nptr[x]][x][rptr[x]];
  end

  // let's cheat, we'll store weights to controller memory first
  // non-synthesizable, need to replace
  initial begin:init_weights
    logic [DAT_W-1:0] wval;
    for (int n=0; n<NUM_W_MATRICES; n++) begin:gn
      wval = 'd22;
      for (int r=0; r<WM_ROWS; r++) begin:gr
        for (int c=0; c<WM_COLS; c++) begin:gc
          gen_weights[n][c][r] = wval;
          wval = wval + 'd1; //FIXME: will overflow if loop iters not controlled
        end:gc
      end:gr
    end:gn
  end:init_weights

endmodule
