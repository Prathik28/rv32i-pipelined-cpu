# 5-Stage Pipelined RISC-V Processor (RV32IM + Zicsr, Verilog)

[![CI](https://github.com/Prathik28/rv32i-pipelined-cpu/actions/workflows/publish.yml/badge.svg?branch=staging)](https://github.com/Prathik28/rv32i-pipelined-cpu/actions/workflows/publish.yml)

A verified 5-stage pipelined **RISC-V** core (IF → ID → EX → MEM → WB) that handles every class of
pipeline hazard, with a branch predictor, a multiplier/divider, machine-mode CSRs, precise
exceptions and a timer interrupt. (RISC-V rather than MIPS, but the pipeline is the classic
MIPS-style one.)

* **ISA:** RV32I + **M** (multiply/divide) + **Zicsr**, machine mode, no compressed instructions
* **Verified** against an independent Python golden model (registers, memory, exit code, console)
  with 13 directed programs and 300 random hazard-dense programs, and by 17 mutation tests
* **Synthesises** with Yosys for Xilinx 7-series (resource numbers below); FPGA top level included

## Hazard handling

| Hazard | Cause | Solution | File |
|---|---|---|---|
| **Data (RAW)** | consumer needs a result still in the pipe | forwarding EX/MEM→EX and MEM/WB→EX for both ALU operands, branch compare, store data, CSR operand | `forwarding_unit.v` |
| Data (RAW, 3 apart) | write and read in the same cycle | register file write-through bypass | `regfile.v` |
| **Load-use** | load data is ready only after MEM | 1-cycle stall, then forward from WB | `hazard_unit.v` |
| **Control** | branch / JAL / JALR resolve in EX | **BTB + 2-bit counters** predict in IF; a misprediction flushes IF/ID + ID/EX (2-cycle penalty) | `branch_predictor.v`, `riscv_core.v` |
| **Structural** | IF and MEM both need memory | Harvard architecture (separate instruction / data memories) | `imem.v`, `dmem.v` |
| Structural | register file read + write | write-through regfile | `regfile.v` |
| Structural | iterative divider is not pipelined | front end stalls while it is busy, bubbles enter MEM; operands are latched so forwarding sources may move on | `div_unit.v` |
| **Exceptions** | illegal instr, ECALL/EBREAK, misaligned load/store/jump target, timer interrupt | taken **precisely in EX**: the instruction never commits, younger ones are flushed, older ones finish | `riscv_core.v`, `csr_file.v` |
| WAW / WAR | — | impossible: in-order, write-back in the last stage; writes to `x0` are ignored | — |

## What the pipeline does (generated from the RTL)

`make diagram` runs `docs/hazard_demo.s` on the RTL and draws what is in each stage every cycle:
forwarding badges (blue), load-use and divider stalls (orange), flushes (red). Runs of identical
cycles (the 32-cycle divide) are collapsed.

![pipeline diagram](docs/pipeline_hazards.svg)

`make wave` renders hazard-unit signals straight from the simulation's VCD (GTKWave works too):

![waveform](docs/waveform.svg)

## Instruction set and platform

* RV32I (all), M: `mul mulh mulhsu mulhu div divu rem remu`, Zicsr: `csrrw/s/c[i]`, `mret`, `ecall`, `ebreak`, `wfi`/`fence` as NOPs
* **Multiplier:** single cycle (maps to DSP48). **Divider:** iterative restoring, 32 cycles; handles divide-by-zero and `INT_MIN / -1` per spec
* **CSRs:** `mstatus` `misa` `mie` `mip` `mtvec` (direct) `mscratch` `mepc` `mcause` `mtval` `mcycle` `minstret` `mhartid`, plus read-only `cycle`/`instret`
* **Traps:** illegal instruction (also bad CSR / write to a read-only CSR / compressed encodings), breakpoint, ECALL from M-mode, instruction-address-misaligned (taken jump/branch target), load/store misaligned (`mtval` = address)
* **Interrupt:** machine timer (`mtime` ≥ `mtimecmp` with `mie.MTIE` and `mstatus.MIE`)

| Address | Register | Access |
|---|---|---|
| `0x0000_0000`–`0x0000_0FFF` | data RAM (4 KiB) | RW |
| `0x1000_0000` | HALT — a write ends the program, value = exit code | W |
| `0x1000_0004` | PUTCHAR — prints a character in simulation | W |
| `0x1000_0008` | MTIMECMP (reset `0xFFFFFFFF` = no interrupt) | RW |
| `0x1000_000C` | MTIME (32-bit free-running cycle counter) | R |
| `0x1000_0010` | LEDS (16-bit GPIO) | RW |

Instruction memory is separate (Harvard), 4 KiB, PC starts at 0, and is loaded from a hex file.

## Results

Output of `make test` (cycles are measured in the RTL; CPI includes startup/drain):

```
test                  result  cycles instret   CPI ld-use  div flush branch mispred traps
01_raw_forwarding     PASS        20      16  1.25      0    0     0      0     0   -    0
02_load_use           PASS        20      13  1.54      3    0     0      0     0   -    0
03_branches           PASS        75      48  1.56      1    0    11     20    11 45%    0
04_jumps              PASS        25      13  1.92      0    0     4      4     4  0%    0
05_memory             PASS        25      20  1.25      1    0     0      0     0   -    0
06_fibonacci          PASS       228     200  1.14     16    0     4     32     4 88%    0
07_bubble_sort        PASS       761     599  1.27     66    0    46    143    46 68%    0
08_shifts_alu         PASS        25      21  1.19      0    0     0      0     0   -    0
09_mixed_hazard_chain PASS        24      13  1.85      1    0     3      4     3 25%    0
10_muldiv             PASS       309      34  9.09      1  270     0      1     0 100%    0
11_csr_traps          PASS       195     134  1.46      0    0    23      1     1  0%   11
12_branch_predict     PASS       873     753  1.16      0    0    58    286    58 80%    0
sc_irq_timer          PASS       396      64  6.19      5  297    11      7     3 57%    4
random programs: 300/300 passed
ALL TESTS PASSED
```

(`ld-use` / `div` = stall cycles, `flush` = pipeline redirects, the percentage after `mispred` is
prediction accuracy over committed control-flow instructions. CPI of `10_muldiv` is high on purpose:
it is almost all divides at ~34 cycles each.)

### Synthesis (Yosys, Xilinx 7-series, `make synth`)

| LUTs | Flip-flops | DSP48E1 | Block RAM | Distributed RAM |
|---|---|---|---|---|
| 2330 | 981 | 4 | 4× RAMB18 + 1× RAMB36 | 30× RAM32M (register file) |

### Place and route (open-source, Lattice ECP5, `sw/ecp5_timing.sh`)

The CI `timing` job runs Yosys + nextpnr for an ECP5 LFE5U-25F (speed grade 6) with no local install:

| LUT4 (TRELLIS_COMB) | Flip-flops | Block RAM (DP16KD) | Multipliers (MULT18X18D) | Estimated Fmax |
|---|---|---|---|---|
| 5273 / 24288 (21%) | 979 | 6 / 56 | 4 / 28 | **≈ 40 MHz** (passes a 25 MHz target) |

This is a single-seed estimate for the ECP5 family, run against a 25 MHz target (nextpnr stops
optimising once the target is met, so the true limit may be somewhat higher). It says nothing exact
about the Basys 3's Artix-7. The single-cycle multiplier and the forwarding paths into EX are the
likely critical paths. The Xilinx numbers above come from Yosys alone with no place-and-route. The example top level
(`fpga/fpga_top.v`, `fpga/basys3.xdc`) divides the Basys 3's 100 MHz clock by 4 and shows a binary
counter (`fpga/blink.s`) on the LEDs. It has been simulated but **never run on hardware**.

## How it is verified

* `sw/iss.py` is an independent, non-pipelined golden model. `make test` runs each program on both
  and compares all 32 registers, all data memory, the exit code and console output.
* `sw/gen_random.py` produces random programs with dense RAW / load-use hazards, loops, forward
  branches, M-extension operations (including divide-by-zero and overflow), CSR accesses,
  misaligned accesses, illegal instructions and ECALL/EBREAK. A handler folds `mcause`/`mtval` into a
  register so trap behaviour is compared as well. Over 60 sample programs this exercised ~430 traps,
  ~3400 pipeline redirects and ~10000 divider-stall cycles.
* Timer-interrupt timing depends on the pipeline, so `sc_irq_timer.s` is **self-checking** instead
  (exit code 0 = pass): the interrupted loop's arithmetic must come out uncorrupted.
* `make mutate` breaks the design 17 ways (no forwarding, no stall, no flush, wrong divider sign,
  traps committing, broken BTB, …); every mutant must make the tests fail. The branch predictor never
  changes program results, so its tests assert **performance limits** (`# PERF mispred<=60`).

## Usage

Requires Icarus Verilog (`brew install icarus-verilog`) and Python 3; Yosys for `make synth`.

```
make test                            # directed + 300 random programs vs the golden model
make run T=tests/07_bubble_sort.s    # run one program
make wave T=docs/hazard_demo.s       # build/wave.vcd + docs/waveform.svg
make diagram                         # docs/pipeline_hazards.svg
make synth                           # Yosys synthesis report
make mutate                          # mutation test of the hazard logic
```

Write your own programs in `tests/` (assembler: `sw/asm.py`, pseudo-ops `li la mv j ret beqz bnez
ble bgt csrr csrw …`, `.word`, and `halt` to end the program). Note: `+hex=` paths cannot contain spaces.

## Layout

```
rtl/   riscv_core riscv_soc alu regfile imm_gen control_unit forwarding_unit hazard_unit
       branch_predictor mul_unit div_unit csr_file imem dmem
tb/    tb_riscv.v        runs +hex=prog.hex; +vcd waveform, +trace pipeline trace
sw/    asm.py iss.py gen_random.py run_tests.py mutation_check.sh synth.sh vcd2svg.py pipeline_diagram.py
tests/ directed programs (NN_*.s compared with the ISS, sc_*.s self-checking)
fpga/  fpga_top.v basys3.xdc blink.s
docs/  hazard_demo.s and the generated SVGs
```

## Limitations

* Machine mode only: no S/U modes, PMP, vectored `mtvec`, 64-bit counters, or other interrupt sources
* No C, A, F/D extensions; instruction memory cannot be written at run time (no `fence.i` semantics)
* Misaligned accesses trap (a legal implementation choice) instead of being emulated
* No caches or memory wait states; data RAM addresses alias modulo 4 KiB
* Not run on real hardware; the only timing figure is the ECP5 place-and-route estimate above
* This is a RISC-V design. A MIPS32 variant is not included.
