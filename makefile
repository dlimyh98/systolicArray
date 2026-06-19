all:
	verilator --binary --trace -f filelist.f  --top-module tb_top
	./obj_dir/Vtb_top
