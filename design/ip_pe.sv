// vim: set ts=2 sw=2 et :

module ip_pe #(
  parameter AM_ROWS,
  parameter WBUF_SZE,
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

  // ------------------------------- WEIGHT BUFFER ------------------------------- //
  // - weight buffer handling is tricky, problem is with the southmost layer's PE (worst-case)
  // - along Y_DIM, all PEs load their weights at the same time, but
  //   the activation data does not reach all PEs similarly (due to systolic nature)
  // - the northmost PE gets activation data first; ie. the more southerly your PE
  //   is located, the more buffering of your weights is required
  // - example is an (8x2) matmul (2x2)
  localparam WBUF_PTR_W = (WBUF_SZE > 1) ? $clog2(WBUF_SZE) : 1;
  typedef logic [WBUF_PTR_W-1:0] wbuf_ptr_t;
  typedef logic [$clog2(AM_ROWS):0] amr_cntr_t;

  wbuf_ptr_t wbuf_wptr, wbuf_rptr;
  amr_cntr_t wbuf_cntr;
  logic wgt_wr;
  logic [wgt.DAT_W-1:0] wbuf [0:WBUF_SZE-1], wbuf_rdat;

  always_ff @(posedge clk) begin:ff_wbuf
    if (!rstn) wbuf <= '{default: 'x};
    else       wbuf[wbuf_wptr] <= (wgt_wr) ? wgt.d_n : wbuf[wbuf_wptr];
  end:ff_wbuf

  always_ff @(posedge clk) begin:ff_wbuf_wptr
    if (!rstn) wbuf_wptr <= '0;
    else begin:nrst
      casez ({wgt_wr, (wbuf_wptr+'d1 == wbuf_ptr_t'(WBUF_SZE))})
        2'b0z : wbuf_wptr <= wbuf_wptr;
        2'b10 : wbuf_wptr <= wbuf_wptr + 'd1;
        2'b11 : wbuf_wptr <= '0;
      endcase
    end:nrst
  end:ff_wbuf_wptr

  always_ff @(posedge clk) begin:ff_wbuf_rptr
    if (!rstn) {wbuf_cntr, wbuf_rptr} <= '0;
    else begin:nrst
      if (act.v_w) begin:av
        if (wbuf_cntr + 'd1 == amr_cntr_t'(AM_ROWS)) begin:astrm_done
          wbuf_cntr <= '0;
          wbuf_rptr <= ( wbuf_rptr+'d1 == wbuf_ptr_t'(WBUF_SZE) ) ? '0 : (wbuf_rptr + 'd1);
        end:astrm_done
        else begin:astrm_ndone
          wbuf_cntr <= wbuf_cntr + 'd1;
          wbuf_rptr <= wbuf_rptr;
        end:astrm_ndone
      end:av
    end:nrst
  end:ff_wbuf_rptr

  assign wbuf_rdat = wbuf[wbuf_rptr];
  assign wgt_wr = (wgt.c_n == 0) && wgt.v_n;

  // ------------------------------- ACTIVATION BUFFER ------------------------------- //
  // TODO: this functionality is not implemented yet
  // - Inverse problem of weight buffer. Consider a (2x3) matmul (3x1) scenario.
  // - Intuitively, the time spent streaming W values down a column of PEs is larger
  //   than the time spent streaming A values across a row of PEs.
  // - Therefore, the A values can be streamed in before the W values for it have even been loaded
  // - Buffering the W values will not help us here, we need to buffer the A values
  // - TODO: the worst case scenario is actually the northwest most PE, contrast this with weight buffer soln
  //   (is it really?)

  // i think no need cntr. Every streamed in A value is "hit" once against a corresponding B

  // ABUF_SZE=1 should work for AM_ROWS >= Y_DIM
  localparam ABUF_SZE = 3; // TODO: bring outside and formularize it
  localparam ABUF_PTR_W = (ABUF_SZE > 1) ? $clog2(ABUF_SZE) : 1;
  typedef logic [ABUF_PTR_W-1:0] abuf_ptr_t;

  abuf_ptr_t abuf_wptr, abuf_rptr;
  logic [act.DAT_W-1:0] abuf [0:ABUF_SZE-1], abuf_rdat;

  typedef logic [31:0] wcrd_t; //FIXME: formularize width
  wcrd_t wcrd;

  always_ff @(posedge clk) begin
    if (!rstn) wcrd <= '0; //FIXME: should reset to 'x, then init to value on first wgt_wr received
    else begin:nrst
      case({act.v_w, wgt_wr})
        2'b00 : wcrd <= wcrd;
        2'b01 : wcrd <= wcrd + wcrd_t'(AM_ROWS);
        2'b10 : wcrd <= wcrd - 'd1; //FIXME: is this safe? possible to underflow if many A flow in before B?
        2'b11 : wcrd <= wcrd + wcrd_t'(AM_ROWS) - 'd1;
      endcase
    end:nrst
  end


  // stall logic
  // if stall, buffer activation data into abuf
  // we can stall for two reasons
  // 1. W values not ready yet when A streams in
  // 2. carr_n values not ready yet when A streams in (eg. noh-upstream PE stalls on cycle t. It still forwards act data to
  // reach on cycle t+1, but north PE only forwards it's psum on cycle t+2)
  logic stall, stall_q;
  assign stall = (wcrd == '0) && wgt_wr_q;

  always_ff @(posedge clk) begin
    if (!rstn) stall_q <= '0;
    else if (stall) stall_q <= '1; // once stalled, remain stalled as no backpressure supported
    // TODO: must be someway of bringing it back down!
  end

  logic wgt_wr_q;
  always_ff @(posedge clk) begin
    if (!rstn) wgt_wr_q <= '0;
    else if (wgt_wr) wgt_wr_q <= '1;
  end

  always_ff @(posedge clk) begin:ff_abuf
    if (!rstn) abuf <= '{default: 'x};
    else       abuf[abuf_wptr] <= (stall || stall_q) ? act.d_w : abuf[abuf_wptr];
  end:ff_abuf

  //FIXME: incrementation logic guards
  always_ff @(posedge clk) begin:ff_abuf_wptr
    if (!rstn) abuf_wptr <= '0;
    else       abuf_wptr <= (stall) ? (abuf_wptr + 'd1) : abuf_wptr;
  end:ff_abuf_wptr

  always_ff @(posedge clk) begin:ff_abuf_rptr
    if (!rstn) abuf_rptr <= '0;
    else       abuf_rptr <= (stall_q) ? abuf_rptr + 'd1 : abuf_rptr;
  end:ff_abuf_rptr
  assign abuf_rdat = abuf[abuf_rptr];

  // ------------------------------- COMPUTE ------------------------------- //
  logic [act.DAT_W-1:0] act_dat;
  //assign act_dat = (stall) ? abuf_rdat : act.d_w;

  assign act_dat = (stall_q) ? abuf_rdat : act.d_w;

  logic stall_level; //TODO: something to bring this down

  //TODO: this is xor
  // act.v_w  stall
  //   0        0        low 
  //   0        1     clear stalled buffer, will be high
  //   1        0     next cycle high
  //   1        1    low, current A cannot be utilised

//    always_ff @(posedge clk) begin:ff_strm
//      if (!rstn) {cmp.psum_s, cmp.psum_v_s, cmp.s_s} <= '0;
//      else begin:nrst
//        /* verilator lint_off WIDTHEXPAND */
//        cmp.psum_s <= (act_dat * wbuf_rdat) + cmp.carr_n;
//        /* verilator lint_on WIDTHEXPAND */
//        cmp.psum_v_s <= cmp.psum_v_n;
//        cmp.s_s <= stall;
//        case ({act.v_w, stall})
//          2'b00 : cmp.psum_v_s <= '0;
//          2'b01 : cmp.psum_v_s <= '1;
//          2'b10 : cmp.psum_v_s <= '1;
//          2'b11 : cmp.psum_v_s <= '0;
//        endcase
//      end:nrst
//    end:ff_strm

  localparam PBUF_SZE = 3; // TODO: buffer depth increases as we progress south
  localparam PBUF_PTR_W = (PBUF_SZE > 1) ? $clog2(PBUF_SZE) : 1;
  typedef logic [PBUF_PTR_W-1:0] pbuf_ptr_t;

  always_ff @(posedge clk) begin
    if (!rstn) stall_level <= '0;
    else if (cmp.s_n) stall_level <= '1;
  end

  pbuf_ptr_t pbuf_wptr, pbuf_rptr;
  logic [(act.DAT_W*2)-1:0] pbuf [0:ABUF_SZE-1], pbuf_rdat;

  always_ff @(posedge clk) begin:ff_pbuf
    if (!rstn) pbuf <= '{default: 'x};
    else       pbuf[pbuf_wptr] <= (cmp.s_n || stall_level) ? (act_dat * wbuf_rdat) : pbuf[pbuf_wptr];
  end:ff_pbuf

  always_ff @(posedge clk) begin
    if (!rstn) pbuf_wptr <= '0;
    else       pbuf_wptr <= (cmp.s_n || stall_level) ? pbuf_wptr + 'd1 : pbuf_wptr;
  end

  always_ff @(posedge clk) begin
    if (!rstn) pbuf_rptr <= '0;
    else       pbuf_rptr <= '0;
  end
  assign pbuf_rdat = pbuf[pbuf_rptr];

  typedef enum logic [2:0] {
    S_ID, // idle
    S_NS, // no stall
    S_SS, // sent stall
    S_RS, // received stall
    S_CB, // clear buffers
    S_IV  // invalid
  } fsm_t;
  fsm_t fsm, fsm_n;

  always_ff @(posedge clk) begin
    if (!rstn) fsm <= S_ID;
    else       fsm <= fsm_n;
  end

  always_comb begin
    fsm_n = fsm;

    if (stall) begin
      // psum_v must be low on next cycle
      // on current cycle, need to buffer incoming A data
      fsm_n = S_SS;
    end
    else if (cmp.s_n) begin
      // psum data from upstream on this cycle is invalid
      // need to calculate current cycle A*W, and store them to buffer
      fsm_n = S_RS;
    end

    case (fsm)
      S_SS : fsm_n = S_CB; //TODO: is this right?
      S_RS : fsm_n = S_CB;
      S_CB : fsm_n = S_CB; // need to exit S_CB eventually
      default: fsm_n = S_IV;
    endcase
  end

  logic pbuf_wr, pbuf_rd;

  always_ff @(posedge clk) begin
    cmp.psum_s <= 'x;

    case (fsm)
      S_RS: begin
        pbuf_wr = 1'b1;
      end
      S_CB: begin
        pbuf_wr = 1'b1;
        pbuf_rd = 1'b1;
      end
    endcase
  end


//  always_ff @(posedge clk) begin:ff_strm
//    if (!rstn) {cmp.psum_s, cmp.psum_v_s, cmp.s_s} <= '0;
//    else begin:nrst
//      if (!stall_level) begin
//        /* verilator lint_off WIDTHEXPAND */
//        cmp.psum_s <= (act_dat * wbuf_rdat) + cmp.carr_n;
//        /* verilator lint_on WIDTHEXPAND */
//        cmp.psum_v_s <= cmp.psum_v_n;
//        cmp.s_s <= stall;
//        case ({act.v_w, stall})
//          2'b00 : cmp.psum_v_s <= '0;
//          2'b01 : cmp.psum_v_s <= '1;
//          2'b10 : cmp.psum_v_s <= '1;
//          2'b11 : cmp.psum_v_s <= '0;
//        endcase
//      end
//      else begin
//        /* verilator lint_off WIDTHEXPAND */
//        cmp.psum_s <= (pbuf_rdat) + cmp.carr_n;
//        /* verilator lint_on WIDTHEXPAND */
//        cmp.psum_v_s <= cmp.psum_v_n;
//        cmp.s_s <= stall;
//      end
//    end:nrst
//  end:ff_strm

endmodule
