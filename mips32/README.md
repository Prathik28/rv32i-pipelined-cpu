# 5-Stage Pipelined MIPS32 Processor (Verilog) with CP0 Exceptions

A second processor in this repository: a verified 5-stage pipelined **MIPS32** core
(IF → ID → EX → MEM → WB) with the classic **branch delay slot**, **branch-likely** instructions,
unaligned loads/stores, a small **coprocessor 0** and **precise exceptions and interrupts**. It reuses
the verification approach of the [RISC-V core](../README.md): an independent Python golden model,
directed and random programs compared register-by-register, and mutation tests.

> MIPS and RISC-V are different instruction sets. The two cores share pipeline ideas (forwarding,
> load-use stalls, an iterative divider, precise traps in EX) but not instruction encodings.

## Hazard handling

| Hazard | Cause | Solution |
|---|---|---|
| **Data (RAW)** | consumer needs a result still in the pipe | forwarding EX/MEM→EX and MEM/WB→EX; register-file write-through (WB→ID) |
| **Load-use** | load data is ready after MEM | 1-cycle stall, then forward from WB |
| **Control** | branches/jumps resolve in **ID** | the **delay slot** hides the branch penalty: **no flush, no prediction, 0-cycle penalty**; a not-taken **branch-likely** annuls its slot |
| **Control + data** | a branch/jump needs its operands in ID | ALU result in MEM → forwarded into the ID comparator; producer in EX → 1 stall; load in MEM → 1 more stall (2 in total for load → branch) |
| **Structural** | `DIV`/`DIVU` are iterative (32 cycles) | front end stalls while the divider is busy |
| **Structural** | `HI`/`LO` | written and read in EX in program order, so no extra interlock |
| **Structural** | IF and MEM both need memory | Harvard architecture |
| **Exceptions** | overflow, address error, SYSCALL, BREAK, reserved instruction, interrupts | taken **precisely in EX**: the faulting instruction never commits, younger ones are flushed; **EPC / Cause.BD follow the delay-slot rules** (a fault in a delay slot reports the BRANCH in EPC with BD = 1); `ERET` returns with no delay slot |
| WAW / WAR | — | impossible: in-order, write-back in the last stage; `$0` is hard-wired |

Differences from the RISC-V core: branches resolve one stage earlier (ID instead of EX) and use the
delay slot instead of a branch predictor; `HI`/`LO` hold multiply/divide results; the exception model
is MIPS CP0 (single vector at `0x180`) rather than RISC-V CSRs.

## What the pipeline does (generated from the RTL)

`make diagram` runs `docs/hazard_demo.s` on the RTL: forwarding badges (blue), stalls (orange), a
taken branch (green outline: the delay slot is already being fetched). Runs of identical cycles (the
32-cycle divide) are collapsed.

![pipeline diagram](docs/pipeline_hazards.svg)

## Instruction set and platform

* **Integer:** `add addu sub subu and or xor nor slt sltu`, `sll srl sra sllv srlv srav`, `addi addiu slti sltiu andi ori xori lui`, `mult multu div divu mfhi mflo mthi mtlo mul`
* **Memory:** `lb lbu lh lhu lw sb sh sw` plus **unaligned** `lwl lwr swl swr` (little-endian)
* **Control:** `beq bne blez bgtz bltz bgez bltzal bgezal`, `j jal jr jalr`, and the **branch-likely** forms `beql bnel blezl bgtzl bltzl bgezl bltzall bgezall`
* **System:** `syscall break eret mfc0 mtc0`
* **CP0:** `BadVAddr`(8) `Count`(9) `Compare`(11) `Status`(12: IM[15:8], EXL, IE) `Cause`(13: BD, IP[15:8], ExcCode) `EPC`(14)
* **Exceptions** (ExcCode): interrupt 0, address error load 4 / store 5 (misaligned `lh lhu lw sh sw`, with `BadVAddr`), syscall 8, break 9, reserved instruction 10, arithmetic overflow 12 (`add addi sub`)
* **Interrupts:** two software requests (`Cause.IP0/IP1`, writable with `mtc0`) and the timer (`Count == Compare` → `IP7`, cleared by writing `Compare`); taken when `Status.IE = 1`, `EXL = 0` and the matching `IM` bit is set. `EXL` also blocks nested interrupts and keeps `EPC`/`BD` from being overwritten by a nested exception
* Pseudo-ops in the assembler: `nop move li la b beqz bnez blt bge bgt ble not negu halt exit`, `.word`, `.org`

Memory map: 4 KiB data RAM at `0`; `0xFFFF0000` HALT (write = exit code), `0xFFFF0004` PUTCHAR
(simulation console), `0xFFFF0008` LEDS. Reset vector `0x0`, exception vector `0x180`; instruction memory is 4 KiB.

## Results

Output of `make test` (cycles measured in the RTL; CPI includes startup/drain):

```
test                  result  cycles instret   CPI ld-use br-stall  div  taken traps
01_raw_forwarding     PASS        23      19  1.21      0        0    0      0     0
02_load_use           PASS        21      14  1.50      3        0    0      0     0
03_branches           PASS        45      41  1.10      0        0    0     10     0
04_jumps              PASS        33      27  1.22      0        2    0      8     0
05_memory             PASS        26      21  1.24      1        0    0      0     0
06_fibonacci          PASS       221     201  1.10      0       16    0     30     0
07_bubble_sort        PASS       954     741  1.29     66      143    0     98     0
08_alu_shifts         PASS        31      27  1.15      0        0    0      0     0
09_hilo_muldiv        PASS       184      45  4.09      0        1  134      1     0
10_branch_hazards     PASS        57      46  1.24      1        6    0      9     0
11_console_exit       PASS        13       9  1.44      0        0    0      0     0
12_exceptions         PASS       330     256  1.29      0        0    0      2    14
13_unaligned          PASS        69      58  1.19      7        0    0      0     0
14_branch_likely      PASS        56      39  1.44      0        3    0      9     0
15_soft_interrupt     PASS       194     122  1.59      0        0   33      3     7
16_nested_exception   PASS        44      31  1.42      0        1    0      3     2
sc_timer_interrupt    PASS       420      94  4.47      0        5  297      6     4
random programs: 200/200 passed
ALL TESTS PASSED
```

(`br-stall` = cycles a branch/jump waited for its operand; `traps` = exceptions + interrupts taken.
`09_hilo_muldiv` is slow on purpose: it is mostly divides at ~34 cycles each. `sc_timer_interrupt` is
self-checking because timer interrupt timing depends on the pipeline.)

### Synthesis (Yosys, Xilinx 7-series, `make synth`)

| LUTs | Flip-flops | DSP48E1 | Block RAM |
|---|---|---|---|
| 2402 | 797 | 8 (two 32×32 multipliers) | 4× RAMB18 + 1× RAMB36 |

Yosys only, no place-and-route.

### Place and route (open-source, Lattice ECP5, `sw/ecp5_timing.sh`)

The CI `mips-timing` job runs Yosys + nextpnr for an ECP5 LFE5U-85F (speed grade 6) with no local install.

| LUT4 (TRELLIS_COMB) | Flip-flops | Block RAM | Multipliers (MULT18X18D) | Estimated Fmax |
|---|---|---|---|---|
| 4409 / 83640 (5%) | 795 | 6 / 208 | 8 / 156 | **≈ 43 MHz** (passes a 25 MHz target) |

nextpnr stops optimising once the 25 MHz target is met, so the true limit may be somewhat higher. The
MIPS core is faster than the RISC-V core's ≈ 27 MHz estimate on the same chip family mainly because
its memories map to block RAM and it has no PMP/atomic/misaligned-access logic in front of the memory stage.

This is a single-seed estimate for the ECP5 family against a 25 MHz target, not a result for any other
FPGA. ZedBoard instructions are in [`../docs/ZEDBOARD.md`](../docs/ZEDBOARD.md) (`fpga/zedboard_top.v`, `fpga/zedboard.xdc`). An example Basys 3 top level (`fpga/fpga_top.v`, `fpga/basys3.xdc`) divides the Basys 3's 100 MHz clock
by 4 and shows a binary counter (`fpga/blink.s`) on the LEDs; the Basys 3 version has been simulated but **never run on hardware**.

### Tested on hardware

The LED counter demo (`fpga/blink.s`) **runs on a ZedBoard** (Zynq-7000, programmable logic only) at a
25 MHz core clock. Other features are verified in simulation only.

## How it is verified

* `sw/mips_iss.py` is an independent, non-pipelined golden model with delay-slot semantics, branch-likely
  annulment, CP0 and exceptions. `make test` compares all 32 registers, `HI`/`LO`, `EPC`/`BadVAddr`/`Cause`,
  data memory, exit code and console output.
* `sw/gen_random.py` makes random programs with dense RAW / load-use / branch-operand hazards, forward
  branches and jumps (all with delay slots, including branch-likely), counted loops, `jr`/`jalr`
  through just-computed addresses, multiply/divide with `HI`/`LO` traffic, unaligned `lwl/lwr/swl/swr`,
  overflowing `add/addi/sub`, misaligned accesses, `syscall`/`break`/reserved encodings (which may fault
  inside a delay slot) and software interrupts. A handler at `0x180` folds `Cause`/`BadVAddr` into a register
  and skips the instruction. Over 60 sample programs: ~650 traps, ~3500 branch-operand stalls,
  ~4100 divider stalls, ~3300 taken branches/jumps.
* Directed tests check delay slots on taken and not-taken branches, every branch-likely form,
  every unaligned offset, exceptions in delay slots (EPC = the branch, BD = 1), nested exceptions
  (EPC and BD preserved while EXL = 1), and interrupt masking by IE, IM and EXL.
* `make mutate` breaks the design **43 ways** (no forwarding, no stalls, delay slot skipped, `EPC`
  ignoring the delay slot, `BD` not recorded, `ERET` not flushing, faulting instruction committing,
  branch-likely never/always annulling, `LWL` ignoring its merge value, `SWR` wrong lanes, interrupt
  ignoring `IE` or `EXL`, timer not raising `IP7`, …); every mutant must make the tests fail.

## Usage

Requires Icarus Verilog and Python 3 (Yosys for `make synth`).

```
make test                          # directed + 200 random programs vs the golden model
make run T=tests/07_bubble_sort.s  # run one program
make diagram                       # docs/pipeline_hazards.svg
make synth                         # Yosys synthesis report
make mutate                        # mutation test (ONLY=regex runs a subset)
```

Programs are written with **explicit delay slots** (the assembler never reorders): put a useful
instruction or a `nop` after every branch and jump. Exception handlers live at `.org 0x180`.
Note: `+hex=` paths cannot contain spaces.

## Limitations

* CP0 is minimal: no TLB, caches, `PRId`, `Config`, vectored/EJTAG exceptions, or the other interrupt lines (only 2 software + timer)
* No floating point (CP1), `MOVZ/MOVN`, `CLZ`, `LL/SC`, `LWC/SWC`, `TEQ`-style trap instructions
* A branch or jump inside another branch's delay slot is undefined (as in MIPS)
* Divide by zero is implementation-defined here (`LO = 0xFFFFFFFF`, `HI` = dividend; `INT_MIN / -1` gives `INT_MIN`) because MIPS leaves it **unpredictable** - there is no architecturally correct answer to implement
* On hardware, only the LED counter demo has been run (ZedBoard, 25 MHz); the only timing figure recorded here is the ECP5 place-and-route estimate above
