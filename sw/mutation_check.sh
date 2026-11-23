#!/bin/bash
# Disable each hazard mechanism in turn; the test-suite MUST fail for every mutant.
cd "$(dirname "$0")/.."
cp -r rtl rtl.orig
trap 'rm -rf rtl; mv rtl.orig rtl' EXIT
mutate() {  # name file sed-expr
  cp rtl.orig/*.v rtl/
  sed -i.bak "$3" "rtl/$2" && rm -f rtl/*.bak
  if python3 sw/run_tests.py 40 >/dev/null 2>&1; then echo "SURVIVED (bad): $1"; else echo "killed: $1"; fi
}
mutate "no EX/MEM forwarding"      forwarding_unit.v 's/fwd_a = 2.b10;/fwd_a = 2'"'"'b00;/; s/fwd_b = 2.b10;/fwd_b = 2'"'"'b00;/'
mutate "no MEM/WB forwarding"      forwarding_unit.v 's/fwd_a = 2.b01;/fwd_a = 2'"'"'b00;/; s/fwd_b = 2.b01;/fwd_b = 2'"'"'b00;/'
mutate "no load-use stall"         hazard_unit.v     's/assign stall = .*/assign stall = 1'"'"'b0; wire _u = 1'"'"'b0 \&\&/'
mutate "no regfile write-through"  regfile.v         's/(we \&\& waddr == raddr1) ? wdata :/1'"'"'b0 ? wdata :/; s/(we \&\& waddr == raddr2) ? wdata :/1'"'"'b0 ? wdata :/'
mutate "no branch flush (IF/ID)"   riscv_core.v      's/if (rst || branch_taken || ex_system || halted) begin/if (rst || ex_system || halted) begin/'
mutate "no branch flush (ID/EX)"   riscv_core.v      's/wire id_bubble = rst || branch_taken ||/wire id_bubble = rst ||/'
