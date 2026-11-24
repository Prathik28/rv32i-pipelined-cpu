#!/bin/bash
# Break each hazard / feature mechanism in turn; the test-suite MUST fail for every mutant.
cd "$(dirname "$0")/.."
cp -r rtl rtl.orig
trap 'rm -rf rtl; mv rtl.orig rtl' EXIT
mutate() {  # name file sed-expr   (ONLY=regex runs just the matching mutants)
  if [ -n "$ONLY" ] && ! [[ "$1" =~ $ONLY ]]; then return; fi
  cp rtl.orig/*.v rtl/
  sed -i.bak "$3" "rtl/$2" && rm -f rtl/*.bak
  if cmp -s "rtl/$2" "rtl.orig/$2"; then echo "MUTATION DID NOT APPLY: $1"; return; fi
  if FAILFAST=1 python3 sw/run_tests.py 40 >/dev/null 2>&1; then echo "SURVIVED (bad): $1"; else echo "killed: $1"; fi
}
mutate "no EX/MEM forwarding"      forwarding_unit.v 's/fwd_a = 2.b10;/fwd_a = 2'"'"'b00;/; s/fwd_b = 2.b10;/fwd_b = 2'"'"'b00;/'
mutate "no MEM/WB forwarding"      forwarding_unit.v 's/fwd_a = 2.b01;/fwd_a = 2'"'"'b00;/; s/fwd_b = 2.b01;/fwd_b = 2'"'"'b00;/'
mutate "no load-use stall"         hazard_unit.v     's/assign stall = .*/assign stall = 1'"'"'b0; wire _u = 1'"'"'b0 \&\&/'
mutate "no regfile write-through"  regfile.v         's/(we \&\& waddr == raddr1) ? wdata :/1'"'"'b0 ? wdata :/; s/(we \&\& waddr == raddr2) ? wdata :/1'"'"'b0 ? wdata :/'
mutate "no flush of IF/ID"            riscv_core.v      's/if (rst || (redirect \&\& !mem_hold)) begin/if (rst) begin/'
mutate "no flush of ID/EX"            riscv_core.v      's/if (rst || (!mem_hold \&\& (redirect || (load_use \&\& !ex_stall)))) begin/if (rst || (!mem_hold \&\& (load_use \&\& !ex_stall))) begin/'
mutate "mispredict never detected" riscv_core.v      's/^    wire mispredict = ex_commit/    wire mispredict = 1'"'"'b0 \& ex_commit/'
mutate "BTB ignores target change" branch_predictor.v 's/target\[ui\] <= upd_target;$/;/'
mutate "BTB predicts always taken" branch_predictor.v 's/ctr\[li\]\[1\]/1'"'"'b1/'
mutate "divider not stalling"      riscv_core.v      's/assign ex_stall  = idex_div \& ~div_done \& ~trap_take;/assign ex_stall = 1'"'"'b0;/'
mutate "div wrong sign handling"   div_unit.v        's/wire a_neg     = sgn \& a\[31\];/wire a_neg = 1'"'"'b0;/'
mutate "div by zero result"        div_unit.v        's/32.hFFFF_FFFF; done <= 1;/32'"'"'h0; done <= 1;/'
mutate "mulh wrong signedness"     mul_unit.v        's/wire b_signed = (op == 2.b01);/wire b_signed = 1'"'"'b0;/'
mutate "traps do not suppress instr"    riscv_core.v      's/assign ex_commit = ex_active \& ~ex_stall \& ~trap_take;/assign ex_commit = ex_active \& ~ex_stall;/'
mutate "mret does not restore MIE"     csr_file.v        's/priv <= mpp ? 2.b11 : 2.b00; mie_g <= mpie;/priv <= mpp ? 2'"'"'b11 : 2'"'"'b00;/'
mutate "misaligned MMIO/atomic allowed" riscv_core.v     's/((idex_amo \& misal) | (~idex_amo \& (r_lo == 3.d4) \& misal));/1'"'"'b0;/'
mutate "illegal opcode accepted"   control_unit.v    's/default: illegal = 1;/default: ;/'

# ---- memory system, atomics, privilege, PMP, interrupts ----
mutate "PC not held during wait states"   riscv_core.v      's/else if (mem_hold)     ;/else if (1'"'"'b0)     ;/'
mutate "wait states ignored"              riscv_core.v      's/assign mem_hold  = ~m_done;/assign mem_hold = 1'"'"'b0;/'
mutate "misaligned split disabled"        riscv_core.v      's/wire        crossing = ~exmem_amo \&.*/wire crossing = 1'"'"'b0;/'
mutate "SC always succeeds"               riscv_core.v      's/wire        sc_ok    = m_sc \& resv_valid \& (resv_word == exmem_result\[31:2\]);/wire sc_ok = m_sc;/'
mutate "trap keeps reservation"           riscv_core.v      's/if (trap_take)      resv_valid <= 1.b0;.*//'
mutate "AMOADD wrong"                     riscv_core.v      's/amo_new = lo_data + exmem_store;/amo_new = lo_data - exmem_store;/'
mutate "FENCE.I does not flush"           riscv_core.v      's/wire fencei_take = idex_fencei \& ex_commit;/wire fencei_take = 1'"'"'b0;/'
mutate "PMP read check always passes"     pmp_check.v       's/assign r_ok = .*/assign r_ok = 1'"'"'b1;/'
mutate "PMP lock ignored for M-mode"      pmp_check.v       's/wire allow_all = m_mode \& (~found | ~sel_cfg\[7\]);/wire allow_all = m_mode;/'
mutate "MRET allowed in U-mode"           riscv_core.v      's/(idex_mret \& (priv != 2.b11))/1'"'"'b0/'
mutate "mcounteren ignored"               csr_file.v        's/(priv == 2.b11) | cntbit/1'"'"'b1/'
mutate "vectored mtvec ignored"           riscv_core.v      's/wire vec_irq     = irq_take \& mtvec\[0\];/wire vec_irq = 1'"'"'b0;/'
mutate "interrupt priority wrong"         csr_file.v        's/assign irq_cause   = pend\[2\] ? 32.h8000_000B : pend\[1\] ? 32.h8000_0003 : 32.h8000_0007;/assign irq_cause = pend[0] ? 32'"'"'h8000_0007 : pend[1] ? 32'"'"'h8000_0003 : 32'"'"'h8000_000B;/'
mutate "address map not enforced"         riscv_core.v      's/(~region_ok |/(1'"'"'b0 |/'
mutate "instruction RAM not writable"     riscv_soc.v       's/.d_we(d_req \& d_we \& sel_iram)/.d_we(1'"'"'b0)/'
mutate "slow RAM ready ignored"           riscv_soc.v       's/assign    d_ready    = slow_acc ? slow_ready : 1.b1;/assign d_ready = 1'"'"'b1;/'
mutate "mcycle high word never counts"    csr_file.v        's/mcycle <= mcycle + 64.d1;/mcycle[31:0] <= mcycle[31:0] + 32'"'"'d1;/'
mutate "ECALL cause ignores privilege"    riscv_core.v      's/(priv == 2.b11) ? 32.d11 : 32.d8/32'"'"'d11/'
# (equivalent mutant, not tested: the divider can never be mid-divide while the MEM stage holds, because
#  div_start waits for ex_active and the pipeline is in-order, so div_unit.en is purely defensive)
mutate "memwb not kept during hold"       riscv_core.v      's/end else if (mem_hold) begin$/end else if (1'"'"'b0) begin/'
