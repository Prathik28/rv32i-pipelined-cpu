# 5-Stage Pipelined RV32I Processor (Verilog)

[![CI](https://github.com/Prathik28/rv32i-pipelined-cpu/actions/workflows/publish.yml/badge.svg?branch=staging)](https://github.com/Prathik28/rv32i-pipelined-cpu/actions/workflows/publish.yml)

A complete, verified 5-stage pipelined **RISC-V RV32I** core (IF → ID → EX → MEM → WB)
handling all three hazard classes. (Note: MIPS and RISC-V are different ISAs; this is RISC-V,
whose pipeline is the classic MIPS-style one.)

## Hazard handling

| Hazard | Cause | Solution | File |
|---|---|---|---|
| **Data (RAW)** | consumer needs a result still in the pipe | forwarding EX/MEM→EX and MEM/WB→EX (both ALU operands, branch compare, store data) | `forwarding_unit.v` |
| Data (RAW, 3 apart) | write and read same cycle | register file write-through bypass | `regfile.v` |
| **Load-use** | load data not ready until end of MEM | 1-cycle stall + bubble, then forward from WB | `hazard_unit.v` |
| **Control** | branch/JAL/JALR resolved in EX | predict-not-taken, flush IF/ID + ID/EX on taken (2-cycle penalty) | `riscv_core.v` |
| **Structural** | IF and MEM both need memory; regfile read+write | Harvard (separate I/D memories), write-through regfile | `imem.v`, `dmem.v` |
| WAW / WAR | — | impossible: in-order, write-back in the last stage; `x0` writes ignored | — |

Instructions: all of RV32I (LUI, AUIPC, JAL, JALR, branches, byte/half/word loads & stores with
sign/zero extension, ALU reg/imm). ECALL/EBREAK halt the simulation. FENCE is a NOP.
Performance counters (cycles, retired instructions, stalls, flushes) are built in.

## Layout
```
rtl/   alu, regfile, imm_gen, control_unit, forwarding_unit, hazard_unit, imem, dmem, riscv_core, riscv_soc
tb/    tb_riscv.v        runs +hex=prog.hex until ECALL, dumps regs/mem/perf
sw/    asm.py            RV32I assembler (+ pseudo-ops: li, mv, j, ret, beqz, ble, ...)
       iss.py            golden-model instruction-set simulator
       gen_random.py     random hazard-dense program generator
       run_tests.py      compares RTL against the ISS (registers + data memory)
       mutation_check.sh breaks each hazard mechanism and checks the tests notice
tests/ 9 directed programs (forwarding, load-use, branches, jumps, memory, fib, bubble sort, ...)
```

## Usage
Requires Icarus Verilog (`brew install icarus-verilog`) and Python 3.

```
make test                          # 9 directed + 300 random programs vs golden model
make run T=tests/07_bubble_sort.s  # run one program, print registers
make wave T=tests/03_branches.s    # produce build/wave.vcd
make mutate                        # mutation test of the hazard logic
```
Note: `+hex=` paths cannot contain spaces; run from the project root with relative paths.

## Memory map
Harvard: instruction memory 4 KiB (PC starts at 0); data memory 4 KiB at address 0.

## Possible extensions
Branch prediction (BTB / 2-bit), moving branch resolution to ID, caches, CSR/M-extension, FPGA top-level.
