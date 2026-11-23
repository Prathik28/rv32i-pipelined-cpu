# make test        - run directed + 300 random tests against the golden ISS
# make run T=tests/06_fibonacci.s   - run one program, dump regs
# make wave T=...  - same, plus build/wave.vcd for GTKWave
# make mutate      - prove the tests catch broken hazard logic
SRCS = $(wildcard rtl/*.v) tb/tb_riscv.v
T ?= tests/06_fibonacci.s

test:
	python3 sw/run_tests.py 300
build/sim: $(SRCS)
	iverilog -g2012 -Wall -Wno-timescale -o build/sim $(SRCS)
run: build/sim
	python3 sw/asm.py $(T) build/prog.hex && vvp build/sim +hex=build/prog.hex
wave: build/sim
	python3 sw/asm.py $(T) build/prog.hex && vvp build/sim +hex=build/prog.hex +vcd >/dev/null && echo "open build/wave.vcd in GTKWave"
mutate:
	sw/mutation_check.sh
clean:
	rm -rf build/*
.PHONY: test run wave mutate clean
