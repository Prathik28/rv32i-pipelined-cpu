# Running the cores on a ZedBoard (Zynq-7000, xc7z020clg484-1)

**Status: simulated and synthesised with Yosys, never run on real hardware. The pin file was written
from memory - compare every pin with the official ZedBoard master XDC before you program the board.**

Only the programmable logic (PL) is used; the ARM processing system stays unconfigured. Vivado runs
on Windows/Linux (not macOS), so use the lab PC.

## What you need

| | RISC-V core | MIPS core |
|---|---|---|
| RTL sources | `rtl/*.v` | `mips32/rtl/*.v` |
| Top level | `fpga/zedboard_top.v` | `mips32/fpga/zedboard_top.v` |
| Constraints | `fpga/zedboard.xdc` | `mips32/fpga/zedboard.xdc` |
| Program | `fpga/blink.hex` | `mips32/fpga/blink.hex` |

Regenerate the program after editing the assembly:
`python3 sw/asm.py fpga/blink.s fpga/blink.hex` (RISC-V) or
`python3 mips32/sw/masm.py mips32/fpga/blink.s mips32/fpga/blink.hex` (MIPS).

## Steps (Vivado)

1. **New RTL project**, part **xc7z020clg484-1** (or pick the ZedBoard board if the board files are installed).
2. **Add sources:** the RTL folder and the top level from the table. Add `blink.hex` as a *memory file*
   (Add Sources → Add or create design sources → the file; set its type to Memory File). If Vivado cannot find it,
   set the `PROGRAM` parameter in the top level to the **absolute path** of `blink.hex` (forward slashes).
3. **Add the constraints** file and set `zedboard_top` as the top module.
4. **Run Synthesis → Implementation → Generate Bitstream.**
5. Power the board, connect the PROG (JTAG) micro-USB cable, set the boot-mode jumpers to JTAG as in the
   ZedBoard manual if the device is not detected, then **Hardware Manager → Open Target → Auto Connect →
   Program Device.**

## What you should see

* LD0-LD7 show a **binary counter** that counts up about every 0.4 s.
* The centre button (BTNC) resets the core and restarts the count.
* **All eight LEDs on at once = the demo's self-check failed** (the multiplier/divider round trip was wrong).

## If it does not work

* **Timing failure** (the core runs at 100 MHz / 4 = 25 MHz): raise `CLK_DIV` to 8 or 16 in `zedboard_top.v`.
  Open-source place-and-route estimates for a different FPGA family were about 27 MHz (RISC-V) and 43 MHz (MIPS),
  so the margin is thin; Artix-7 fabric is normally faster, but this was not checked in Vivado.
* **No LED activity:** check that the program file was loaded (a wrong `$readmemh` path leaves the memory as NOPs),
  that BTNC is not stuck, and the pin assignments.
* **Vivado warns about a generated clock:** the core clock is derived by a divider and buffered with a BUFG
  (`CLOCK_BUFFER_TYPE`); the constraints file defines it as `core_clk`.
