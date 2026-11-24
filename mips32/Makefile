# make test     - directed + 200 random programs vs the golden ISS (RTL in iverilog)
# make run T=tests/06_fibonacci.s
# make diagram  - pipeline diagram SVG (docs/pipeline_hazards.svg)
# make mutate   - prove the tests catch broken hazard logic (ONLY=regex runs a subset)
SRCS = $(wildcard rtl/*.v) tb/tb_mips.v
T ?= tests/06_fibonacci.s

test:
	python3 sw/run_tests.py 200
build/sim: $(SRCS)
	@mkdir -p build
	iverilog -g2012 -Wall -Wno-timescale -o build/sim $(SRCS)
run: build/sim
	python3 sw/masm.py $(T) build/prog.hex && vvp build/sim +hex=build/prog.hex | grep -v WARNING
diagram: build/sim
	python3 sw/pipeline_diagram.py docs/hazard_demo.s docs/pipeline_hazards.svg 0 200
mutate:
	sw/mutation_check.sh
clean:
	rm -rf build/*
.PHONY: test run diagram mutate clean
