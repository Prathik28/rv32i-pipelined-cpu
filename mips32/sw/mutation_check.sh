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
mutate "delay slot not executed"         mips_core.v    's/ifid_valid <= 1; end$/ifid_valid <= ~id_redirect; end/'
mutate "jal links PC+4 not PC+8"         mips_core.v    's/idex_pc + 32.d8/idex_pc + 32'"'"'d4/'
mutate "divider does not stall"          mips_core.v    's/assign ex_stall = div_any \& ~div_done;/assign ex_stall = 1'"'"'b0;/'
mutate "mult signedness wrong"           mips_core.v    's/if (idex_mult)       {hi, lo} <= prod_s;/if (idex_mult)       {hi, lo} <= prod_u;/'
mutate "mthi/mtlo swapped"               mips_core.v    's/else if (idex_mthi)  hi <= rs_v;/else if (idex_mthi)  lo <= rs_v;/'
mutate "divide by zero result"           mips_div.v     's/sp_q <= 32.hFFFF_FFFF; sp_r <= a;/sp_q <= 32'"'"'h0; sp_r <= a;/'
mutate "div remainder sign"              mips_div.v     's/wire a_neg    = is_signed \& a\[31\];/wire a_neg = 1'"'"'b0;/'
mutate "SRA is logical"                  mips_alu.v     's/SRA:  y = \$signed(a) >>> b\[4:0\];/SRA:  y = a >> b[4:0];/'
mutate "NOR is OR"                       mips_alu.v     's/NOR:  y = ~(a | b);/NOR:  y = a | b;/'
mutate "ANDI sign-extends"               mips_control.v 's/6.h0C: begin reg_write=1; alu_op=AND;  alu_src_imm=1; imm_zext=1;/6'"'"'h0C: begin reg_write=1; alu_op=AND;  alu_src_imm=1;/'
mutate "BGEZ treated as BLTZ"            mips_core.v    's/3.d4: taken = ltz;    default: taken = ~ltz;/3'"'"'d4: taken = ~ltz;    default: taken = ltz;/'
mutate "BLTZAL does not link"            mips_control.v 's/5.h10: begin br_type = 4; link=1; reg_write=1; dest_sel=2; end/5'"'"'h10: begin br_type = 4; end/'
mutate "LB zero-extends"                 mips_core.v    's/2.d0:    load_data = exmem_mem_unsigned ? {24.b0, shifted\[7:0\]}  : {{24{shifted\[7\]}},  shifted\[7:0\]};/2'"'"'d0:    load_data = {24'"'"'b0, shifted[7:0]};/'
mutate "SYSCALL ignores \$a0 forward"    mips_core.v    's/idex_syscall ? rs_v : alu_y/idex_syscall ? idex_rsv : alu_y/'
