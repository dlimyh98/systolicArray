COMPILE_CMD := verilator --quiet --binary --trace -F design/design.f -F verif/verif.f --top-module tb_top
SIM_CMD = ./obj_dir/Vtb_top

# NB: sweep test requires RTL's DAT_W parameter to be sufficiently large,
# else matmul results cannot be adequately represented

# AM_ROWS < AM_COLS not supported yet
#		"AM_ROWS=2 AM_COLS=3 WM_COLS=1" \
#		"AM_ROWS=2 AM_COLS=3 WM_COLS=2" \
#		"AM_ROWS=2 AM_COLS=3 WM_COLS=3" \
#		"AM_ROWS=2 AM_COLS=3 WM_COLS=4" \

sweep:
	@for cfg in \
		"AM_ROWS=1 AM_COLS=1 WM_COLS=1" \
		"AM_ROWS=1 AM_COLS=1 WM_COLS=4" \
		"AM_ROWS=2 AM_COLS=2 WM_COLS=2" \
		"AM_ROWS=3 AM_COLS=3 WM_COLS=3" \
		"AM_ROWS=4 AM_COLS=4 WM_COLS=4" \
		"AM_ROWS=5 AM_COLS=5 WM_COLS=5" \
		"AM_ROWS=2 AM_COLS=1 WM_COLS=1" \
		"AM_ROWS=3 AM_COLS=3 WM_COLS=1" \
		"AM_ROWS=3 AM_COLS=3 WM_COLS=4" \
		"AM_ROWS=4 AM_COLS=3 WM_COLS=4" \
		"AM_ROWS=6 AM_COLS=1 WM_COLS=6" \
		"AM_ROWS=6 AM_COLS=2 WM_COLS=1" \
		"AM_ROWS=6 AM_COLS=2 WM_COLS=3" \
	; do \
		echo "Running $$cfg"; \
		$(MAKE) sweep_cmd $$cfg; \
		rc=$$?; \
		if [ $$rc -ne 0 ]; then \
			echo "FAILED: $$cfg"; \
			exit $$rc; \
		fi; \
	done; \
	echo "SWEEP PASSED"; \

sweep_cmd:
	$(COMPILE_CMD) -GAM_ROWS=$(AM_ROWS) -GAM_COLS=$(AM_COLS) -GWM_COLS=$(WM_COLS)
	$(SIM_CMD)

sample:
	$(COMPILE_CMD) -GAM_ROWS=3 -GAM_COLS=3 -GWM_COLS=3 -GDAT_W=5
	$(SIM_CMD)

run:
	$(COMPILE_CMD)
	$(SIM_CMD)
