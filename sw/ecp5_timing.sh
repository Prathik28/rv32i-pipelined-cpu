#!/bin/bash
# Place & route for a Lattice ECP5 (LFE5U-25F) with the open-source Yosys + nextpnr flow and
# report the estimated maximum clock frequency. No board needed.
#   needs: yosys, nextpnr-ecp5  (OSS CAD Suite: https://github.com/YosysHQ/oss-cad-suite-build)
# NOTE: this is an estimate for ECP5, not for any other FPGA family (e.g. the Basys 3's Artix-7).
set -e
cd "$(dirname "$0")/.."
for t in yosys nextpnr-ecp5; do command -v $t >/dev/null || { echo "$t not installed"; exit 1; }; done
FREQ=${FREQ:-25}
mkdir -p build
python3 sw/asm.py fpga/blink.s fpga/blink.hex
yosys -q -l build/ecp5_synth.log -p "
  read_verilog -sv -DSYNTHESIS rtl/*.v fpga/timing_top.v
  synth_ecp5 -top timing_top -json build/ecp5.json
"
nextpnr-ecp5 --25k --package CABGA381 --speed 6 --json build/ecp5.json \
    --freq "$FREQ" --seed 1 --lpf-allow-unconstrained \
    --report build/ecp5_report.json > build/ecp5_pnr.log 2>&1 || { tail -30 build/ecp5_pnr.log; exit 1; }
echo "== utilisation =="
grep -E "TRELLIS_COMB|TRELLIS_FF|DP16KD|MULT18X18D|TRELLIS_DPR16X4|LUT4" build/ecp5_pnr.log | grep -E "[0-9]+/ +[0-9]+" | tail -8
echo "== timing (target ${FREQ} MHz) =="
grep -E "Max frequency for clock" build/ecp5_pnr.log | tail -1
