#!/bin/bash
# Synthesise the MIPS FPGA top with Yosys for Xilinx 7-series and print resource use.
# (Yosys only: no place & route, so no Fmax -- see ecp5_timing.sh for an open-source estimate.)
cd "$(dirname "$0")/.."
command -v yosys >/dev/null || { echo "yosys not installed"; exit 1; }
python3 sw/masm.py fpga/blink.s fpga/blink.hex
mkdir -p build
yosys -q -l build/synth.log -p "
  read_verilog -sv -DSYNTHESIS rtl/*.v fpga/fpga_top.v
  hierarchy -top fpga_top
  synth_xilinx -family xc7 -top fpga_top -flatten
  tee -o build/synth_stat.txt stat
"
echo "== resource summary (build/synth_stat.txt) =="
grep -E "LUT[1-6] |FDRE|FDSE|CARRY4|DSP48E1|RAM|MUXF" build/synth_stat.txt
awk '/LUT[1-6]$/{l+=$1} /FD[RSCP]E/{f+=$1} END{print "total LUTs: " l ", flip-flops: " f}' build/synth_stat.txt
