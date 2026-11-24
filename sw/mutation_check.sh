#!/bin/bash
# Break each hazard / feature mechanism in turn; the test-suite MUST fail for every mutant.
cd "$(dirname "$0")/.."
cp -r rtl rtl.orig
trap 'rm -rf rtl; mv rtl.orig rtl' EXIT
mutate() {  # name file sed-expr
  cp rtl.orig/*.v rtl/
  sed -i.bak "$3" "rtl/$2" && rm -f rtl/*.bak
  if cmp -s "rtl/$2" "rtl.orig/$2"; then echo "MUTATION DID NOT APPLY: $1"; return; fi
  if FAILFAST=1 python3 sw/run_tests.py 40 >/dev/null 2>&1; then echo "SURVIVED (bad): $1"; else echo "killed: $1"; fi
}
mutate "no EX/MEM forwarding"      forwarding_unit.v 's/fwd_a = 2.b10;/fwd_a = 2'"'"'b00;/; s/fwd_b = 2.b10;/fwd_b = 2'"'"'b00;/'
mutate "no MEM/WB forwarding"      forwarding_unit.v 's/fwd_a = 2.b01;/fwd_a = 2'"'"'b00;/; s/fwd_b = 2.b01;/fwd_b = 2'"'"'b00;/'
mutate "no load-use stall"         hazard_unit.v     's/assign stall = .*/assign stall = 1'"'"'b0; wire _u = 1'"'"'b0 \&\&/'
mutate "no regfile write-through"  regfile.v         's/(we \&\& waddr == raddr1) ? wdata :/1'"'"'b0 ? wdata :/; s/(we \&\& waddr == raddr2) ? wdata :/1'"'"'b0 ? wdata :/'
mutate "no flush of IF/ID"         riscv_core.v      's/if (rst || redirect) begin$/if (rst) begin/'
mutate "no flush of ID/EX"         riscv_core.v      's/if (rst || redirect || (load_use \&\& !ex_stall)) begin/if (rst || (load_use \&\& !ex_stall)) begin/'
mutate "mispredict never detected" riscv_core.v      's/^    wire mispredict = ex_commit/    wire mispredict = 1'"'"'b0 \& ex_commit/'
mutate "BTB ignores target change" branch_predictor.v 's/target\[ui\] <= upd_target;$/;/'
mutate "BTB predicts always taken" branch_predictor.v 's/ctr\[li\]\[1\]/1'"'"'b1/'
mutate "divider not stalling"      riscv_core.v      's/assign ex_stall  = idex_div \& ~div_done \& ~trap_take;/assign ex_stall = 1'"'"'b0;/'
mutate "div wrong sign handling"   div_unit.v        's/wire a_neg     = sgn \& a\[31\];/wire a_neg = 1'"'"'b0;/'
mutate "div by zero result"        div_unit.v        's/32.hFFFF_FFFF; done <= 1;/32'"'"'h0; done <= 1;/'
mutate "mulh wrong signedness"     mul_unit.v        's/wire b_signed = (op == 2.b01);/wire b_signed = 1'"'"'b0;/'
mutate "traps do not suppress instr" riscv_core.v    's/wire   ex_commit = ~ex_stall \& ~trap_take;/wire ex_commit = ~ex_stall;/'
mutate "mret does not restore MIE" csr_file.v        's/mie_g <= mpie;    mpie   <= 1.b1;/mpie <= 1'"'"'b1;/'
mutate "misaligned loads allowed"  riscv_core.v      's/^    wire exc_ld_mis    = idex_mem_read  \&/    wire exc_ld_mis    = 1'"'"'b0 \&/'
mutate "illegal opcode accepted"   control_unit.v    's/default: illegal = 1;/default: ;/'
