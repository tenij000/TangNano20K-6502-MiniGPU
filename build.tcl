set ROOT [file dirname [file normalize [info script]]]
cd $ROOT
open_project "$ROOT/MiniGPU_BASIC.gprj"
set_option -top_module top
set_option -verilog_std sysv2017
run all
