// vim: set ts=2 sw=2 et :

module tb_top;

  // test square matrix (3x3)
  // test nonsquare matrix (eg. 2x3 x 3x1)

  // activation matrix dimensions
  parameter AM_ROWS = 3;
  parameter AM_COLS = 3;
  // weight matrix dimensions
  localparam WM_ROWS = AM_COLS;
  parameter WM_COLS = 3;
  // systolic array dimensions
  localparam Y_DIM = AM_COLS;
  localparam X_DIM = WM_COLS;

  parameter DAT_W = 4;
  weight_if     #( .DAT_W, .CRD_N($clog2(Y_DIM)) ) if_w [0:X_DIM-1] ();
  activation_if #( .DAT_W                        ) if_a [0:Y_DIM-1] ();

  logic clk;
  logic rstn; // assume sync

  wire ssa;
  ip_a_ctrl #(
    .AM_ROWS,
    .AM_COLS,
    .ZZZ (0)
  ) i_a_ctrl (
    .ext_a ( if_a ),
    .clk, .rstn,
    .ssa
  );

  ip_w_ctrl #(
    .WM_ROWS,
    .WM_COLS,
    .Y_DIM,
    .ZZZ (0)
  ) i_w_ctrl (
    .ext_w ( if_w ),
    .clk, .rstn,
    .ssa
  );

  ip_sysarr #(
    .X_DIM,
    .Y_DIM,
    .ZZZ (0)
  ) i_sysarr (
    .ext_w ( if_w ),
    .ext_a ( if_a ),
    .clk, .rstn
  );

  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_top);
  end

  initial begin
    clk = '0;
    rstn = '0;
    repeat(10) @(negedge clk);
    rstn = '1;
    repeat(20) @(negedge clk);
    $finish;
  end

  always #(10) clk = ~clk;

endmodule
