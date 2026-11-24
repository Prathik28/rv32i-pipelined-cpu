`timescale 1ns/1ps
// Testbench: runs +hex=prog.hex until the program stores to the HALT register, then dumps
// registers, data memory, exit code and performance counters for the Python checker.
// Options: +maxcycles=N  +vcd (waveform)  +trace (per-cycle pipeline trace)
module tb_riscv;
    reg clk = 0, rst = 1;
    wire halt;
    wire [31:0] exit_code;
    wire [15:0] leds;
    integer i, maxc;
    reg trace;

    riscv_soc dut (.clk(clk), .rst(rst), .halt(halt), .exit_code(exit_code), .leds(leds));
    always #5 clk = ~clk;

    initial begin
        if (!$value$plusargs("maxcycles=%d", maxc)) maxc = 200000;
        trace = $test$plusargs("trace");
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/wave.vcd");
            $dumpvars(0, tb_riscv);
        end
        repeat (3) @(posedge clk);
        #1 rst = 0;
    end

    // per-cycle pipeline trace (+trace): cycle, PCs in IF ID EX MEM WB (FFFFFFFF = bubble),
    // then flags: load_use ex_stall mispredict trap fwd_a fwd_b
    reg [31:0] s_mem_pc = 32'hFFFFFFFF, s_wb_pc = 32'hFFFFFFFF;
    always @(posedge clk) begin
        s_wb_pc  <= s_mem_pc;
        s_mem_pc <= (dut.u_core.idex_valid && dut.u_core.ex_commit) ? dut.u_core.idex_pc : 32'hFFFFFFFF;
    end
    always @(posedge clk) if (!rst && trace) begin
        $display("TRACE %0d %08x %08x %08x %08x %08x %0d %0d %0d %0d %0d %0d",
            dut.u_core.perf_cycles,
            dut.u_core.pc,
            dut.u_core.ifid_valid ? dut.u_core.ifid_pc : 32'hFFFFFFFF,
            dut.u_core.idex_valid ? dut.u_core.idex_pc : 32'hFFFFFFFF,
            s_mem_pc, s_wb_pc,
            dut.u_core.load_use && !dut.u_core.ex_stall, dut.u_core.ex_stall,
            dut.u_core.mispredict, dut.u_core.trap_take,
            dut.u_core.fwd_a, dut.u_core.fwd_b);
    end

    always @(posedge clk) begin
        if (!rst && halt) begin
            #1;
            $display("");
            $display("----");
            for (i = 0; i < 32; i = i + 1)
                $display("REG %0d %08x", i, dut.u_core.rf.regs[i]);
            for (i = 0; i < 1024; i = i + 1)
                if ({dut.u_dmem.b3[i], dut.u_dmem.b2[i], dut.u_dmem.b1[i], dut.u_dmem.b0[i]} != 0)
                    $display("MEM %0d %08x", i*4,
                        {dut.u_dmem.b3[i], dut.u_dmem.b2[i], dut.u_dmem.b1[i], dut.u_dmem.b0[i]});
            $display("EXIT %0d", exit_code);
            $display("PERF %0d %0d %0d %0d %0d %0d %0d %0d",
                dut.u_core.perf_cycles, dut.u_core.perf_instret,
                dut.u_core.perf_stall_lu, dut.u_core.perf_stall_div,
                dut.u_core.perf_flushes, dut.u_core.perf_branches,
                dut.u_core.perf_mispred, dut.u_core.perf_traps);
            $display("DONE");
            $finish;
        end else if (!rst && dut.u_core.perf_cycles > maxc) begin
            $display("TIMEOUT");
            $finish;
        end
    end
endmodule
