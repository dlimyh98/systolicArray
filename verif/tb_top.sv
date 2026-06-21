// vim: set ts=2 sw=2 et :

// verification for A*W systolic-array matmul

module tb_top;

  // - currently (AM_ROWS < Y_DIM) is not supported
  // - eg. failing testcase = (2x3) matmul (3x1)
  //       worse failure is (2x4) matmul (4x1)
  // - currently looking into adding abuf in PE to solve this
  // - plausible alternative is changing A/W stream scheduling

  // ----------------- PARAMETERS ----------------- //
  // activation matrix dimensions
  parameter AM_ROWS = 2;
  parameter AM_COLS = 3;
  parameter AM_NUM  = 2;
  // weight matrix dimensions
  localparam WM_ROWS = AM_COLS;
  parameter WM_COLS = 1;
  localparam WM_NUM = AM_NUM; // assume no broadcast feature (ie. one A to many W)
  // systolic array dimensions
  localparam Y_DIM = AM_COLS;
  localparam X_DIM = WM_COLS;
  // result matrix dimensions
  localparam RM_ROWS = AM_ROWS;
  localparam RM_COLS = WM_COLS;
  localparam RM_NUM  = AM_NUM;

  parameter DAT_W = 6;
  localparam CRD_N = (Y_DIM > 1) ? $clog2(Y_DIM) : 1;
  localparam MAX_PSUM_W = (DAT_W*2) + (Y_DIM-1);

  // ----------------- INTERFACES ----------------- //
  weight_if     #( .DAT_W, .CRD_N     ) if_w [0:X_DIM-1] ();
  activation_if #( .DAT_W             ) if_a [0:Y_DIM-1] ();
  result_if     #( .DAT_W(MAX_PSUM_W) ) if_r [0:X_DIM-1] ();

  // ----------------- DUT ----------------- //
  logic clk;
  logic rstn; // assume sync

  wire ssa;
  ip_a_ctrl #(
    .AM_ROWS,
    .AM_COLS,
    .AM_NUM,
    .ZZZ (0)
  ) i_a_ctrl (
    .ext_a ( if_a ),
    .clk, .rstn,
    .ssa
  );

  ip_w_ctrl #(
    .WM_ROWS,
    .WM_COLS,
    .WM_NUM,
    .Y_DIM,
    .ZZZ (0)
  ) i_w_ctrl (
    .ext_w ( if_w ),
    .clk, .rstn,
    .ssa
  );

  wire ares_v;
  wire [MAX_PSUM_W-1:0] ares_d [0:RM_COLS-1][0:RM_ROWS-1];
  ip_r_ctrl #(
    .RM_ROWS,
    .RM_COLS,
    .RM_NUM,
    .ZZZ (0)
  ) i_r_ctrl (
    .sres   ( if_r ),
    .ares_v,
    .ares_d,
    .clk, .rstn
  );

  ip_sysarr #(
    .AM_ROWS,
    .X_DIM,
    .Y_DIM,
    .ZZZ (0)
  ) i_sysarr (
    .ext_w ( if_w ),
    .ext_a ( if_a ),
    .ext_r ( if_r ),
    .clk, .rstn
  );

  // ----------------- SCOREBOARD ----------------- //
  logic [MAX_PSUM_W-1:0] sbrd [0:RM_COLS-1][0:RM_ROWS-1];

  initial begin:sbrd_checker
    int n = 0;
    do begin
      @(negedge clk); //FIXME: inefficient to poll on every negedge, but it works

      // NB: ares_v possible to be asserted b2b (edge case of 1x1 systolic array)
      if (ares_v) begin:av
        // compute scoreboard
        for (int rc=0; rc<RM_COLS; rc++) begin:grc
          for (int rr=0; rr<RM_ROWS; rr++) begin:grr
            sbrd[rc][rr] = '0;
            for (int ac=0; ac<AM_COLS; ac++)
              sbrd[rc][rr] += i_a_ctrl.gen_activation[n][ac][rr] *
                              i_w_ctrl.gen_weights[n][rc][ac];
          end:grr
        end:grc
        // do comparison
        assert(sbrd === ares_d) else $warning("FAIL: mismatch at n=%0d", n);
        n++;
      end:av
    end while (n < AM_NUM);

    repeat(5) @(negedge clk);
    $display("PASS\n");
    $finish(); //FIXME: timeout support, sim will hang if RTL doesn't iterate thru all n
  end:sbrd_checker

  // ----------------- VERIF ARTIFACTS ----------------- //
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_top);
  end

  initial begin
    clk = '0;
    rstn = '0;
    repeat(10) @(negedge clk);
    rstn = '1;
  end

  always #(10) clk = ~clk;

endmodule
