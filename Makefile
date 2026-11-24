# make test                       - directed + random tests vs golden ISS (RTL in iverilog)
# make run T=tests/06_fibonacci.s - run one program, print registers/perf
# make wave T=docs/hazard_demo.s  - VCD (build/wave.vcd) + SVG waveform (docs/waveform.svg)
# make diagram                    - pipeline diagram SVG (docs/pipeline_hazards.svg)
# make synth                      - Yosys synthesis for Xilinx 7-series (resource report)
# make mutate                     - prove the tests catch broken hazard logic
SRCS = $(wildcard rtl/*.v) tb/tb_riscv.v
T ?= tests/06_fibonacci.s

test:
	python3 sw/run_tests.py 300
build/sim: $(SRCS)
	@mkdir -p build
	iverilog -g2012 -Wall -Wno-timescale -o build/sim $(SRCS)
run: build/sim
	python3 sw/asm.py $(T) build/prog.hex && vvp build/sim +hex=build/prog.hex | grep -v WARNING
wave: build/sim
	python3 sw/asm.py $(T) build/prog.hex && vvp build/sim +hex=build/prog.hex +vcd >/dev/null
	python3 sw/vcd2svg.py build/wave.vcd docs/waveform.svg 0 40
	@echo "wrote docs/waveform.svg; open build/wave.vcd in GTKWave for the full trace"
diagram: build/sim
	python3 sw/pipeline_diagram.py docs/hazard_demo.s docs/pipeline_hazards.svg 0 200
synth:
	sw/synth.sh
mutate:
	sw/mutation_check.sh
clean:
	rm -rf build/*
.PHONY: test run wave diagram synth mutate clean
