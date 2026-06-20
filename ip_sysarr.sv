// vim: set ts=2 sw=2 et :

module ip_sysarr #(
  parameter AM_ROWS,
  parameter X_DIM,
  parameter Y_DIM,
  parameter ZZZ = 0
) (
  weight_if.pe      ext_w[0:X_DIM-1],
  activation_if.pe  ext_a[0:Y_DIM-1],
  result_if.sar     ext_r[0:X_DIM-1],
  input clk, rstn
);
  localparam DAT_W = ext_w[0].DAT_W;
  localparam CRD_N = ext_w[0].CRD_N;
  localparam MAX_PSUM_W = ext_r[0].DAT_W;

  // NB: dimensions [XDIM][Y_DIM] of interconnects are unused. they
  // are added to work around a vrltr issue with oob-driver, under gy_int/gx_int loop

  // weight {d,c,v} interconnect
  wire [DAT_W-1:0] grd_w_d [0:X_DIM][0:Y_DIM];
  wire [CRD_N-1:0] grd_w_c [0:X_DIM][0:Y_DIM];
  wire             grd_w_v [0:X_DIM][0:Y_DIM];

  // activation {d,v} interconnect
  wire [DAT_W-1:0] grd_a_d [0:X_DIM][0:Y_DIM];
  wire             grd_a_v [0:X_DIM][0:Y_DIM];

  // comp interconnect
  // z-index is larger than required (MAX_PSUM_W), to work around vrltr issue
  wire [MAX_PSUM_W-1:0] grd_p_carr_n [0:X_DIM][0:Y_DIM];

  genvar x,y;
  generate
    for (y=0; y<Y_DIM; y++) begin:gy_ext
      assign grd_a_d[0][y] = ext_a[y].d_w;
      assign grd_a_v[0][y] = ext_a[y].v_w;
    end:gy_ext

    for (x=0; x<X_DIM; x++) begin:gx_ext
      assign grd_w_d[x][0] = ext_w[x].d_n;
      assign grd_w_c[x][0] = ext_w[x].c_n;
      assign grd_w_v[x][0] = ext_w[x].v_n;
      assign grd_p_carr_n[x][0] = '0;
    end:gx_ext

    for (y=0; y<Y_DIM; y++) begin:gy_int
      localparam CARR_W = (y==0) ? 0 : (2*DAT_W)+(1*y)-1;
      localparam PSUM_W = (y==0) ? (2*DAT_W) : CARR_W+1;

      for (x=0; x<X_DIM; x++) begin:gx_int
        weight_if #(.DAT_W, .CRD_N) w ();
        assign w.d_n = grd_w_d[x][y];
        assign grd_w_d[x][y+1] = w.d_s;
        assign w.c_n = grd_w_c[x][y];
        assign grd_w_c[x][y+1] = w.c_s;
        assign w.v_n = grd_w_v[x][y];
        assign grd_w_v[x][y+1] = w.v_s;

        activation_if #(.DAT_W) a();
        assign a.d_w = grd_a_d[x][y];
        assign grd_a_d[x+1][y] = a.d_e;
        assign a.v_w = grd_a_v[x][y];
        assign grd_a_v[x+1][y] = a.v_e;

        compute_if #(.CARR_W, .PSUM_W) c();
        /* verilator lint_off WIDTHTRUNC */
        assign c.carr_n = grd_p_carr_n[x][y];
        /* verilator lint_on WIDTHTRUNC */
        /* verilator lint_off WIDTHEXPAND */
        assign grd_p_carr_n[x][y+1] = c.psum_s;
        /* verilator lint_on WIDTHEXPAND */

        localparam WBUF_SZE = (AM_ROWS - Y_DIM) + (y) + 1;
        ip_pe #(
          .AM_ROWS,
          .WBUF_SZE,
          .ZZZ (0)
        ) i_pe (
          .wgt ( w ),
          .act ( a ),
          .cmp ( c ),
          .clk, .rstn
        );
        if (y == Y_DIM-1) begin:sysarr_out
          assign ext_r[x].v = c.psum_v;
          assign ext_r[x].d = c.psum_s;
        end:sysarr_out
      end:gx_int
    end:gy_int
  endgenerate

endmodule
