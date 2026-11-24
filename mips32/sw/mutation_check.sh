#!/bin/bash
# Break each hazard / feature mechanism in turn; the test-suite MUST fail for every mutant.
# ONLY=regex runs a subset.
cd "$(dirname "$0")/.."
cp -r rtl rtl.orig
trap 'rm -rf rtl; mv rtl.orig rtl' EXIT
mutate() {  # name file sed-expr
  if [ -n "$ONLY" ] && ! [[ "$1" =~ $ONLY ]]; then return; fi
  cp rtl.orig/*.v rtl/
  sed -i.bak "$3" "rtl/$2" && rm -f rtl/*.bak
  if cmp -s "rtl/$2" "rtl.orig/$2"; then echo "MUTATION DID NOT APPLY: $1"; return; fi
  if FAILFAST=1 python3 sw/run_tests.py 40 >/dev/null 2>&1; then echo "SURVIVED (bad): $1"; else echo "killed: $1"; fi
}
mutate "no EX/MEM forwarding"            mips_fwd.v     's/fwd_a = 2.b10;/fwd_a = 2'"'"'b00;/; s/fwd_b = 2.b10;/fwd_b = 2'"'"'b00;/'
mutate "no MEM/WB forwarding"            mips_fwd.v     's/fwd_a = 2.b01;/fwd_a = 2'"'"'b00;/; s/fwd_b = 2.b01;/fwd_b = 2'"'"'b00;/'
mutate "no regfile write-through"        regfile.v      's/(we \&\& waddr == raddr1) ? wdata :/1'"'"'b0 ? wdata :/; s/(we \&\& waddr == raddr2) ? wdata :/1'"'"'b0 ? wdata :/'
mutate "no load-use stall"               mips_core.v    's/assign stall_lu = ifid_valid \& idex_mem_read \&\&/assign stall_lu = 1'"'"'b0 \&\&/'
mutate "branch ignores producer in EX"   mips_core.v    's/assign stall_br = ifid_valid \& (br_dep_ex | br_dep_mem);/assign stall_br = ifid_valid \& br_dep_mem;/'
mutate "branch ignores load in MEM"      mips_core.v    's/assign stall_br = ifid_valid \& (br_dep_ex | br_dep_mem);/assign stall_br = ifid_valid \& br_dep_ex;/'
mutate "no ID-stage forwarding (rs)"     mips_core.v    's/wire fwd_a_id = exmem_reg_write/wire fwd_a_id = 1'"'"'b0 \&\& exmem_reg_write/'
mutate "no ID-stage forwarding (rt)"     mips_core.v    's/wire fwd_b_id = exmem_reg_write/wire fwd_b_id = 1'"'"'b0 \&\& exmem_reg_write/'
mutate "delay slot not executed"         mips_core.v    's/ifid_valid <= ~annul;/ifid_valid <= ~annul \& ~id_redirect;/'
mutate "jal links PC+4 not PC+8"         mips_core.v    's/idex_pc + 32.d8/idex_pc + 32'"'"'d4/'
mutate "divider does not stall"          mips_core.v    's/assign ex_stall = div_any \& ~div_done \& ~trap_take;/assign ex_stall = 1'"'"'b0;/'
mutate "mult signedness wrong"           mips_core.v    's/if (idex_mult)       {hi, lo} <= prod_s;/if (idex_mult)       {hi, lo} <= prod_u;/'
mutate "mthi/mtlo swapped"               mips_core.v    's/else if (idex_mthi)  hi <= rs_v;/else if (idex_mthi)  lo <= rs_v;/'
mutate "divide by zero result"           mips_div.v     's/sp_q <= 32.hFFFF_FFFF; sp_r <= a;/sp_q <= 32'"'"'h0; sp_r <= a;/'
mutate "div remainder sign"              mips_div.v     's/wire a_neg    = is_signed \& a\[31\];/wire a_neg = 1'"'"'b0;/'
mutate "SRA is logical"                  mips_alu.v     's/SRA:  y = \$signed(a) >>> b\[4:0\];/SRA:  y = a >> b[4:0];/'
mutate "NOR is OR"                       mips_alu.v     's/NOR:  y = ~(a | b);/NOR:  y = a | b;/'
mutate "ANDI sign-extends"               mips_control.v 's/6.h0C: begin itype(AND); imm_zext=1; end/6'"'"'h0C: begin itype(AND); end/'
mutate "BGEZ treated as BLTZ"            mips_core.v    's/3.d4: taken = ltz;    default: taken = ~ltz;/3'"'"'d4: taken = ~ltz;    default: taken = ltz;/'
mutate "BLTZAL does not link"            mips_control.v 's/5.h10: branch1(4, 0, 1);/5'"'"'h10: branch1(4, 0, 0);/'
mutate "LB zero-extends"                 mips_core.v    's/2.d0:    load_data = exmem_mem_unsigned ? {24.b0, shifted\[7:0\]}  : {{24{shifted\[7\]}},  shifted\[7:0\]};/2'"'"'d0:    load_data = {24'"'"'b0, shifted[7:0]};/'

# ---- CP0, exceptions, interrupts, unaligned access, branch-likely ----
mutate "overflow not detected"            mips_core.v    's/wire exc_ov = idex_ov \& /wire exc_ov = 1'"'"'b0 \& /'
mutate "SUB overflow uses ADD rule"       mips_core.v    's/(idex_alu_op == 4.d1) ? sub_ov : add_ov/add_ov/'
mutate "misaligned access allowed"        mips_core.v    's/wire misal  = mem_op \& ~unal \&/wire misal = 1'"'"'b0 \&/'
mutate "EPC ignores delay slot"           mips_core.v    's/.exc_epc(idex_bd ? idex_pc - 32.d4 : idex_pc)/.exc_epc(idex_pc)/'
mutate "Cause.BD not recorded"            mips_core.v    's/.exc_bd(idex_bd)/.exc_bd(1'"'"'b0)/'
mutate "ERET does not flush"              mips_core.v    's/assign flush    = trap_take | eret_take;/assign flush = trap_take;/'
mutate "faulting instruction commits"     mips_core.v    's/if (rst || ex_stall || trap_take) begin/if (rst || ex_stall) begin/'
mutate "reserved instr treated as NOP"    mips_control.v 's/default: ri = 1;/default: ;/'
mutate "branch-likely never annuls"       mips_core.v    's/assign annul         = ifid_valid \& ~stall_front \& c_is_branch \& c_likely \& ~taken;/assign annul = 1'"'"'b0;/'
mutate "branch-likely always annuls"      mips_core.v    's/\& c_is_branch \& c_likely \& ~taken;/\& c_is_branch \& c_likely;/'
mutate "BLTZALL does not link"            mips_control.v 's/5.h12: branch1(4, 1, 1);/5'"'"'h12: branch1(4, 1, 0);/'
mutate "LWL ignores merge value"          mips_core.v    's/load_data = (exmem_store \& ~mask_hi) | ((dmem_rdata << {noff, 3.b000}) \& mask_hi);/load_data = ((dmem_rdata << {noff, 3'"'"'b000}) \& mask_hi);/'
mutate "SWR wrong data lanes"             mips_core.v    's/wdata = exmem_store << {off, 3.b000};/wdata = exmem_store;/'
mutate "SWL wrong byte enables"           mips_core.v    's/be = 4.b1111 >> noff;  wdata/be = 4'"'"'b1111;  wdata/'
mutate "interrupt ignores IE"             mips_cp0.v     's/assign irq_pending = ie \& ~exl \&/assign irq_pending = ~exl \&/'
mutate "interrupt ignores EXL"            mips_cp0.v     's/assign irq_pending = ie \& ~exl \&/assign irq_pending = ie \&/'
mutate "EXL not set on entry"             mips_cp0.v     's/exl <= 1.b1; exccode <= exc_code;/exccode <= exc_code;/'
mutate "ERET leaves EXL set"              mips_cp0.v     's/exl <= 1.b0;$/;/'
mutate "EPC overwritten while EXL"        mips_cp0.v     's/if (!exl) begin epc <= exc_epc; bd <= exc_bd; end/begin epc <= exc_epc; bd <= exc_bd; end/'
mutate "timer never raises IP7"           mips_cp0.v     's/if (count == compare) ip7 <= 1.b1;/if (count == compare) ip7 <= 1'"'"'b0;/'
mutate "Compare write does not clear IP7" mips_cp0.v     's/5.d11: begin compare <= wdata; ip7 <= 1.b0; end/5'"'"'d11: begin compare <= wdata; end/'
mutate "BadVAddr not recorded"            mips_core.v    's/.badv_we(~irq_take \& (exc_adel | exc_ades))/.badv_we(1'"'"'b0)/'
