// vim: set ts=2 sw=2 et :

interface weight_if #(
  parameter DAT_W = 8,
  parameter CRD_N = 3
) ();
  logic v_n, v_s;
  logic [CRD_N-1:0] c_n, c_s;
  logic [DAT_W-1:0] d_n, d_s;

  modport pe (input v_n, c_n, d_n,
              output v_s, c_s, d_s);

  modport ct (output v_n, c_n, d_n);
endinterface //weight_if

interface activation_if #(
  parameter DAT_W = 8
) ();
  logic v_w, v_e;
  logic [DAT_W-1:0] d_w, d_e;

  modport pe (input v_w, d_w,
              output v_e, d_e);

  modport ct (output v_w, d_w);
endinterface //activation_if

interface result_if #(
  parameter DAT_W = 8
) ();
  logic v;
  logic [DAT_W-1:0] d;

  modport sar (output v, d);
  modport mem (input v, d);
endinterface //result_if

interface compute_if #(
  parameter CARR_W = 8,
  parameter PSUM_W = 9
) ();
  /* verilator lint_off ASCRANGE */
  logic [CARR_W-1:0] carr_n;
  /* verilator lint_on ASCRANGE */

  logic [PSUM_W-1:0] psum_s;
  logic psum_v_s, psum_v_n;

  logic s_n, s_s; // stall

  modport pe (input carr_n, psum_v_n, s_n,
              output psum_s, psum_v_s, s_s);
endinterface //compute_if
